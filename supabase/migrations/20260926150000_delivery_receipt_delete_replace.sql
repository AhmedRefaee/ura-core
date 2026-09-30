-- Reps can delete, and "edit" (replace), a سند they created.
--
-- Deleting archives rather than erases: deleted_at hides the سند from every
-- list, but the row, its items and its PDF stay for audit -- a signed copy
-- may already be in a client's hands. Editing = filing a new سند with
-- p_replaces set: the old one is archived in the same transaction, with
-- replaced_by pointing at the new one, so there is never both or neither.
--
-- create_delivery_receipt gains a parameter, so the old signature is dropped
-- first rather than left behind as a second, unguarded overload.

ALTER TABLE "public"."delivery_receipts"
    ADD COLUMN "deleted_at" timestamp with time zone,
    ADD COLUMN "deleted_by" "uuid" REFERENCES "public"."profiles"("id"),
    ADD COLUMN "replaced_by" "uuid" REFERENCES "public"."delivery_receipts"("id");

-- Archived receipts are invisible to every role; their items follow, since
-- the items policy checks the parent row through this table's RLS.
ALTER POLICY "Approved users can view delivery receipts" ON "public"."delivery_receipts" USING (
  "public"."is_current_user_approved"()
  AND "deleted_at" IS NULL
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

CREATE OR REPLACE FUNCTION "public"."delete_delivery_receipt"("p_receipt_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role user_role;
  v_receipt RECORD;
BEGIN
  v_role := get_user_role();
  IF auth.uid() IS NULL
     OR coalesce(is_current_user_approved(), false) IS NOT TRUE
     OR v_role IS NULL
     OR v_role NOT IN ('rep', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بحذف السند');
  END IF;

  SELECT * INTO v_receipt FROM delivery_receipts WHERE id = p_receipt_id AND deleted_at IS NULL FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'السند غير موجود أو محذوف مسبقاً');
  END IF;
  IF v_receipt.organization_id IS DISTINCT FROM auth_org_id() AND coalesce(is_platform_admin(), false) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;
  IF v_receipt.rep_id IS DISTINCT FROM auth.uid() AND v_role <> 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'يحذف السند منشئه فقط');
  END IF;

  UPDATE delivery_receipts SET deleted_at = now(), deleted_by = auth.uid() WHERE id = p_receipt_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

DROP FUNCTION IF EXISTS "public"."create_delivery_receipt"("uuid", "uuid", "jsonb", "uuid", "text", "text");

CREATE FUNCTION "public"."create_delivery_receipt"(
    "p_entity_id" "uuid",
    "p_project_id" "uuid",
    "p_items" "jsonb",
    "p_order_id" "uuid" DEFAULT NULL::"uuid",
    "p_pdf_url" "text" DEFAULT NULL::"text",
    "p_notes" "text" DEFAULT NULL::"text",
    "p_replaces" "uuid" DEFAULT NULL::"uuid"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_role user_role;
  v_project RECORD;
  v_old RECORD;
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

  IF p_replaces IS NOT NULL THEN
    SELECT * INTO v_old FROM delivery_receipts WHERE id = p_replaces AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'السند الأصلي غير موجود أو محذوف');
    END IF;
    IF v_old.organization_id IS DISTINCT FROM v_project.organization_id
       OR (v_old.rep_id IS DISTINCT FROM auth.uid() AND v_role <> 'admin') THEN
      RETURN jsonb_build_object('success', false, 'error', 'يعدّل السند منشئه فقط');
    END IF;
  END IF;

  -- Validate every line before writing anything.
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

  IF p_replaces IS NOT NULL THEN
    UPDATE delivery_receipts
       SET deleted_at = now(), deleted_by = auth.uid(), replaced_by = v_receipt_id
     WHERE id = p_replaces;
  END IF;

  RETURN jsonb_build_object('success', true, 'delivery_receipt_id', v_receipt_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."delete_delivery_receipt"("uuid") FROM "anon", PUBLIC;
REVOKE EXECUTE ON FUNCTION "public"."create_delivery_receipt"("uuid", "uuid", "jsonb", "uuid", "text", "text", "uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."delete_delivery_receipt"("uuid") TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."create_delivery_receipt"("uuid", "uuid", "jsonb", "uuid", "text", "text", "uuid") TO "authenticated";
