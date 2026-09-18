# Supabase storage for EThesisHub

Thesis documents (chapter versions, title-defence presentations and
justifications, final manuscripts) live in a Supabase Storage bucket.
Everything else — accounts, theses, the workflow, authorization — is Firebase.

## Why there is an edge function

The app authenticates with **Firebase Auth**. The Supabase client is
initialised with the publishable key and **no Supabase session**, so every
request the app makes to Supabase arrives as the same anonymous principal.

That has one consequence that shapes this whole directory: **Supabase RLS
cannot tell one EThesisHub user from another.** A private bucket would be
all-or-nothing, and a signed URL minted in the client would be worthless —
any client could sign any path.

So authorization for documents lives in one place the client cannot forge:
the `document-url` edge function. It holds the service-role key, verifies the
caller's Firebase ID token, asks Firestore whether that caller is on the
thesis, and only then signs a short-lived URL. The decision it applies is the
same one `firestore.rules` applies to the thesis (`mayReadThesis`), plus the
dean's chapter-file exclusion and the archived-manuscript opening — see
`functions/document-url/authorize.ts`, which is unit-tested in
`authorize_test.ts`.

## The bucket MUST be private

None of the above means anything if the object is fetchable without a
signature. With a public bucket, anyone holding a URL — and those URLs are
stored in Firestore, readable by everyone on the thesis — can fetch the file
directly, and the edge function is decorative.

Set the `thesis-documents` bucket to **Private** in the Supabase dashboard
(Storage → the bucket → Configuration → Public = off). The uploads still work
(they use the service path through the client), and reads go through the
function.

> The previous Supabase project (`wevvsskextznmstjfmfo`) was deleted — its
> hostname no longer resolves — so a new project must be provisioned anyway.
> Create the bucket **private** from the start; there is no data to migrate.

## Setup

1. Create the bucket:
   - Storage → New bucket → name `thesis-documents`, **Public off**.
   - Optionally set an allowed MIME list and size limit (the client already
     validates `pdf`/`doc`/`docx`/`ppt`/`pptx` and a size cap; a bucket-level
     list is defence in depth).

2. Point the app at the project. In `lib/core/config/app_config.dart`:
   - `supabaseUrl` → your project URL
   - `supabaseAnonKey` → your project's **publishable** (anon) key
   These are client-side public values by design; they are not secrets.

3. Deploy the function and its secrets (see below).

4. In the app, opening any document now round-trips through the function. A
   reader who is not on the thesis gets a "you do not have access" message
   instead of a file.

## Deploying `document-url`

```sh
supabase functions deploy document-url --project-ref <your-ref>
```

Secrets — set once, never committed:

```sh
supabase secrets set \
  SUPABASE_URL="https://<ref>.supabase.co" \
  SUPABASE_SERVICE_ROLE_KEY="<service-role-key>" \
  FIREBASE_PROJECT_ID="ethesishub-43a04" \
  GCP_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
```

- `SUPABASE_SERVICE_ROLE_KEY` is the only real secret in the app's stack. It
  signs URLs and must never reach a client. It lives here and nowhere else.
- `GCP_SERVICE_ACCOUNT_JSON` is a Google service account with read access to
  Firestore (role: *Cloud Datastore User* is enough). The function reads the
  thesis, the caller's user doc, the nomination and — for a manuscript — the
  archive doc, to make its decision.

## Testing

The authorization logic is pure and unit-tested without a network:

```sh
deno test --allow-net supabase/functions/document-url/authorize_test.ts
```

The token verification and Firestore reads in `index.ts` need a live project.
After deploying, verify by hand:

1. As the thesis leader, open a chapter version → succeeds.
2. As an unrelated student (signed in, verified), request the same path via
   the function → **403 forbidden**.
3. As the dean, open the manuscript → succeeds; open a chapter version →
   **403** (the dean sees that a chapter is approved, not its files).
4. Fetch a stored `manuscriptUrl` directly in a browser while signed out →
   **fails** (proves the bucket is private).
5. Open an archived thesis's manuscript as any active user → succeeds
   (the repository is meant to be browsed).
