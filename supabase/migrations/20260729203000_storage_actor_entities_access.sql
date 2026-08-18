-- These policies were originally applied by hand in the dashboard, so a plain
-- CREATE POLICY fails with 42710 ("already exists") and aborts the migration.
-- Dropping first makes this replayable and converges the database on the
-- definitions below, whichever of the three already happen to exist.

-- Allow storage actors to create entities
DROP POLICY IF EXISTS "Storage actors can create entities" ON "public"."entities";
CREATE POLICY "Storage actors can create entities" ON "public"."entities"
FOR INSERT WITH CHECK (
  ("public"."get_user_role"() = 'storage_actor'::"public"."user_role")
);

-- Allow storage actors to update entities
DROP POLICY IF EXISTS "Storage actors can update entities" ON "public"."entities";
CREATE POLICY "Storage actors can update entities" ON "public"."entities"
FOR UPDATE USING (
  ("public"."get_user_role"() = 'storage_actor'::"public"."user_role")
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

-- Allow storage actors to delete entities
DROP POLICY IF EXISTS "Storage actors can delete entities" ON "public"."entities";
CREATE POLICY "Storage actors can delete entities" ON "public"."entities"
FOR DELETE USING (
  ("public"."get_user_role"() = 'storage_actor'::"public"."user_role")
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);
