-- Outside entities can file a سند through a share link, for approval.
--
-- No account: the link's secret token is the identity. A submission is a
-- delivery_receipts row with status 'pending', rep_id NULL, tied to the link
-- that made it plus the name/phone the submitter typed. Nothing is trusted
-- from the client except which project items and how many; names, units and
-- the project all come from the link / project_items.
--
-- A verifier/manager/admin of the project's org approves (attaching the PDF
-- their app generates -- the submitter never uploads files) or rejects it.
-- Rejecting archives it (deleted_at) with status 'rejected', so it vanishes
-- from internal lists but the submitter still sees it was turned down.
--
-- Links are view-only unless created with can_submit, so links already
-- handed out before this migration cannot start filing سندات.
--
-- Pending/rejected rows are invisible to reps and storage staff: only the
-- commercial roles see (and decide on) them.

-- ── Links: opt-in to submissions ────────────────────────────────────────────
ALTER TABLE "public"."project_share_links"
    ADD COLUMN IF NOT EXISTS "can_submit" boolean NOT NULL DEFAULT false;

-- Signature changes, so the old one is dropped rather than left as a second
-- overload.
DROP FUNCTION IF EXISTS "public"."create_project_share_link"("uuid", timestamp with time zone);

CREATE FUNCTION "public"."create_project_share_link"(
    "p_project_id" "uuid",
    "p_expires_at" timestamp with time zone DEFAULT NULL,
    "p_can_submit" boolean DEFAULT false
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org uuid;
  v_token text;
  v_id uuid;
BEGIN
  SELECT organization_id INTO v_org FROM projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود');
  END IF;
  IF can_manage_project_share_links(v_org) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بمشاركة المشروع');
  END IF;
  IF p_expires_at IS NOT NULL AND p_expires_at <= now() THEN
    RETURN jsonb_build_object('success', false, 'error', 'تاريخ انتهاء الصلاحية غير صالح');
  END IF;

  v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

  INSERT INTO project_share_links (project_id, token, expires_at, can_submit, created_by, organization_id)
  VALUES (p_project_id, v_token, p_expires_at, coalesce(p_can_submit, false), auth.uid(), v_org)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'token', v_token);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."create_project_share_link"("uuid", timestamp with time zone, boolean) FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."create_project_share_link"("uuid", timestamp with time zone, boolean) TO "authenticated";

-- ── Receipts: status + provenance ───────────────────────────────────────────
ALTER TABLE "public"."delivery_receipts"
    ALTER COLUMN "rep_id" DROP NOT NULL,
    ADD COLUMN "status" text NOT NULL DEFAULT 'approved',
    ADD COLUMN "source_link_id" uuid REFERENCES "public"."project_share_links"("id") ON DELETE SET NULL,
    ADD COLUMN "submitter_name" text,
    ADD COLUMN "submitter_phone" text,
    -- How the submitter set up the سند (date choice, full descriptions), so
    -- the approver's app can regenerate the identical PDF.
    ADD COLUMN "submission_meta" jsonb,
    ADD COLUMN "decided_by" uuid REFERENCES "public"."profiles"("id"),
    ADD COLUMN "decided_at" timestamp with time zone,
    ADD CONSTRAINT "delivery_receipts_status_check" CHECK ("status" IN ('approved', 'pending', 'rejected')),
    ADD CONSTRAINT "delivery_receipts_has_author_check" CHECK ("rep_id" IS NOT NULL OR "source_link_id" IS NOT NULL OR "submitter_name" IS NOT NULL);

CREATE INDEX IF NOT EXISTS "delivery_receipts_source_link_idx" ON "public"."delivery_receipts" ("source_link_id") WHERE "source_link_id" IS NOT NULL;

ALTER POLICY "Approved users can view delivery receipts" ON "public"."delivery_receipts" USING (
  "public"."is_current_user_approved"()
  AND "deleted_at" IS NULL
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
  AND (
    "status" = 'approved'
    OR coalesce("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]), false)
    OR coalesce("public"."is_platform_admin"(), false)
  )
);

-- ── What a link holder sees: items now carry ids + packaging ────────────────
-- Still never quantity or prices. The id lets a submission name an item;
-- packaging (e.g. 1 كرتون = 1.65 كجم × 4) drives the quantity calculator and
-- says nothing about how much the project buys.
CREATE OR REPLACE FUNCTION "public"."get_shared_project"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT jsonb_build_object(
    'project_name', "p"."name",
    'entity_name', "e"."name",
    'letterhead_path', "p"."letterhead_image_url",
    'can_submit', "l"."can_submit",
    'items', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'id', "pi"."id",
          'category', "pi"."category",
          'item_name', "pi"."item_name",
          'description', "pi"."description",
          'unit', "pi"."unit",
          'packaging_unit_size', "pi"."packaging_unit_size",
          'packaging_unit_count', "pi"."packaging_unit_count",
          'packaging_base_unit', "pi"."packaging_base_unit"
        )
        ORDER BY "pi"."sort_order", "pi"."created_at"
      )
      FROM "public"."project_items" "pi"
      WHERE "pi"."project_id" = "p"."id"
    ), '[]'::jsonb)
  )
  FROM "public"."project_share_links" "l"
  JOIN "public"."projects" "p" ON "p"."id" = "l"."project_id"
  LEFT JOIN "public"."entities" "e" ON "e"."id" = "p"."entity_id"
  WHERE coalesce(length("p_token"), 0) >= 32
    AND "l"."token" = "p_token"
    AND "l"."revoked_at" IS NULL
    AND ("l"."expires_at" IS NULL OR "l"."expires_at" > now());
