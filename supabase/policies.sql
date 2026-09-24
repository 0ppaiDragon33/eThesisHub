-- Storage access policies for the private `thesis-documents` bucket.
--
-- Run these in the Supabase dashboard: SQL Editor → paste → Run. They are
-- idempotent (each drops itself first), so re-running is safe.
--
-- THE MODEL
--
-- The app talks to Supabase with the anon (publishable) key and no Supabase
-- session — every request is the same anonymous principal. So these policies
-- cannot tell one reader from another; that decision lives in the
-- `document-url` edge function, which uses the service_role key (and
-- service_role BYPASSES RLS entirely, so no SELECT policy is needed for it).
--
-- What that leaves for RLS here:
--   * READ  — no anon SELECT policy at all, so anon cannot read a byte. This
--             is what makes the bucket private: the only way to read is a
--             signed URL the edge function mints after authorizing the caller.
--   * UPLOAD — anon MAY insert, but only under the `theses/` or `personal/` prefix, so a
--             client cannot scribble elsewhere in the bucket. This is not a
--             full authorization (an anon caller can upload an orphan), but a
--             private bucket makes an orphan unreadable and unreferenced: the
--             function only ever signs paths whose thesis the caller is on,
--             and Firestore rules gate whether a document RECORD may point at
--             an uploaded file. The exposure is storage cost, not data access.
--   * DELETE/UPDATE — none. Nothing anonymous may remove or overwrite a file.
--             Chapter versions are immutable by design (firestore.rules denies
--             version update/delete), so the app never deletes in normal use;
--             the only `storage.delete` call is best-effort orphan cleanup
--             after a failed Firestore write, and it is allowed to fail. The
--             cost is that a failed upload can leave an orphan, which is the
--             safe trade against letting anyone delete anyone's manuscript.
--             Personal files (My files) are deleted by the `document-url`
--             function with service_role, after it checks the caller owns
--             the path. Still no anonymous delete.

-- Uploads, confined to the theses/ and personal/ prefixes. -------------------
drop policy if exists "ethesishub anon upload under theses" on storage.objects;
drop policy if exists "ethesishub anon upload under theses or personal" on storage.objects;
create policy "ethesishub anon upload under theses or personal"
on storage.objects for insert
to anon
with check (
  bucket_id = 'thesis-documents'
  and (storage.foldername(name))[1] in ('theses', 'personal')
);

-- Deliberately NO select / update / delete policy for anon. Reads go through
-- the edge function (service_role); nothing anonymous reads, overwrites or
-- deletes a file. Do not add a "public read" policy — it reopens the exposure
-- the edge function exists to close.
