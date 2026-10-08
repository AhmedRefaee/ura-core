-- Follow-up to 20260925120300_delivery_receipt_storage_buckets.sql.
--
-- Those policies cast the first path segment with ::uuid. Postgres does not
-- promise to evaluate `bucket_id = '...'` before the cast, and storage.objects
-- policies are checked against objects in *every* bucket -- so an object in
-- some other bucket whose path doesn't start with a UUID could make the cast
-- throw and break reads/uploads there. Comparing as text can't throw.

DROP POLICY IF EXISTS "Commercial roles can upload project letterheads" ON storage.objects;
CREATE POLICY "Commercial roles can upload project letterheads" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'project-letterheads'
  AND public.get_user_role() = ANY (ARRAY['verifier'::public.user_role, 'manager'::public.user_role, 'admin'::public.user_role])
  AND (storage.foldername(name))[1] = public.auth_org_id()::text
);

DROP POLICY IF EXISTS "Commercial roles can replace project letterheads" ON storage.objects;
CREATE POLICY "Commercial roles can replace project letterheads" ON storage.objects
FOR UPDATE USING (
  bucket_id = 'project-letterheads'
  AND public.get_user_role() = ANY (ARRAY['verifier'::public.user_role, 'manager'::public.user_role, 'admin'::public.user_role])
  AND (storage.foldername(name))[1] = public.auth_org_id()::text
);

DROP POLICY IF EXISTS "Commercial roles can delete project letterheads" ON storage.objects;
CREATE POLICY "Commercial roles can delete project letterheads" ON storage.objects
FOR DELETE USING (
  bucket_id = 'project-letterheads'
  AND public.get_user_role() = ANY (ARRAY['verifier'::public.user_role, 'manager'::public.user_role, 'admin'::public.user_role])
  AND (storage.foldername(name))[1] = public.auth_org_id()::text
);

DROP POLICY IF EXISTS "Approved users can read project letterheads" ON storage.objects;
CREATE POLICY "Approved users can read project letterheads" ON storage.objects
FOR SELECT USING (
  bucket_id = 'project-letterheads'
  AND public.is_current_user_approved()
  AND (storage.foldername(name))[1] = public.auth_org_id()::text
);

DROP POLICY IF EXISTS "Reps can upload delivery receipt PDFs" ON storage.objects;
CREATE POLICY "Reps can upload delivery receipt PDFs" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'delivery-receipts'
  AND public.get_user_role() = ANY (ARRAY['rep'::public.user_role, 'admin'::public.user_role])
  AND (storage.foldername(name))[1] = public.auth_org_id()::text
);

DROP POLICY IF EXISTS "Approved users can read delivery receipt PDFs" ON storage.objects;
CREATE POLICY "Approved users can read delivery receipt PDFs" ON storage.objects
FOR SELECT USING (
  bucket_id = 'delivery-receipts'
  AND public.is_current_user_approved()
  AND (storage.foldername(name))[1] = public.auth_org_id()::text
);
