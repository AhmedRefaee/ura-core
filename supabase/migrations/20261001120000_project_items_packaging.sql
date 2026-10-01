-- Optional packaging definition on a project_item, for converting an actual
-- delivery into the quotation's registered unit on a سند (e.g. "1 كرتون =
-- 1.65 كجم × 4" -- someone receiving 2.75 kg × 4 packs can have the app work
-- out that's ~1.67 كرتون, instead of guessing). All three columns null (the
-- default, and every existing row) means the item has no such relationship;
-- سند quantity entry is unaffected, exactly as before this existed.
--
-- packaging_base_unit stores a QuantityUnit enum name (see
-- lib/shared/logic/unit_conversion.dart), e.g. 'kilogram' -- plain text, not
-- a Postgres enum type, so adding a unit there never needs a migration here.
--
-- Not settable via Excel import (replace_project_items) yet -- out of scope
-- for now; items imported that way simply have no packaging until someone
-- sets it from the item form, same as any item created before this existed.
--
-- get_project_items is DROPPED and re-created rather than CREATE OR
-- REPLACE'd: its return type changes, which OR REPLACE refuses (established
-- pattern -- see 20260926120000_project_items_categories.sql).

ALTER TABLE "public"."project_items"
    ADD COLUMN "packaging_unit_size" numeric,
    ADD COLUMN "packaging_unit_count" numeric,
    ADD COLUMN "packaging_base_unit" "text";

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
    "pi"."item_name", "pi"."description", "pi"."quantity", "pi"."unit",
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."unit_price" ELSE NULL END,
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."total_price" ELSE NULL END,
    "pi"."packaging_unit_size", "pi"."packaging_unit_count", "pi"."packaging_base_unit",
    "pi"."created_at"
  FROM "public"."project_items" "pi"
  JOIN "public"."projects" "p" ON "p"."id" = "pi"."project_id"
  WHERE "p"."id" = "p_project_id"
    AND (("p"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
    AND "public"."is_current_user_approved"()
  ORDER BY "pi"."sort_order", "pi"."created_at";
$$;

REVOKE EXECUTE ON FUNCTION "public"."get_project_items"("uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."get_project_items"("uuid") TO "authenticated";
