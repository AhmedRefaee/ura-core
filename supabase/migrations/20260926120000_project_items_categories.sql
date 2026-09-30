-- بنود العقد: categories, ordering, and whole-quotation replace for Excel
-- import.
--
-- A quotation is split into category tables (جدول الكميات : المخبوزات, ...),
-- so items carry a category and a stable position. sort_order is one sequence
-- per project; category order is simply the order categories first appear.
--
-- get_project_items is DROPPED and re-created rather than CREATE OR REPLACE'd:
-- its return type changes, which OR REPLACE refuses, and this project has been
-- bitten before by stale overloads left behind next to a replaced function.

ALTER TABLE "public"."project_items"
    ADD COLUMN "category" "text" DEFAULT ''::"text" NOT NULL,
    ADD COLUMN "sort_order" integer DEFAULT 0 NOT NULL;

DROP FUNCTION IF EXISTS "public"."get_project_items"("uuid");

CREATE FUNCTION "public"."get_project_items"("p_project_id" "uuid") RETURNS TABLE(
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
    "created_at" timestamp with time zone
)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    "pi"."id", "pi"."project_id", "pi"."category", "pi"."sort_order",
    "pi"."item_name", "pi"."description", "pi"."quantity", "pi"."unit",
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."unit_price" ELSE NULL END,
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."total_price" ELSE NULL END,
    "pi"."created_at"
  FROM "public"."project_items" "pi"
  JOIN "public"."projects" "p" ON "p"."id" = "pi"."project_id"
  WHERE "p"."id" = "p_project_id"
    AND (("p"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
    AND "public"."is_current_user_approved"()
  ORDER BY "pi"."sort_order", "pi"."created_at";
$$;

-- Excel import: the file IS the quotation, so it replaces every line in one
-- transaction. Past سندات survive: delivery_receipt_items keeps its own
-- name/unit snapshot and its project_item_id FK is ON DELETE SET NULL.
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
  IF NOT project_item_pricing_visible() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بتعديل بنود العرض');
  END IF;

  SELECT organization_id INTO v_org FROM projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود');
  END IF;
  IF NOT (v_org = auth_org_id() OR is_platform_admin()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا توجد بنود في الملف');
  END IF;

  SELECT count(*) INTO v_bad
  FROM jsonb_array_elements(p_items) e
  WHERE coalesce(trim(e->>'item_name'), '') = ''
     OR coalesce(trim(e->>'unit'), '') = ''
     OR (e->>'quantity') IS NULL
     OR (e->>'quantity')::numeric < 0;
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
