-- Hardening for the سند / بنود العقد functions, from a code review.
--
-- 1. NULL-unsafe guards. For a caller with no profile (e.g. the shipped anon
--    key), get_user_role() and auth_org_id() are NULL, so checks like
--    `IF NOT project_item_pricing_visible()` or `v_role NOT IN (...)` became
--    `IF NULL` and were skipped: replace_project_items would then DELETE every
--    line of any project whose id it was given. Every guard below is written
--    to fail closed, and the functions require an authenticated, approved
--    caller explicitly.
-- 2. The project's default privileges grant EXECUTE on new functions to
--    anon; these are revoked (defence in depth on top of 1).
-- 3. create_delivery_receipt inserted the header and then RETURNed on a bad
--    item, committing a سند with no/partial items that nobody can delete.
--    It now validates everything before writing anything.
-- 4. Both buckets were public, so their org-scoped SELECT policies never
--    applied to public URLs. They are now private; the app reads through
--    short-lived signed URLs, which the SELECT policies do govern.

CREATE OR REPLACE FUNCTION "public"."project_item_pricing_visible"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT coalesce(
           "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]),
           false
         )
    OR coalesce("public"."is_platform_admin"(), false);
$$;

CREATE OR REPLACE FUNCTION "public"."replace_project_items"(
    "p_project_id" "uuid",
    "p_items" "jsonb"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org uuid;
  v_bad int;
  v_count int;
BEGIN
  IF auth.uid() IS NULL
     OR coalesce(is_current_user_approved(), false) IS NOT TRUE
     OR project_item_pricing_visible() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بتعديل بنود العرض');
  END IF;

  SELECT organization_id INTO v_org FROM projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود');
  END IF;
  IF v_org IS DISTINCT FROM auth_org_id() AND coalesce(is_platform_admin(), false) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا توجد بنود في الملف');
  END IF;

  SELECT count(*) INTO v_bad
  FROM jsonb_array_elements(p_items) e
  WHERE coalesce(trim(e->>'item_name'), '') = ''
     OR coalesce(trim(e->>'unit'), '') = ''
     OR jsonb_typeof(e->'quantity') IS DISTINCT FROM 'number'
     OR (e->>'quantity')::numeric < 0
     OR (e ? 'unit_price' AND jsonb_typeof(e->'unit_price') NOT IN ('number', 'null'))
     OR (e ? 'total_price' AND jsonb_typeof(e->'total_price') NOT IN ('number', 'null'));
  IF v_bad > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يوجد ' || v_bad || ' بند ناقص البيانات');
  END IF;

  DELETE FROM project_items WHERE project_id = p_project_id;

  INSERT INTO project_items (
    project_id, category, sort_order, item_name, description,
    quantity, unit, unit_price, total_price, created_by
  )
  SELECT
    p_project_id,
    coalesce(trim(e->>'category'), ''),
    ord::int,
    trim(e->>'item_name'),
    nullif(trim(e->>'description'), ''),
    (e->>'quantity')::numeric,
    trim(e->>'unit'),
    (e->>'unit_price')::numeric,
    (e->>'total_price')::numeric,
    auth.uid()
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, ord);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'count', v_count);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."create_delivery_receipt"(
    "p_entity_id" "uuid",
    "p_project_id" "uuid",
    "p_items" "jsonb",
    "p_order_id" "uuid" DEFAULT NULL::"uuid",
    "p_pdf_url" "text" DEFAULT NULL::"text",
    "p_notes" "text" DEFAULT NULL::"text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role user_role;
  v_project RECORD;
  v_receipt_id uuid;
  v_count int;
  v_valid int;
BEGIN
  v_role := get_user_role();
  IF auth.uid() IS NULL
     OR coalesce(is_current_user_approved(), false) IS NOT TRUE
     OR v_role IS NULL
     OR v_role NOT IN ('rep', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بإنشاء سند');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب اختيار بند واحد على الأقل');
  END IF;

  SELECT * INTO v_project FROM projects WHERE id = p_project_id AND entity_id = p_entity_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود لهذه الجهة');
  END IF;
  IF v_project.organization_id IS DISTINCT FROM auth_org_id() AND coalesce(is_platform_admin(), false) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM orders WHERE id = p_order_id AND entity_id = p_entity_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لا يخص هذه الجهة');
  END IF;

  -- Validate every line before writing anything: a positive number, and an
  -- item that still belongs to this project (the quotation may have been
  -- re-imported while the rep had the form open).
  SELECT count(*),
         count(*) FILTER (
           WHERE jsonb_typeof(e->'quantity_delivered') = 'number'
             AND (e->>'quantity_delivered')::numeric > 0
             AND EXISTS (
               SELECT 1 FROM project_items pi
               WHERE pi.project_id = p_project_id
                 AND pi.id::text = e->>'project_item_id'
             )
         )
    INTO v_count, v_valid
  FROM jsonb_array_elements(p_items) e;
  IF v_valid <> v_count THEN
    RETURN jsonb_build_object('success', false, 'error',
      'بعض البنود لم تعد موجودة في عرض المشروع أو كمياتها غير صحيحة. أعد فتح السند وحاول مجدداً');
  END IF;

  INSERT INTO delivery_receipts (entity_id, project_id, order_id, rep_id, notes, pdf_url, letterhead_image_url_snapshot)
  VALUES (p_entity_id, p_project_id, p_order_id, auth.uid(), p_notes, p_pdf_url, v_project.letterhead_image_url)
  RETURNING id INTO v_receipt_id;

  INSERT INTO delivery_receipt_items (delivery_receipt_id, project_item_id, item_name_snapshot, unit_snapshot, quantity_delivered)
  SELECT v_receipt_id, pi.id, pi.item_name, pi.unit, (e->>'quantity_delivered')::numeric
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, ord)
  JOIN project_items pi ON pi.id::text = e->>'project_item_id' AND pi.project_id = p_project_id
  ORDER BY ord;

  RETURN jsonb_build_object('success', true, 'delivery_receipt_id', v_receipt_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."replace_project_items"("uuid", "jsonb") FROM "anon", PUBLIC;
REVOKE EXECUTE ON FUNCTION "public"."create_delivery_receipt"("uuid", "uuid", "jsonb", "uuid", "text", "text") FROM "anon", PUBLIC;
REVOKE EXECUTE ON FUNCTION "public"."get_project_items"("uuid") FROM "anon", PUBLIC;
REVOKE EXECUTE ON FUNCTION "public"."project_item_pricing_visible"() FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."replace_project_items"("uuid", "jsonb") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."create_delivery_receipt"("uuid", "uuid", "jsonb", "uuid", "text", "text") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_project_items"("uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."project_item_pricing_visible"() TO "authenticated";

UPDATE storage.buckets SET public = false WHERE id IN ('project-letterheads', 'delivery-receipts');
