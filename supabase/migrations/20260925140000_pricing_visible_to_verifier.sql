-- Verifiers join the commercial group on project_items: they now see
-- quotation pricing and can add/edit/delete quotation lines (the same
-- function gates both the table's read and write policies). Reps and storage
-- actors still get item/description/unit only.
CREATE OR REPLACE FUNCTION "public"."project_item_pricing_visible"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"])
    OR "public"."is_platform_admin"();
$$;
