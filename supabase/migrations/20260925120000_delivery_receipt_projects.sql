-- سند استلام module, step 1 of 3: the missing Entity -> Project -> Order
-- layer.
--
-- Orders currently connect straight to entity_id, but one entity can run
-- multiple concurrent projects and an order really belongs to a project, not
-- the entity directly. This adds `projects` and wires `project_id` onto
-- `orders` (nullable -- existing orders have none, and this column alone
-- doesn't make it required going forward; the create-order UI flow is what
-- enforces picking one once an entity is chosen).
--
-- Read access is intentionally open to every approved org role: a rep needs
-- a project's name + letterhead to file a سند, not just the verifier/manager
-- who authors the project. Pricing lives on project_items (next migration),
-- never here.

CREATE TABLE IF NOT EXISTS "public"."projects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "letterhead_image_url" "text",
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid",
    CONSTRAINT "projects_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."projects" OWNER TO "postgres";

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");

ALTER TABLE ONLY "public"."projects"
    ADD CONSTRAINT "projects_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");

CREATE OR REPLACE TRIGGER "set_org_id_projects" BEFORE INSERT ON "public"."projects" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();

ALTER TABLE "public"."projects" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Approved users can view projects" ON "public"."projects" FOR SELECT USING (
  ((SELECT "profiles"."is_approved" FROM "public"."profiles" WHERE ("profiles"."id" = "auth"."uid"())) = true)
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

CREATE POLICY "Verifiers and managers can create projects" ON "public"."projects" FOR INSERT WITH CHECK (
  "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"])
);

CREATE POLICY "Verifiers and managers can update projects" ON "public"."projects" FOR UPDATE USING (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

CREATE POLICY "Verifiers and managers can delete projects" ON "public"."projects" FOR DELETE USING (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

GRANT ALL ON TABLE "public"."projects" TO "anon";
GRANT ALL ON TABLE "public"."projects" TO "authenticated";
GRANT ALL ON TABLE "public"."projects" TO "service_role";

ALTER TABLE "public"."orders" ADD COLUMN "project_id" "uuid";

ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id");
