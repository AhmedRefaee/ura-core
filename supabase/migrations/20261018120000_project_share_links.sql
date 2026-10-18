-- Share links: a read-only view of a project's بنود for the outside entity
-- (الجهة) that owns the project -- no account, the link itself is the access.
--
-- A verifier/manager/admin creates a link for one project and sends it (e.g.
-- over WhatsApp). Whoever opens it sees the project name, entity name,
-- letterhead, and each item's category / name / description / unit. NEVER
-- quantity, prices or packaging: get_shared_project selects only the allowed
-- columns, so nothing else ever leaves the database, whatever the client does.
--
-- Access dies when the link is revoked (revoked_at) or passes expires_at.
-- Tokens are two v4 UUIDs' worth of randomness (~244 bits) -- not guessable,
-- so get_shared_project is the one function here granted to anon.
--
-- organization_id is set from the project inside create_project_share_link,
-- not by the set_organization_id() trigger: that trigger writes the caller's
-- auth_org_id(), which is NULL for the platform admin.

CREATE TABLE IF NOT EXISTS "public"."project_share_links" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "project_id" "uuid" NOT NULL,
    "token" "text" NOT NULL,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid",
    CONSTRAINT "project_share_links_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "project_share_links_token_key" UNIQUE ("token")
);

ALTER TABLE "public"."project_share_links" OWNER TO "postgres";

ALTER TABLE ONLY "public"."project_share_links"
    ADD CONSTRAINT "project_share_links_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."project_share_links"
    ADD CONSTRAINT "project_share_links_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."project_share_links"
    ADD CONSTRAINT "project_share_links_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");

CREATE INDEX IF NOT EXISTS "project_share_links_project_id_idx" ON "public"."project_share_links" ("project_id");

ALTER TABLE "public"."project_share_links" ENABLE ROW LEVEL SECURITY;

-- Read-only for the roles that manage projects; every write goes through the
-- RPCs below, so there are no INSERT/UPDATE/DELETE policies.
CREATE POLICY "Commercial roles can view project share links" ON "public"."project_share_links" FOR SELECT USING (
  coalesce("public"."is_current_user_approved"(), false)
  AND (
    (
      coalesce("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]), false)
      AND "organization_id" = "public"."auth_org_id"()
    )
    OR coalesce("public"."is_platform_admin"(), false)
  )
);

REVOKE ALL ON TABLE "public"."project_share_links" FROM "anon", PUBLIC;
REVOKE ALL ON TABLE "public"."project_share_links" FROM "authenticated";
GRANT SELECT ON TABLE "public"."project_share_links" TO "authenticated";
GRANT ALL ON TABLE "public"."project_share_links" TO "service_role";

-- Shared guard for the two write RPCs: an approved verifier/manager/admin of
-- the project's org, or the platform admin. Fails closed on any NULL.
CREATE OR REPLACE FUNCTION "public"."can_manage_project_share_links"("p_org" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT "auth"."uid"() IS NOT NULL
    AND (
      coalesce("public"."is_platform_admin"(), false)
      OR (
        coalesce("public"."is_current_user_approved"(), false)
        AND coalesce("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]), false)
        AND "p_org" IS NOT NULL
        AND "p_org" = "public"."auth_org_id"()
      )
    );
$$;

REVOKE EXECUTE ON FUNCTION "public"."can_manage_project_share_links"("uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."can_manage_project_share_links"("uuid") TO "authenticated";

CREATE OR REPLACE FUNCTION "public"."create_project_share_link"(
    "p_project_id" "uuid",
    "p_expires_at" timestamp with time zone DEFAULT NULL
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

  INSERT INTO project_share_links (project_id, token, expires_at, created_by, organization_id)
  VALUES (p_project_id, v_token, p_expires_at, auth.uid(), v_org)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'id', v_id, 'token', v_token);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."create_project_share_link"("uuid", timestamp with time zone) FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."create_project_share_link"("uuid", timestamp with time zone) TO "authenticated";

CREATE OR REPLACE FUNCTION "public"."revoke_project_share_link"("p_link_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org uuid;
BEGIN
  SELECT organization_id INTO v_org FROM project_share_links WHERE id = p_link_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الرابط غير موجود');
  END IF;
  IF can_manage_project_share_links(v_org) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  UPDATE project_share_links SET revoked_at = now()
  WHERE id = p_link_id AND revoked_at IS NULL;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."revoke_project_share_link"("uuid") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."revoke_project_share_link"("uuid") TO "authenticated";

-- The one anon-callable function. NULL for a missing/unknown/revoked/expired
-- token -- the caller can't tell those apart, by design. Selects ONLY the
-- columns the outside entity may see.
CREATE OR REPLACE FUNCTION "public"."get_shared_project"("p_token" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT jsonb_build_object(
    'project_name', "p"."name",
    'entity_name', "e"."name",
    'letterhead_path', "p"."letterhead_image_url",
    'items', coalesce((
      SELECT jsonb_agg(
        jsonb_build_object(
          'category', "pi"."category",
          'item_name', "pi"."item_name",
          'description', "pi"."description",
          'unit', "pi"."unit"
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

REVOKE EXECUTE ON FUNCTION "public"."get_shared_project"("text") FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."get_shared_project"("text") TO "anon";
GRANT EXECUTE ON FUNCTION "public"."get_shared_project"("text") TO "authenticated";

-- Letterhead for the shared view. The bucket is private and its existing
-- SELECT policy is org-scoped, which an anon viewer can never pass. This lets
-- anyone sign exactly the letterhead objects of projects that currently have
-- a live share link -- nothing else in the bucket. The path itself is only
-- ever handed out by get_shared_project. Stored values may be a bare path or
-- a pre-private-bucket full URL (see SignedStorageUrl.pathOf), so both match.
CREATE OR REPLACE FUNCTION "public"."letterhead_is_shared"("p_name" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1
    FROM "public"."project_share_links" "l"
    JOIN "public"."projects" "p" ON "p"."id" = "l"."project_id"
    WHERE "l"."revoked_at" IS NULL
      AND ("l"."expires_at" IS NULL OR "l"."expires_at" > now())
      AND "p_name" IS NOT NULL
      AND (
        "p"."letterhead_image_url" = "p_name"
        OR split_part("p"."letterhead_image_url", '?', 1) LIKE '%/project-letterheads/' || "p_name"
      )
  );
$$;

REVOKE EXECUTE ON FUNCTION "public"."letterhead_is_shared"("text") FROM PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."letterhead_is_shared"("text") TO "anon";
GRANT EXECUTE ON FUNCTION "public"."letterhead_is_shared"("text") TO "authenticated";

DROP POLICY IF EXISTS "Shared project letterheads are readable" ON storage.objects;
CREATE POLICY "Shared project letterheads are readable" ON storage.objects
FOR SELECT TO "anon", "authenticated" USING (
  bucket_id = 'project-letterheads'
  AND public.letterhead_is_shared(name)
);
