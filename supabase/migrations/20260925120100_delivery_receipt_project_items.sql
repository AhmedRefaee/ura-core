-- سند استلام module, step 2 of 3: project_items -- the digitized خطاب
-- العرض (quotation) Ahmed already produces by hand per project.
--
-- Two audiences: commercial roles get full pricing, everyone else gets
-- item/description/unit only. Confirmed for manager+admin; whether verifier
-- also sees pricing is still open and deliberately centralized in ONE
-- function (project_item_pricing_visible) so widening/narrowing it later is
-- a one-line change here, not a multi-object migration.
--
-- The base table's row-level policy is gated by that same function -- this
-- is real server-side enforcement (a non-commercial role gets zero rows
-- querying the table directly), not just "the app doesn't ask for those
-- columns". Every role reads through get_project_items() instead, which
-- nulls the price columns for whoever the function says shouldn't see them.

CREATE TABLE IF NOT EXISTS "public"."project_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "item_name" "text" NOT NULL,
    "description" "text",
    "quantity" numeric NOT NULL,
    "unit" "text" NOT NULL,
    "unit_price" numeric,
    "total_price" numeric,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "project_items_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."project_items" OWNER TO "postgres";

ALTER TABLE ONLY "public"."project_items"
    ADD CONSTRAINT "project_items_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."project_items"
    ADD CONSTRAINT "project_items_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");

ALTER TABLE "public"."project_items" ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION "public"."project_item_pricing_visible"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT "public"."get_user_role"() = ANY (ARRAY['manager'::"public"."user_role", 'admin'::"public"."user_role"])
    OR "public"."is_platform_admin"();
$$;

-- project_items carries no organization_id of its own (mirrors
-- order_template_items) -- org scoping goes through the parent project.
CREATE POLICY "org_isolation" ON "public"."project_items" TO "authenticated" USING (
  "public"."project_item_pricing_visible"()
  AND EXISTS (
    SELECT 1 FROM "public"."projects" "p"
    WHERE ("p"."id" = "project_items"."project_id")
      AND (("p"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
  )
) WITH CHECK (
  "public"."project_item_pricing_visible"()
  AND EXISTS (
    SELECT 1 FROM "public"."projects" "p"
    WHERE ("p"."id" = "project_items"."project_id")
      AND (("p"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
  )
);

GRANT ALL ON TABLE "public"."project_items" TO "anon";
GRANT ALL ON TABLE "public"."project_items" TO "authenticated";
GRANT ALL ON TABLE "public"."project_items" TO "service_role";

-- Operational read path -- every approved org role calls this (including
-- commercial roles, for one consistent client-side code path). SECURITY
-- DEFINER lets it read rows the caller's own RLS would otherwise hide, but
-- it only ever returns price columns when project_item_pricing_visible().
CREATE OR REPLACE FUNCTION "public"."get_project_items"("p_project_id" "uuid") RETURNS TABLE(
    "id" "uuid",
    "project_id" "uuid",
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
    "pi"."id", "pi"."project_id", "pi"."item_name", "pi"."description", "pi"."quantity", "pi"."unit",
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."unit_price" ELSE NULL END,
    CASE WHEN "public"."project_item_pricing_visible"() THEN "pi"."total_price" ELSE NULL END,
    "pi"."created_at"
  FROM "public"."project_items" "pi"
  JOIN "public"."projects" "p" ON "p"."id" = "pi"."project_id"
  WHERE "p"."id" = "p_project_id"
    AND (("p"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
    AND "public"."is_current_user_approved"();
$$;
