-- Allow storage actors to create entities
CREATE POLICY "Storage actors can create entities" ON "public"."entities" 
FOR INSERT WITH CHECK (
  ("public"."get_user_role"() = 'storage_actor'::"public"."user_role")
);

-- Allow storage actors to update entities
CREATE POLICY "Storage actors can update entities" ON "public"."entities" 
FOR UPDATE USING (
  ("public"."get_user_role"() = 'storage_actor'::"public"."user_role") 
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

-- Allow storage actors to delete entities
CREATE POLICY "Storage actors can delete entities" ON "public"."entities" 
FOR DELETE USING (
  ("public"."get_user_role"() = 'storage_actor'::"public"."user_role") 
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);
