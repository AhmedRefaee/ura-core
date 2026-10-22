-- Portal سند split per category: keep the category in submission_meta so
-- the approver's regenerated PDF (and the submitter's own view) prints the
-- same "الفئة : …" heading above the items as the submitter saw.
--
-- submit_shared_receipt whitelists p_meta's keys; this adds 'category'
-- (trimmed, capped at 200 chars, NULL when absent). Same signature, so
-- CREATE OR REPLACE keeps the grants; they are re-stated anyway.
--
-- p_meta:  {date_mode: today|blank|custom, custom_date?, full_description?, category?}
CREATE OR REPLACE FUNCTION "public"."submit_shared_receipt"(
    "p_token" "text",
    "p_submitter_name" "text",
    "p_submitter_phone" "text",
    "p_items" "jsonb",
    "p_notes" "text" DEFAULT NULL,
    "p_meta" "jsonb" DEFAULT NULL
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_link RECORD;
  v_project RECORD;
  v_name text := nullif(trim(p_submitter_name), '');
  v_phone text := nullif(trim(p_submitter_phone), '');
  v_receipt_id uuid;
  v_count int;
  v_valid int;
  v_mode text;
  v_meta jsonb;
BEGIN
  SELECT * INTO v_link FROM project_share_links
  WHERE coalesce(length(p_token), 0) >= 32
    AND token = p_token
    AND revoked_at IS NULL
    AND (expires_at IS NULL OR expires_at > now());
  IF NOT FOUND OR v_link.can_submit IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الرابط لا يسمح بإنشاء سند');
  END IF;

  IF v_name IS NULL OR length(v_name) > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'أدخل اسمك');
  END IF;
  IF v_phone IS NOT NULL AND length(v_phone) > 30 THEN
    RETURN jsonb_build_object('success', false, 'error', 'رقم الجوال غير صحيح');
  END IF;
  IF p_notes IS NOT NULL AND length(p_notes) > 1000 THEN
    RETURN jsonb_build_object('success', false, 'error', 'الملاحظات طويلة جداً');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 OR jsonb_array_length(p_items) > 300 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب اختيار بند واحد على الأقل');
  END IF;

  -- Bounded backlog: one leaked link can't bury the approvers.
  IF (SELECT count(*) FROM delivery_receipts
      WHERE source_link_id = v_link.id AND status = 'pending' AND deleted_at IS NULL) >= 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'لديك سندات كثيرة بانتظار الاعتماد. انتظر مراجعتها');
  END IF;

  SELECT * INTO v_project FROM projects WHERE id = v_link.project_id;

  v_count := jsonb_array_length(p_items);

  IF (SELECT count(DISTINCT e->>'project_item_id') FROM jsonb_array_elements(p_items) e) <> v_count THEN
    RETURN jsonb_build_object('success', false, 'error', 'بند مكرر في السند');
  END IF;

  -- CASE keeps the numeric cast from running on a non-number.
  SELECT count(*) INTO v_valid
  FROM jsonb_array_elements(p_items) e
  WHERE CASE WHEN jsonb_typeof(e->'quantity_delivered') = 'number'
             THEN (e->>'quantity_delivered')::numeric > 0 AND (e->>'quantity_delivered')::numeric < 1000000000
             ELSE false END
    AND length(coalesce(e->>'notes', '')) <= 500
    AND EXISTS (
      SELECT 1 FROM project_items pi
      WHERE pi.project_id = v_link.project_id
        AND pi.id::text = e->>'project_item_id'
    );
  IF v_valid <> v_count THEN
    RETURN jsonb_build_object('success', false, 'error',
      'بعض البنود لم تعد موجودة أو كمياتها غير صحيحة. أعد فتح الصفحة وحاول مجدداً');
  END IF;

  v_mode := coalesce(p_meta->>'date_mode', 'today');
  IF v_mode NOT IN ('today', 'blank', 'custom') THEN v_mode := 'today'; END IF;
  v_meta := jsonb_build_object(
    'date_mode', v_mode,
    'custom_date', CASE WHEN v_mode = 'custom' THEN p_meta->>'custom_date' END,
    'full_description', coalesce(p_meta->>'full_description', 'false') = 'true',
    'category', left(nullif(trim(p_meta->>'category'), ''), 200)
  );

  INSERT INTO delivery_receipts (
    entity_id, project_id, rep_id, notes, letterhead_image_url_snapshot,
    status, source_link_id, submitter_name, submitter_phone, submission_meta
  )
  VALUES (
    v_project.entity_id, v_project.id, NULL, nullif(trim(p_notes), ''), v_project.letterhead_image_url,
    'pending', v_link.id, v_name, v_phone, v_meta
  )
  RETURNING id INTO v_receipt_id;

  -- The BEFORE INSERT trigger stamps auth_org_id(), which is NULL for anon.
  UPDATE delivery_receipts SET organization_id = v_project.organization_id WHERE id = v_receipt_id;

  INSERT INTO delivery_receipt_items (delivery_receipt_id, project_item_id, item_name_snapshot, unit_snapshot, quantity_delivered, notes)
  SELECT v_receipt_id, pi.id, pi.item_name, pi.unit, (e->>'quantity_delivered')::numeric,
         NULLIF(trim(both from (e->>'notes')), '')
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, ord)
  JOIN project_items pi ON pi.id::text = e->>'project_item_id' AND pi.project_id = v_link.project_id
  ORDER BY ord;

  RETURN jsonb_build_object('success', true, 'delivery_receipt_id', v_receipt_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."submit_shared_receipt"("text", "text", "text", "jsonb", "text", "jsonb") FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."submit_shared_receipt"("text", "text", "text", "jsonb", "text", "jsonb") TO "anon", "authenticated";
