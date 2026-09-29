-- The RPC gate (20260929140000) let verifiers create/delete سندات, but
-- missed this second, separate permission surface: the Storage RLS policy
-- that governs uploading the سند's PDF to the delivery-receipts bucket.
-- Without this, a verifier's create_delivery_receipt call would never even
-- run -- the client uploads the PDF to Storage first and only calls the RPC
-- with the resulting URL, so the upload's 403 blocks the whole flow before
-- the RPC is ever reached.

DROP POLICY IF EXISTS "Reps can upload delivery receipt PDFs" ON storage.objects;
CREATE POLICY "Reps and verifiers can upload delivery receipt PDFs" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'delivery-receipts'
  AND public.get_user_role() = ANY (ARRAY['rep'::public.user_role, 'verifier'::public.user_role, 'admin'::public.user_role])
  AND ((storage.foldername(name))[1])::uuid = public.auth_org_id()
);