$$;

-- ── Submit (anon) ───────────────────────────────────────────────────────────
-- p_items: [{project_item_id, quantity_delivered, notes?}]
-- p_meta:  {date_mode: today|blank|custom, custom_date?, full_description?}
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
    'full_description', coalesce(p_meta->>'full_description', 'false') = 'true'
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

-- ── The submitter's own list (anon) ─────────────────────────────────────────
-- Only receipts made through THIS link: never other links', reps' or the
-- org's. Pending, approved and rejected all show, so they know the outcome.
CREATE OR REPLACE FUNCTION "public"."get_shared_receipts"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'id', "r"."id",
      'status', "r"."status",
      'created_at', "r"."created_at",
      'submitter_name', "r"."submitter_name",
      'notes', "r"."notes",
      'meta', "r"."submission_meta",
      'items', coalesce((
        SELECT jsonb_agg(
          jsonb_build_object(
            'project_item_id', "ri"."project_item_id",
            'item_name', "ri"."item_name_snapshot",
            'unit', "ri"."unit_snapshot",
            'quantity', "ri"."quantity_delivered",
            'notes', "ri"."notes"
          )
          ORDER BY "ri"."id"
        )
        FROM "public"."delivery_receipt_items" "ri"
        WHERE "ri"."delivery_receipt_id" = "r"."id"
      ), '[]'::jsonb)
    )
    ORDER BY "r"."created_at" DESC
  ), '[]'::jsonb)
  FROM "public"."project_share_links" "l"
  JOIN "public"."delivery_receipts" "r" ON "r"."source_link_id" = "l"."id"
  WHERE coalesce(length("p_token"), 0) >= 32
    AND "l"."token" = "p_token"
    AND "l"."revoked_at" IS NULL
    AND ("l"."expires_at" IS NULL OR "l"."expires_at" > now())
    AND ("r"."deleted_at" IS NULL OR "r"."status" = 'rejected');
$$;

REVOKE EXECUTE ON FUNCTION "public"."get_shared_receipts"("text") FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."get_shared_receipts"("text") TO "anon", "authenticated";

-- ── Decide (verifier / manager / admin) ─────────────────────────────────────
CREATE OR REPLACE FUNCTION "public"."approve_delivery_receipt"("p_receipt_id" "uuid", "p_pdf_url" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_receipt RECORD;
BEGIN
  SELECT * INTO v_receipt FROM delivery_receipts WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'السند غير موجود');
  END IF;
  IF can_manage_project_share_links(v_receipt.organization_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح باعتماد السند');
  END IF;
  IF v_receipt.status <> 'pending' OR v_receipt.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'السند ليس بانتظار الاعتماد');
  END IF;
  IF coalesce(trim(p_pdf_url), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ملف السند مطلوب للاعتماد');
  END IF;

  UPDATE delivery_receipts
     SET status = 'approved', pdf_url = p_pdf_url, decided_by = auth.uid(), decided_at = now()
   WHERE id = p_receipt_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."reject_delivery_receipt"("p_receipt_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_receipt RECORD;
BEGIN
  SELECT * INTO v_receipt FROM delivery_receipts WHERE id = p_receipt_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'السند غير موجود');
  END IF;
  IF can_manage_project_share_links(v_receipt.organization_id) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح برفض السند');
  END IF;
  IF v_receipt.status <> 'pending' OR v_receipt.deleted_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'السند ليس بانتظار الاعتماد');
  END IF;

  UPDATE delivery_receipts
     SET status = 'rejected', deleted_at = now(), deleted_by = auth.uid(), decided_by = auth.uid(), decided_at = now()
   WHERE id = p_receipt_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."approve_delivery_receipt"("uuid", "text") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."approve_delivery_receipt"("uuid", "text") TO "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."reject_delivery_receipt"("uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."reject_delivery_receipt"("uuid") TO "authenticated";
