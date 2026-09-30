-- سند استلام module: the two Storage buckets it needs.
--
-- Every other bucket in this project (chat-attachments, etc.) was created by
-- hand in the dashboard with no migration for the bucket itself. These are
-- created here via SQL instead, so they're reproducible across environments
-- without a manual dashboard step.
--
-- Both buckets are public (matches the existing chat-attachments bucket --
-- the app always reads back via getPublicUrl, never signed URLs), so access
-- control is entirely the write-side RLS below. Object paths are required to
-- start with the uploader's organization_id (storage.foldername(name))[1]),
-- and every policy checks that segment against auth_org_id() -- without
-- this, any approved user in any organization could read another org's
-- letterhead/PDF by guessing or observing its URL, since storage.objects has
-- no organization_id column of its own to scope by.

INSERT INTO storage.buckets (id, name, public)
VALUES ('project-letterheads', 'project-letterheads', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('delivery-receipts', 'delivery-receipts', true)
ON CONFLICT (id) DO NOTHING;

-- project-letterheads: verifier/manager/admin author projects and their
-- letterhead; every approved org role can read one (same audience as the
-- projects table itself).

DROP POLICY IF EXISTS "Commercial roles can upload project letterheads" ON storage.objects;
CREATE POLICY "Commercial roles can upload project letterheads" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'project-letterheads'
  AND public.get_user_role() = ANY (ARRAY['verifier'::public.user_role, 'manager'::public.user_role, 'admin'::public.user_role])
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);

DROP POLICY IF EXISTS "Commercial roles can replace project letterheads" ON storage.objects;
CREATE POLICY "Commercial roles can replace project letterheads" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'project-letterheads'
  AND public.get_user_role() = ANY (ARRAY['verifier'::public.user_role, 'manager'::public.user_role, 'admin'::public.user_role])
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);

DROP POLICY IF EXISTS "Commercial roles can delete project letterheads" ON storage.objects;
CREATE POLICY "Commercial roles can delete project letterheads" ON storage.objects
FOR DELETE USING (
  bucket_id = 'project-letterheads'
  AND public.get_user_role() = ANY (ARRAY['verifier'::public.user_role, 'manager'::public.user_role, 'admin'::public.user_role])
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);

DROP POLICY IF EXISTS "Approved users can read project letterheads" ON storage.objects;
CREATE POLICY "Approved users can read project letterheads" ON storage.objects
FOR SELECT USING (
  bucket_id = 'project-letterheads'
  AND public.is_current_user_approved()
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);

-- delivery-receipts: reps are the sole creators (matching the table's own
-- INSERT policy); every approved org role can read one, view-only. No
-- UPDATE/DELETE policy for anyone -- a filed سند's PDF is immutable, same
-- reasoning as the delivery_receipts table having no UPDATE policy.

DROP POLICY IF EXISTS "Reps can upload delivery receipt PDFs" ON storage.objects;
CREATE POLICY "Reps can upload delivery receipt PDFs" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'delivery-receipts'
  AND public.get_user_role() = ANY (ARRAY['rep'::public.user_role, 'admin'::public.user_role])
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);

DROP POLICY IF EXISTS "Approved users can read delivery receipt PDFs" ON storage.objects;
CREATE POLICY "Approved users can read delivery receipt PDFs" ON storage.objects
FOR SELECT USING (
  bucket_id = 'delivery-receipts'
  AND public.is_current_user_approved()
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);
