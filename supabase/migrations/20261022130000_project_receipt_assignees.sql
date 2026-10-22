-- Reps file سندات only for projects a verifier assigned them to.
--
-- Before this, every approved rep could file a سند for every project in the
-- org and read every project's بنود, including the contract quantity. Now:
--
-- * project_receipt_assignees lists, per project, the reps allowed to file.
--   A verifier/manager/admin manages it from the project page (next to the
--   share-link button) through assign/unassign RPCs -- no write policies.
-- * can_file_receipt_for_project() is the ONE definition of "may file a سند
--   for this project": verifier/admin always (as before); a rep only when
--   assigned. Managers still can't file, exactly as before.
-- * create_delivery_receipt refuses a rep who isn't assigned.
-- * get_project_items returns nothing to a rep who isn't assigned, and the
--   contract quantity is now hidden alongside prices for every role that
--   project_item_pricing_visible() says isn't commercial. Reps type the
--   delivered quantity on the سند; they never needed the contract total.
-- * get_receipt_project_ids() lists the projects the caller may file for, so
--   the app's project picker shows the same thing the server enforces.
--
-- Existing reps lose access until assigned -- deliberate (the user's call,
-- 2026-10-22). Their already-filed سندات are untouched and still visible.

CREATE TABLE IF NOT EXISTS "public"."project_receipt_assignees" (
    "project_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "organization_id" "uuid",
    "assigned_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "project_receipt_assignees_pkey" PRIMARY KEY ("project_id", "user_id")
);

ALTER TABLE "public"."project_receipt_assignees" OWNER TO "postgres";

ALTER TABLE ONLY "public"."project_receipt_assignees"
    ADD CONSTRAINT "project_receipt_assignees_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."project_receipt_assignees"
    ADD CONSTRAINT "project_receipt_assignees_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."project_receipt_assignees"
    ADD CONSTRAINT "project_receipt_assignees_assigned_by_fkey" FOREIGN KEY ("assigned_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."project_receipt_assignees"
    ADD CONSTRAINT "project_receipt_assignees_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");

CREATE INDEX IF NOT EXISTS "project_receipt_assignees_user_id_idx" ON "public"."project_receipt_assignees" ("user_id");

ALTER TABLE "public"."project_receipt_assignees" ENABLE ROW LEVEL SECURITY;

-- Managers of the org see every row; anyone else sees only their own.
CREATE POLICY "View project receipt assignees" ON "public"."project_receipt_assignees" FOR SELECT USING (
  coalesce("public"."is_current_user_approved"(), false)
  AND (
    "user_id" = "auth"."uid"()
    OR coalesce("public"."can_manage_project_share_links"("organization_id"), false)
  )
);

REVOKE ALL ON TABLE "public"."project_receipt_assignees" FROM "anon", PUBLIC;
REVOKE ALL ON TABLE "public"."project_receipt_assignees" FROM "authenticated";
GRANT SELECT ON TABLE "public"."project_receipt_assignees" TO "authenticated";
GRANT ALL ON TABLE "public"."project_receipt_assignees" TO "service_role";

-- ── The one rule ────────────────────────────────────────────────────────────
-- Fails closed on any NULL (unknown project, no session, unapproved, no role).
CREATE OR REPLACE FUNCTION "public"."can_file_receipt_for_project"("p_project_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT coalesce((
    SELECT "auth"."uid"() IS NOT NULL
      AND coalesce("public"."is_current_user_approved"(), false)
      AND ("p"."organization_id" = "public"."auth_org_id"() OR coalesce("public"."is_platform_admin"(), false))
      AND (
        "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'admin'::"public"."user_role"])
        OR (
          "public"."get_user_role"() = 'rep'::"public"."user_role"
          AND EXISTS (
            SELECT 1 FROM "public"."project_receipt_assignees" "a"
            WHERE "a"."project_id" = "p"."id" AND "a"."user_id" = "auth"."uid"()
          )
        )
      )
    FROM "public"."projects" "p"
    WHERE "p"."id" = "p_project_id"
  ), false);
$$;

REVOKE EXECUTE ON FUNCTION "public"."can_file_receipt_for_project"("uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."can_file_receipt_for_project"("uuid") TO "authenticated";

CREATE OR REPLACE FUNCTION "public"."get_receipt_project_ids"() RETURNS SETOF "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT "p"."id" FROM "public"."projects" "p"
  WHERE ("p"."organization_id" = "public"."auth_org_id"() OR coalesce("public"."is_platform_admin"(), false))
    AND "public"."can_file_receipt_for_project"("p"."id");
$$;

REVOKE EXECUTE ON FUNCTION "public"."get_receipt_project_ids"() FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."get_receipt_project_ids"() TO "authenticated";

-- ── Assign / unassign (verifier/manager/admin of the project's org) ─────────
CREATE OR REPLACE FUNCTION "public"."assign_project_receipt_user"("p_project_id" "uuid", "p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود');
  END IF;
  IF can_manage_project_share_links(v_org) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = p_user_id AND role = 'rep' AND is_approved IS TRUE AND organization_id = v_org
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم ليس مندوباً في هذه المؤسسة');
  END IF;

  INSERT INTO project_receipt_assignees (project_id, user_id, organization_id, assigned_by)
  VALUES (p_project_id, p_user_id, v_org, auth.uid())
  ON CONFLICT (project_id, user_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."assign_project_receipt_user"("uuid", "uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."assign_project_receipt_user"("uuid", "uuid") TO "authenticated";

CREATE OR REPLACE FUNCTION "public"."unassign_project_receipt_user"("p_project_id" "uuid", "p_user_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود');
  END IF;
  IF can_manage_project_share_links(v_org) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  DELETE FROM project_receipt_assignees WHERE project_id = p_project_id AND user_id = p_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."unassign_project_receipt_user"("uuid", "uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."unassign_project_receipt_user"("uuid", "uuid") TO "authenticated";

-- ── get_project_items: gated for reps, quantity hidden like prices ──────────
-- Same return type as 20261001120000, so OR REPLACE is enough.
CREATE OR REPLACE FUNCTION "public"."get_project_items"("p_project_id" "uuid") RETURNS TABLE(
    "id" "uuid",
    "project_id" "uuid",
    "category" "text",
    "sort_order" integer,
    "item_name" "text",
    "description" "text",
    "quantity" numeric,
    "unit" "text",
    "unit_price" numeric,
    "total_price" numeric,
    "packaging_unit_size" numeric,
    "packaging_unit_count" numeric,
    "packaging_base_unit" "text",
    "created_at" timestamp with time zone
)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    "pi"."id", "pi"."project_id", "pi"."category", "pi"."sort_order",
    "pi"."item_name", "pi"."description",
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."quantity" ELSE NULL END,
    "pi"."unit",
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."unit_price" ELSE NULL END,
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."total_price" ELSE NULL END,
    "pi"."packaging_unit_size", "pi"."packaging_unit_count", "pi"."packaging_base_unit",
    "pi"."created_at"
  FROM "public"."project_items" "pi"
  JOIN "public"."projects" "p" ON "p"."id" = "pi"."project_id"
  WHERE "p"."id" = "p_project_id"
    AND (("p"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
    AND "public"."is_current_user_approved"()
    AND (
      "public"."get_user_role"() IS DISTINCT FROM 'rep'::"public"."user_role"
      OR "public"."can_file_receipt_for_project"("p"."id")
    )
  ORDER BY "pi"."sort_order", "pi"."created_at";
$$;

REVOKE EXECUTE ON FUNCTION "public"."get_project_items"("uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."get_project_items"("uuid") TO "authenticated";

-- ── create_delivery_receipt: reps must be assigned ──────────────────────────
-- Same signature and body as 20260930130000 plus the assignment check.
CREATE OR REPLACE FUNCTION "public"."create_delivery_receipt"(
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
     OR v_role NOT IN ('rep', 'verifier', 'admin') THEN
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

  IF can_file_receipt_for_project(p_project_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم إسنادك لإنشاء سندات لهذا المشروع');
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

  INSERT INTO delivery_receipt_items (delivery_receipt_id, project_item_id, item_name_snapshot, unit_snapshot, quantity_delivered, notes)
  SELECT v_receipt_id, pi.id, pi.item_name, pi.unit, (e->>'quantity_delivered')::numeric,
         NULLIF(trim(both from (e->>'notes')), '')
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
