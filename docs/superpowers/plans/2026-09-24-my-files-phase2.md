# My Files — Phase 2 (folders and uploads) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every signed-in user gets a **My files** page where they keep their form copies and their own uploaded files (PDF, Word, PowerPoint, PNG, JPEG) in one-level folders, and can open, rename, move and delete them. Nobody else can see them, not the Dean or the Coordinator either.

**Architecture:** Folders and file records live in Firestore under `users/{uid}/folders` and `users/{uid}/files`, owner-only by rules. Form copies (Phase 1) join a folder through the `folderId` they already carry. The bytes go to the existing private Supabase bucket under `personal/{uid}/{fileId}/…`. The existing `document-url` server function gains a personal branch: it signs a link for the owner only, and it deletes a personal file for the owner only. The anonymous upload policy widens from `theses/` to `theses/` + `personal/`.

**Tech Stack:** Flutter 3.44, Riverpod 2.6.1 (pinned), go_router 17.5.0 (pinned), Cloud Firestore + `fake_cloud_firestore` 4.2.0, Supabase Storage + a Deno edge function (`supabase/functions/document-url`, tests with `deno test`), Firestore rules tested on the emulator.

**Spec:** `docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md`. This plan covers §11 step 2 (spec §6, §7, §8, §9, §12, §13).

## Global Constraints

- **Commit only the files your task names.** The working tree has unrelated uncommitted changes: `android/app/src/main/kotlin/com/example/ethesishub/MainActivity.kt`, `lib/app.dart`, `lib/core/widgets/app_shell.dart`, `lib/core/theme/app_theme.dart`, `lib/features/dashboard/progress_rail.dart`, `lib/features/defence/consolidated_defence_screen.dart`, `lib/core/platform/native_back.dart`, `test/core/platform/`, the deleted `double_back_to_exit` files, `macos/…`, `android/build/`. Never `git add -A`, `git add .`, or `git commit -a`. Stage by explicit path and check `git status --short` before every commit.
- **No new dependencies**, and no bump to any pinned package.
- **Deploy nothing.** No `firebase deploy`, no `supabase functions deploy`, no SQL run against the live project. Firestore rules are tested on the emulator; the edge function with `deno test`. Deployment is a manual step for the project owner (Task 7 lists it).
- **Folders** (`users/{uid}/folders/{folderId}`): exactly `name` (1–60 characters) and `createdAt` (server time at create, unchanged after). One level only; there are no folders inside folders.
- **File records** (`users/{uid}/files/{fileId}`): exactly `name` (1–200), `storagePath`, `contentType`, `sizeBytes` (1 to 26214400, i.e. 25 MB), `folderId` (null or a string of at most 128), `createdAt`. `storagePath` is `personal/{uid}/{fileId}/{generated}.{ext}`, where `{uid}` and `{fileId}` are the record's own. `storagePath`, `contentType`, `sizeBytes` and `createdAt` never change after create.
- **Upload types:** `pdf doc docx ppt pptx png jpg jpeg`. Size cap `kPersonalFileMaxBytes = 25 * 1024 * 1024`. Content is checked by signature: PNG `89 50 4E 47`, JPEG `FF D8 FF` (plus the existing PDF / ZIP-Office / OLE2-Office checks).
- **Owner only** for every read and write of folders, file records and personal storage paths: the signed-in, verified, active owner. No role reaches another person's personal files, the Dean and the Research Coordinator included (spec E9).
- **`document-url`:** a `personal/{uid}/…` path is signed only for that uid while their profile's `active` is `true`. The delete action (`{"path": …, "action": "delete"}`) is allowed only for the caller's own personal path. A delete on a `theses/…` path is refused with 403. Thesis signing behaves exactly as before.
- **Storage policy:** anonymous INSERT allowed under `theses/` **or** `personal/`. There is still no anonymous read, update or delete.
- **Deleting a folder moves its items to the top level**; nothing inside is deleted. Deleting a file asks first, removes the stored object through the server function, then the record.
- **Never throw inside a `runTransaction` closure** (in this app it crashes Android with `MissingPluginException`). This plan adds no transactions; keep it that way.
- User-facing wording in this plan is final copy. Use it verbatim.
- Every commit message ends with the trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Test commands: `flutter test <path>` from the repo root; rules with `cd rules-test && npm test`; the function with `deno test supabase/functions/document-url/`.

## Rulings made while planning (the spec is amended in Task 0)

- **P1:** The last path segment is a **generated** `{uuid}.{ext}`, not the person's own filename. Their filename is kept in the Firestore record's `name`. A generated name always passes the function's strict filename check (`[A-Za-z0-9][A-Za-z0-9_-]*\.[A-Za-z0-9]{1,8}`); real filenames have spaces, accents and brackets.
- **P2:** Deleting a personal file goes through a new, separate `PersonalFileRemover` interface (implemented by `SupabaseStorageService`, with its own provider). `StorageService` itself is not widened, because four test fakes `implements StorageService` and would all break.
- **P3:** Opening a folder **pushes** `/files?folder={id}`. On a phone the system back then closes the folder instead of triggering exit-to-home. The shell location is still `/files`, so the sidebar keeps My files selected.
- **P4:** An item whose `folderId` names a folder that no longer exists shows at the **top level**, so nothing can become unreachable.
- **P5:** The function's personal branch reads `users/{uid}.active === true`, the same test its thesis branch uses. Profiles are created with `active: true`.
- **P6:** If the Firestore record fails to write after an upload, the uploaded object is deleted through the function on a best-effort basis. Without a record it would sit invisible and use storage.
- **P7:** `promptForName` (Phase 1) gains an optional `maxLength`, so folders (60) and files (200) reuse it.
- **P8:** An empty (0-byte) file is refused before upload with *"That file is empty."* The rules would refuse its record anyway.

## File structure

| File | Responsibility |
|---|---|
| `lib/features/titles/file_upload.dart` (modify) | image content types, PNG/JPEG signatures, `kPersonalFileTypes`, `kPersonalFileMaxBytes` |
| `lib/data/services/storage_service.dart` (modify) | `StoragePaths.personalFile`, `PersonalFileRemover` interface |
| `supabase/functions/document-url/authorize.ts` (modify) | `personalOwnerForPath`, `mayUsePersonalFile`, `routeRequest` (pure) |
| `supabase/functions/document-url/index.ts` (modify) | dispatch by route; personal sign/delete |
| `supabase/functions/document-url/authorize_test.ts` (modify) | Deno tests |
| `supabase/policies.sql`, `supabase/README.md` (modify) | widened upload policy; deploy notes |
| `lib/data/models/personal_folder.dart`, `personal_file.dart` (new) | models |
| `lib/data/repositories/my_files_repository.dart` (new) | folders, file records, folder deletion |
| `lib/data/repositories/form_copy_repository.dart` (modify) | `watchAllCopies`, `moveToFolder` |
| `lib/providers/my_files_providers.dart` (new) | repository + stream providers |
| `firestore.rules`, `rules-test/rules.test.js` (modify) | folders + files rules and tests |
| `lib/data/services/supabase_storage_service.dart`, `lib/providers/service_providers.dart` (modify) | `deletePersonal` via the function; remover provider |
| `lib/features/files/personal_file_actions.dart` (new) | upload and delete flows |
| `lib/features/forms/editable/name_dialog.dart` (modify) | `maxLength` parameter |
| `lib/features/files/my_files_screen.dart` (new) | the My files screen |
| `lib/core/routing/app_router.dart`, `lib/core/widgets/app_shell_host.dart`, `lib/core/navigation/shell_destination.dart` (modify) | route, title, sidebar entry |

---

### Task 0: Record the planning rulings in the spec

**Files:**
- Modify: `docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md`
- Create: `docs/superpowers/plans/2026-09-24-my-files-phase2.md` (this file, already written)

**Interfaces:** none.

- [ ] **Step 1:** In §6.1, in the `users/{uid}/files/{fileId}` table, replace the `storagePath` row's notes cell `` `personal/{uid}/{fileId}/{filename}` `` with:

```markdown
`personal/{uid}/{fileId}/{generated}.{ext}`: the last segment is generated; the person's own filename is kept in `name`
```

- [ ] **Step 2:** At the end of §7.3 (after the paragraph that ends `…one deploy.`), append:

```markdown
**Phase 2 note.** The app deletes personal files through a separate
`PersonalFileRemover` interface (implemented by the Supabase storage service),
so `StorageService` and its test fakes stay unchanged. If a record write fails
after an upload, the uploaded object is removed through this same delete
action on a best-effort basis.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-09-24-editable-forms-and-my-files-design.md docs/superpowers/plans/2026-09-24-my-files-phase2.md
git status --short   # only those two paths staged
git commit -m "docs(plan): My files phase 2, and the rulings it made

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 1: Upload checks for personal files

**Files:**
- Modify: `lib/features/titles/file_upload.dart`
- Modify: `lib/data/services/storage_service.dart` (`StoragePaths` only)
- Test: `test/features/files/personal_file_checks_test.dart` (new)

**Interfaces:**
- Produces:
  - `const Set<String> kPersonalFileTypes = {'pdf','doc','docx','ppt','pptx','png','jpg','jpeg'};`
  - `const int kPersonalFileMaxBytes = 25 * 1024 * 1024;`
  - `contentTypeFor('png') == 'image/png'`, `contentTypeFor('jpg'|'jpeg') == 'image/jpeg'` (case-insensitive, like the rest)
  - `contentMatchesExtension('png', …)` checks `89 50 4E 47`; `'jpg'`/`'jpeg'` check `FF D8 FF`
  - `static String StoragePaths.personalFile({required String uid, required String fileId, required String extension})` → `personal/$uid/$fileId/<uuid-v4>.$extension`

- [ ] **Step 1: Write the failing test** at `test/features/files/personal_file_checks_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const jpeg = [0xFF, 0xD8, 0xFF, 0xE0];
const pdf = [0x25, 0x50, 0x44, 0x46, 0x2D];

PickedDocument picked(String ext, Uint8List bytes) => PickedDocument(
      name: 'x.$ext',
      bytes: bytes,
      extension: ext,
      contentType: contentTypeFor(ext),
    );

String? check(PickedDocument file) => validateDocument(
      file,
      allowed: kPersonalFileTypes,
      maxBytes: kPersonalFileMaxBytes,
    );

void main() {
  test('My files accepts documents, slides and photos, up to 25 MB', () {
    expect(kPersonalFileTypes,
        {'pdf', 'doc', 'docx', 'ppt', 'pptx', 'png', 'jpg', 'jpeg'});
    expect(kPersonalFileMaxBytes, 25 * 1024 * 1024);
  });

  test('a real PNG or JPEG passes the content check', () {
    expect(contentMatchesExtension('png', png), isTrue);
    expect(contentMatchesExtension('jpg', jpeg), isTrue);
    expect(contentMatchesExtension('jpeg', jpeg), isTrue);
  });

  test('a renamed file fails the content check', () {
    expect(contentMatchesExtension('png', pdf), isFalse);
    expect(contentMatchesExtension('jpg', png), isFalse);
  });

  test('photos are stored with an image content type', () {
    expect(contentTypeFor('png'), 'image/png');
    expect(contentTypeFor('jpg'), 'image/jpeg');
    expect(contentTypeFor('JPEG'), 'image/jpeg');
  });

  test('validateDocument with the My files limits', () {
    expect(check(picked('png', Uint8List.fromList(png))), isNull);
    expect(check(picked('pdf', Uint8List.fromList(pdf))), isNull);
    expect(check(picked('exe', Uint8List.fromList([0x4D, 0x5A]))), isNotNull,
        reason: 'not an allowed type');
    expect(check(picked('png', Uint8List.fromList(pdf))),
        contains('does not look like a real PNG'));

    final big = Uint8List(kPersonalFileMaxBytes + 1)..setRange(0, 4, pdf);
    expect(check(picked('pdf', big)), 'That file is larger than 25 MB.');
  });

  test('a personal file path is personal/{uid}/{fileId}/{uuid}.{ext}', () {
    final path =
        StoragePaths.personalFile(uid: 'u1', fileId: 'f1', extension: 'png');
    expect(path, matches(RegExp(r'^personal/u1/f1/[0-9a-f-]{36}\.png$')));
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/files/personal_file_checks_test.dart`
Expected: FAIL: `Undefined name 'kPersonalFileTypes'` (compile error).

- [ ] **Step 3: Implement.** In `lib/features/titles/file_upload.dart`:

(a) After the `kChapterMaxBytes` line, add:

```dart

/// What My files accepts: documents, slides and photos (spec §6.3).
const kPersonalFileTypes = {
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'png', 'jpg', 'jpeg',
};

/// The same cap as a presentation, under the bucket's 50 MB ceiling.
const kPersonalFileMaxBytes = 25 * 1024 * 1024;
```

(b) In `contentTypeFor`, add two cases before the `_ =>` fallback:

```dart
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
```

(c) After the `_oleSig` constant, add:

```dart
const _pngSig = [0x89, 0x50, 0x4E, 0x47]; // "\x89PNG"
const _jpegSig = [0xFF, 0xD8, 0xFF]; // JPEG start-of-image marker
```

(d) In `contentMatchesExtension`, add two cases before the `_ => true` fallback:

```dart
    'png' => _startsWith(bytes, _pngSig),
    'jpg' || 'jpeg' => _startsWith(bytes, _jpegSig),
```

In `lib/data/services/storage_service.dart`, inside `class StoragePaths`, after `thesisDocument`, add:

```dart

  /// A file in someone's My files:
  /// `personal/{uid}/{fileId}/{uuid}.{extension}`.
  ///
  /// The person's own filename never goes in the path. It is kept in the
  /// Firestore record, and a generated name always passes the
  /// `document-url` function's strict filename check, which real filenames
  /// (spaces, accents, brackets) do not.
  static String personalFile({
    required String uid,
    required String fileId,
    required String extension,
  }) {
    return 'personal/$uid/$fileId/${_uuid.v4()}.$extension';
  }
```

- [ ] **Step 4: Run the new test and the existing upload tests**

Run: `flutter test test/features/files/personal_file_checks_test.dart test/features/titles/file_upload_test.dart`
Expected: all PASS. The existing PDF/Office checks are unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/features/titles/file_upload.dart lib/data/services/storage_service.dart test/features/files/personal_file_checks_test.dart
git status --short
git commit -m "feat(files): accept photos, and a path for personal uploads

PNG and JPEG are checked by signature like the documents already are;
My files takes documents, slides and photos up to 25 MB. A personal file
is stored at personal/{uid}/{fileId}/{uuid}.{ext}, its real name kept
in Firestore.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The server function: open and delete personal files, owner only

**Files:**
- Modify: `supabase/functions/document-url/authorize.ts` (append)
- Modify: `supabase/functions/document-url/index.ts`
- Modify: `supabase/functions/document-url/authorize_test.ts` (append)
- Modify: `supabase/policies.sql`
- Modify: `supabase/README.md` (append a section)

**Interfaces:**
- Consumes: in `authorize.ts`, the private `SEGMENT` and `FILENAME` regexes and `thesisIdForPath`, `CallerFacts`, `SIGNED_URL_TTL_SECONDS`; in `index.ts`, `getDoc`, `verifyFirebaseToken`, `env`, `json`, `createClient`, `DOCUMENTS_BUCKET`.
- Produces:
  - `export function personalOwnerForPath(path: string): string | null`
  - `export function mayUsePersonalFile(caller: CallerFacts, ownerUid: string): boolean`
  - `export type Action = "sign" | "delete";`
  - `export type Route = { kind: "thesis"; thesisId: string; documentId: string } | { kind: "personal"; action: Action; ownerUid: string } | { kind: "error"; status: 400 | 403; error: string };`
  - `export function routeRequest(path: unknown, action?: unknown): Route`
  - HTTP contract: body `{ "path": string, "action"?: "sign" | "delete" }`. Personal sign → `200 {url, expiresIn}`. Personal delete → `200 {deleted: true}`. Non-owner or inactive → `403 {error: "forbidden"}`. Thesis delete → `403 {error: "forbidden"}`. Bad action → `400 {error: "bad_action"}`. Bad path → `400 {error: "bad_path"}`. Non-string path or unparseable body → `400 {error: "bad_request"}`. Storage delete error → `502 {error: "delete_failed"}`.

- [ ] **Step 1: Write the failing Deno tests.** Append to `supabase/functions/document-url/authorize_test.ts`, and extend its import from `./authorize.ts` to also import `mayUsePersonalFile`, `personalOwnerForPath` and `routeRequest`:

```ts
// --- personal files (My files) ---------------------------------------------

Deno.test("a well-formed personal path yields its owner", () => {
  assertEquals(
    personalOwnerForPath("personal/u1/f1/3f9a-b2.png"),
    "u1",
  );
});

Deno.test("personal paths of any other shape are refused", () => {
  for (
    const bad of [
      "personal/u1/f1",                  // too short
      "personal/u1/f1/a/b.png",          // too deep
      "personal/../f1/a.png",            // traversal
      "/personal/u1/f1/a.png",           // absolute
      "personal/u1/f1/my photo.png",     // filename with a space
      "personal/u1/f1/a%2Fb.png",        // encoded separator
      "personal/u1\\f1/a.png",           // backslash
      "privat/u1/f1/a.png",              // wrong root
      "",
    ]
  ) {
    assertEquals(personalOwnerForPath(bad), null, bad);
  }
});

Deno.test("a thesis path is not a personal path", () => {
  assertEquals(personalOwnerForPath("theses/t1/chapterI/a.pdf"), null);
});

Deno.test("only the active owner may use a personal file", () => {
  assertEquals(mayUsePersonalFile(caller({ uid: "u1" }), "u1"), true);
  assertEquals(mayUsePersonalFile(caller({ uid: "u2" }), "u1"), false);
  assertEquals(
    mayUsePersonalFile(caller({ uid: "u1", active: false }), "u1"),
    false,
  );
});

Deno.test("no role reaches another person's personal files", () => {
  for (const role of ["coordinator", "dean", "faculty", "student"]) {
    assertEquals(
      mayUsePersonalFile(caller({ uid: "someone", role }), "u1"),
      false,
      role,
    );
  }
});

Deno.test("routeRequest: personal paths may be signed or deleted", () => {
  assertEquals(routeRequest("personal/u1/f1/a.png"), {
    kind: "personal",
    action: "sign",
    ownerUid: "u1",
  });
  assertEquals(routeRequest("personal/u1/f1/a.png", "delete"), {
    kind: "personal",
    action: "delete",
    ownerUid: "u1",
  });
});

Deno.test("routeRequest: a thesis path may be signed, never deleted", () => {
  assertEquals(routeRequest("theses/t1/chapterI/a.pdf", "sign"), {
    kind: "thesis",
    thesisId: "t1",
    documentId: "chapterI",
  });
  assertEquals(routeRequest("theses/t1/chapterI/a.pdf", "delete"), {
    kind: "error",
    status: 403,
    error: "forbidden",
  });
});

Deno.test("routeRequest: malformed requests are refused", () => {
  assertEquals(routeRequest(42), {
    kind: "error",
    status: 400,
    error: "bad_request",
  });
  assertEquals(routeRequest("theses/t1/chapterI/a.pdf", "rename"), {
    kind: "error",
    status: 400,
    error: "bad_action",
  });
  assertEquals(routeRequest("elsewhere/a.pdf"), {
    kind: "error",
    status: 400,
    error: "bad_path",
  });
});
```

- [ ] **Step 2: Run them and watch them fail**

Run: `deno test supabase/functions/document-url/`
Expected: FAIL: the new imports are not exported (`personalOwnerForPath` / `mayUsePersonalFile` / `routeRequest` not found). The existing tests still pass once it compiles.

- [ ] **Step 3: Implement the pure functions.** Append to `supabase/functions/document-url/authorize.ts`:

```ts

// ---------------------------------------------------------------------------
// Personal files (My files)
// ---------------------------------------------------------------------------

/// The owner of a path in someone's My files, or null for any other path.
///
/// Exactly one shape exists, written by `StoragePaths.personalFile`:
///   personal/{uid}/{fileId}/{generated}.{ext}
/// with the same traversal defence as [thesisIdForPath].
export function personalOwnerForPath(path: string): string | null {
  if (path.length === 0 || path.length > 512) return null;
  if (path.includes("..") || path.includes("\\") || path.includes("%")) {
    return null;
  }
  if (path.startsWith("/")) return null;

  const parts = path.split("/");
  if (parts.length !== 4) return null;

  const [root, uid, fileId, filename] = parts;
  if (root !== "personal") return null;
  if (!SEGMENT.test(uid)) return null;
  if (!SEGMENT.test(fileId)) return null;
  if (!FILENAME.test(filename)) return null;

  return uid;
}

/// Whether [caller] may open or delete a file in [ownerUid]'s My files.
///
/// The owner alone, while active. No role reaches another person's personal
/// files, the Dean and the Research Coordinator included: these are one
/// person's working files, not thesis records (spec E9).
export function mayUsePersonalFile(
  caller: CallerFacts,
  ownerUid: string,
): boolean {
  return caller.active && caller.uid === ownerUid;
}

export type Action = "sign" | "delete";

/// What a request is asking for, decided from its body alone.
export type Route =
  | { kind: "thesis"; thesisId: string; documentId: string }
  | { kind: "personal"; action: Action; ownerUid: string }
  | { kind: "error"; status: 400 | 403; error: string };

/// Routes a request body to the check it needs.
///
/// A thesis document can only be signed. Nothing in the app deletes one, so
/// a delete on a thesis path is refused outright rather than attempted.
export function routeRequest(path: unknown, action: unknown = "sign"): Route {
  if (typeof path !== "string") {
    return { kind: "error", status: 400, error: "bad_request" };
  }
  if (action !== "sign" && action !== "delete") {
    return { kind: "error", status: 400, error: "bad_action" };
  }

  const ownerUid = personalOwnerForPath(path);
  if (ownerUid !== null) return { kind: "personal", action, ownerUid };

  const thesisId = thesisIdForPath(path);
  if (thesisId === null) {
    return { kind: "error", status: 400, error: "bad_path" };
  }
  if (action === "delete") {
    return { kind: "error", status: 403, error: "forbidden" };
  }
  return { kind: "thesis", thesisId, documentId: path.split("/")[2] };
}
```

- [ ] **Step 4: Run the Deno tests and watch them pass**

Run: `deno test supabase/functions/document-url/`
Expected: all PASS (existing + 8 new).

- [ ] **Step 5: Wire the handler.** In `supabase/functions/document-url/index.ts`:

(a) Change the import from `./authorize.ts` so it reads:

```ts
import {
  Action,
  CallerFacts,
  mayReadDocument,
  mayUsePersonalFile,
  routeRequest,
  SIGNED_URL_TTL_SECONDS,
  ThesisFacts,
} from "./authorize.ts";
```

(`thesisIdForPath` is no longer used here; `routeRequest` calls it.)

(b) Immediately above the line `Deno.serve(async (req) => {`, add:

```ts
/// A request for a file in someone's My files: open (sign) or delete it.
///
/// Owner only, and only while their account is active. `active` is read the
/// same way the thesis branch reads it. A non-owner is refused before any
/// Firestore read.
async function handlePersonal(
  projectId: string,
  callerUid: string,
  ownerUid: string,
  action: Action,
  path: string,
): Promise<Response> {
  if (callerUid !== ownerUid) return json(403, { error: "forbidden" });

  const userDoc = await getDoc(projectId, `users/${callerUid}`);
  const caller: CallerFacts = {
    uid: callerUid,
    role: (userDoc?.role as string | null) ?? null,
    active: userDoc?.active === true,
    hasNomination: false,
  };
  if (!mayUsePersonalFile(caller, ownerUid)) {
    return json(403, { error: "forbidden" });
  }

  const bucket = createClient(
    env("SUPABASE_URL"),
    env("SUPABASE_SERVICE_ROLE_KEY"),
  ).storage.from(DOCUMENTS_BUCKET);

  if (action === "delete") {
    const { error } = await bucket.remove([path]);
    if (error) return json(502, { error: "delete_failed" });
    return json(200, { deleted: true });
  }

  const { data, error } = await bucket.createSignedUrl(
    path,
    SIGNED_URL_TTL_SECONDS,
  );
  if (error || !data) return json(502, { error: "sign_failed" });
  return json(200, { url: data.signedUrl, expiresIn: SIGNED_URL_TTL_SECONDS });
}

```

(c) Inside `Deno.serve`, replace everything from the line `  let path: string;` down to and including the line `  if (!claims.emailVerified) return json(403, { error: "unverified" });`, including the comments between them, with:

```ts
  let body: { path?: unknown; action?: unknown };
  try {
    body = await req.json() as { path?: unknown; action?: unknown };
  } catch {
    return json(400, { error: "bad_request" });
  }

  // Which check this request needs, from its body alone. A delete is only
  // ever allowed on a personal path; see `routeRequest`.
  const route = routeRequest(body.path, body.action ?? "sign");
  if (route.kind === "error") {
    return json(route.status, { error: route.error });
  }
  const path = body.path as string;

  const projectId = env("FIREBASE_PROJECT_ID");
  const claims = await verifyFirebaseToken(auth.slice(7), projectId);
  if (!claims) return json(401, { error: "unauthenticated" });
  if (!claims.emailVerified) return json(403, { error: "unverified" });

  if (route.kind === "personal") {
    return await handlePersonal(
      projectId,
      claims.uid,
      route.ownerUid,
      route.action,
      path,
    );
  }
  const { thesisId, documentId } = route;
```

Everything after that (the `wantsManuscript` line onwards) stays exactly as it is. It keeps using `thesisId`, `documentId`, `claims`, `projectId` and `path`.

- [ ] **Step 6: Type-check the handler**

Run: `deno check supabase/functions/document-url/index.ts`
Expected: no errors. It needs the `jsr:` imports cached or network access. If it cannot fetch them, record the exact message in your report and continue; do not change imports to work around it.

- [ ] **Step 7: Widen the upload policy.** In `supabase/policies.sql`:

(a) In the header comment, replace the `UPLOAD` bullet's first line `--   * UPLOAD — anon MAY insert, but only under the `theses/` prefix, so a` with `--   * UPLOAD — anon MAY insert, but only under the `theses/` or `personal/` prefix, so a`. Leave the rest of that bullet as it is.

(b) Append this sentence to the end of the `DELETE/UPDATE` bullet (after `…anyone's manuscript.`):

```sql
--             Personal files (My files) are deleted by the `document-url`
--             function with service_role, after it checks the caller owns
--             the path. Still no anonymous delete.
```

(c) Replace the policy block (from `-- Uploads, confined to the theses/ prefix.` through the closing `);` of that `create policy`) with:

```sql
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
```

- [ ] **Step 8: Document the deploy.** Append to `supabase/README.md`:

```markdown

## My files (personal uploads)

Each person's own files live under `personal/{uid}/{fileId}/…` in the same
private bucket. The Firestore record at `users/{uid}/files/{fileId}` is what
makes a file appear in their My files. `document-url` signs a personal path
only for its owner, and is the only thing that can delete one (the
`{"path": …, "action": "delete"}` request, owner only). A delete on a thesis
path is always refused.

To turn it on (once):

1. SQL Editor: run the updated `policies.sql`. It replaces the upload policy
   so uploads may go under `theses/` or `personal/`.
2. Storage → `thesis-documents` → settings: if an allowed-MIME list is set,
   add `image/png` and `image/jpeg`.
3. Redeploy the function: `supabase functions deploy document-url --no-verify-jwt`.
4. Deploy the Firestore rules: `firebase deploy --only firestore:rules`.
```

- [ ] **Step 9: Run the Deno tests once more and commit**

Run: `deno test supabase/functions/document-url/`
Expected: all PASS.

```bash
git add supabase/functions/document-url/authorize.ts supabase/functions/document-url/index.ts supabase/functions/document-url/authorize_test.ts supabase/policies.sql supabase/README.md
git status --short
git commit -m "feat(storage): open and delete My files uploads, owner only

document-url routes each request by path: a personal/{uid}/... path is
signed or deleted only for that uid while active; a thesis path can be
signed as before but never deleted. The upload policy widens to the
personal/ prefix; there is still no anonymous read, update or delete.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Folders and file records (data layer)

**Files:**
- Create: `lib/data/models/personal_folder.dart`
- Create: `lib/data/models/personal_file.dart`
- Create: `lib/data/repositories/my_files_repository.dart`
- Modify: `lib/data/repositories/form_copy_repository.dart`
- Create: `lib/providers/my_files_providers.dart`
- Test: `test/data/repositories/my_files_repository_test.dart` (new)
- Test: `test/data/repositories/form_copy_repository_test.dart` (add two tests)

**Interfaces:**
- Consumes: `FormCopy`, `FormCopyRepository` (Phase 1); `firestoreProvider`, `authStateProvider`.
- Produces:
  - `class PersonalFolder { final String id, name; final DateTime? createdAt; factory PersonalFolder.fromMap(String id, Map<String, dynamic> m); }`
  - `class PersonalFile { final String id, name, storagePath, contentType; final int sizeBytes; final String? folderId; final DateTime? createdAt; factory PersonalFile.fromMap(String id, Map<String, dynamic> m); }`
  - `const int kFolderNameMax = 60; const int kFileNameMax = 200;`
  - `class MyFilesRepository { MyFilesRepository(FirebaseFirestore db); Stream<List<PersonalFolder>> watchFolders(String uid); Future<String> createFolder({required String uid, required String name}); Future<void> renameFolder({required String uid, required String folderId, required String name}); Future<int> deleteFolder({required String uid, required String folderId}); Stream<List<PersonalFile>> watchFiles(String uid); String newFileId(String uid); Future<void> addFile({required String uid, required String fileId, required String name, required String storagePath, required String contentType, required int sizeBytes, String? folderId}); Future<void> renameFile({required String uid, required String fileId, required String name}); Future<void> moveFile({required String uid, required String fileId, String? folderId}); Future<void> deleteFileRecord({required String uid, required String fileId}); }`
  - `FormCopyRepository.watchAllCopies(String uid) -> Stream<List<FormCopy>>` (every form, newest first) and `FormCopyRepository.moveToFolder({required String uid, required String copyId, String? folderId}) -> Future<void>`
  - `final myFilesRepositoryProvider = Provider<MyFilesRepository>`; `final myFoldersProvider = StreamProvider<List<PersonalFolder>>`; `final myPersonalFilesProvider = StreamProvider<List<PersonalFile>>`; `final myAllFormCopiesProvider = StreamProvider<List<FormCopy>>`

- [ ] **Step 1: Write the failing repository test** at `test/data/repositories/my_files_repository_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MyFilesRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = MyFilesRepository(db);
  });

  Timestamp at(int day) => Timestamp.fromDate(DateTime(2026, 9, day));

  Future<void> seedCopy(String id, String? folderId) =>
      db.doc('users/u1/formCopies/$id').set({
        'formId': 'form1', 'name': id, 'overrides': <String, String>{},
        'folderId': folderId, 'createdAt': at(1), 'updatedAt': at(1),
      });

  Future<void> seedFile(String id, String? folderId, {int day = 1}) =>
      db.doc('users/u1/files/$id').set({
        'name': '$id.pdf', 'storagePath': 'personal/u1/$id/a.pdf',
        'contentType': 'application/pdf', 'sizeBytes': 10,
        'folderId': folderId, 'createdAt': at(day),
      });

  test('createFolder writes only a trimmed name and the time', () async {
    final id = await repo.createFolder(uid: 'u1', name: '  Group 3  ');
    final data = (await db.doc('users/u1/folders/$id').get()).data()!;
    expect(data.keys.toSet(), {'name', 'createdAt'});
    expect(data['name'], 'Group 3');
  });

  test('a folder name must be 1 to $kFolderNameMax characters', () {
    expect(() => repo.createFolder(uid: 'u1', name: ' '), throwsArgumentError);
    expect(() => repo.createFolder(uid: 'u1', name: 'x' * 61),
        throwsArgumentError);
  });

  test('watchFolders lists folders by name', () async {
    await repo.createFolder(uid: 'u1', name: 'b folder');
    await repo.createFolder(uid: 'u1', name: 'A folder');
    final folders = await repo.watchFolders('u1').first;
    expect(folders.map((f) => f.name), ['A folder', 'b folder']);
  });

  test('renameFolder changes only the name', () async {
    final id = await repo.createFolder(uid: 'u1', name: 'Old');
    await repo.renameFolder(uid: 'u1', folderId: id, name: 'New');
    expect((await db.doc('users/u1/folders/$id').get()).data()!['name'],
        'New');
  });

  test('deleting a folder moves its copies and files to the top level',
      () async {
    final keep = await repo.createFolder(uid: 'u1', name: 'Keep');
    final gone = await repo.createFolder(uid: 'u1', name: 'Gone');
    await seedCopy('c-in', gone);
    await seedCopy('c-other', keep);
    await seedFile('f-in', gone);
    await seedFile('f-other', keep);

    final moved = await repo.deleteFolder(uid: 'u1', folderId: gone);

    expect(moved, 2);
    expect((await db.doc('users/u1/folders/$gone').get()).exists, isFalse);
    expect((await db.doc('users/u1/formCopies/c-in').get())['folderId'],
        isNull);
    expect((await db.doc('users/u1/files/f-in').get())['folderId'], isNull);
    expect((await db.doc('users/u1/formCopies/c-other').get())['folderId'],
        keep, reason: 'another folder is left alone');
    expect((await db.doc('users/u1/files/f-other').get())['folderId'], keep);
  });

  test('addFile writes exactly the record the rules allow, under its id',
      () async {
    final id = repo.newFileId('u1');
    await repo.addFile(
      uid: 'u1', fileId: id, name: '  Photo.png ',
      storagePath: 'personal/u1/$id/x.png', contentType: 'image/png',
      sizeBytes: 1234, folderId: null,
    );
    final data = (await db.doc('users/u1/files/$id').get()).data()!;
    expect(data.keys.toSet(), {
      'name', 'storagePath', 'contentType', 'sizeBytes', 'folderId',
      'createdAt',
    });
    expect(data['name'], 'Photo.png');
    expect(data['sizeBytes'], 1234);
  });

  test('an uploaded file keeps a name the rules accept', () async {
    final long = repo.newFileId('u1');
    await repo.addFile(
      uid: 'u1', fileId: long, name: '${'x' * 250}.pdf',
      storagePath: 'personal/u1/$long/x.pdf', contentType: 'application/pdf',
      sizeBytes: 1,
    );
    expect(
        ((await db.doc('users/u1/files/$long').get())['name'] as String)
            .length,
        kFileNameMax);

    final blank = repo.newFileId('u1');
    await repo.addFile(
      uid: 'u1', fileId: blank, name: '   ',
      storagePath: 'personal/u1/$blank/x.pdf',
      contentType: 'application/pdf', sizeBytes: 1,
    );
    expect((await db.doc('users/u1/files/$blank').get())['name'], 'Untitled');
  });

  test('watchFiles lists newest first', () async {
    await seedFile('old', null, day: 1);
    await seedFile('new', null, day: 3);
    final files = await repo.watchFiles('u1').first;
    expect(files.map((f) => f.id), ['new', 'old']);
    expect(files.first, isA<PersonalFile>());
  });

  test('renameFile is strict; moveFile and deleteFileRecord work', () async {
    await seedFile('f1', null);
    await repo.renameFile(uid: 'u1', fileId: 'f1', name: ' Notes.pdf ');
    expect((await db.doc('users/u1/files/f1').get())['name'], 'Notes.pdf');
    expect(() => repo.renameFile(uid: 'u1', fileId: 'f1', name: ''),
        throwsArgumentError);

    await repo.moveFile(uid: 'u1', fileId: 'f1', folderId: 'fold');
    expect((await db.doc('users/u1/files/f1').get())['folderId'], 'fold');
    await repo.moveFile(uid: 'u1', fileId: 'f1', folderId: null);
    expect((await db.doc('users/u1/files/f1').get())['folderId'], isNull);

    await repo.deleteFileRecord(uid: 'u1', fileId: 'f1');
    expect((await db.doc('users/u1/files/f1').get()).exists, isFalse);
  });
}
```

- [ ] **Step 2: Add the two form-copy tests.** Append inside `main()` of `test/data/repositories/form_copy_repository_test.dart`, after the last test (it already defines `db`, `repo` and a `seed(uid, id, formId, updated)` helper):

```dart
  test('watchAllCopies lists every form\'s copies, newest first', () async {
    await seed('u1', 'a', 'form1', DateTime(2026, 9, 1));
    await seed('u1', 'b', 'form3', DateTime(2026, 9, 2));
    await seed('u2', 'c', 'form1', DateTime(2026, 9, 3));
    final copies = await repo.watchAllCopies('u1').first;
    expect(copies.map((c) => c.id), ['b', 'a']);
  });

  test('moveToFolder sets the folder and keeps the edits', () async {
    await seed('u1', 'a', 'form1', DateTime(2026, 9, 1));
    await repo.saveOverrides(
        uid: 'u1', copyId: 'a', overrides: {'salutation': 'Dear Dean:'});
    await repo.moveToFolder(uid: 'u1', copyId: 'a', folderId: 'fold');
    final data = (await db.doc('users/u1/formCopies/a').get()).data()!;
    expect(data['folderId'], 'fold');
    expect(data['overrides'], {'salutation': 'Dear Dean:'});
    await repo.moveToFolder(uid: 'u1', copyId: 'a', folderId: null);
    expect((await db.doc('users/u1/formCopies/a').get())['folderId'], isNull);
  });
```

- [ ] **Step 3: Run both and watch them fail**

Run: `flutter test test/data/repositories/my_files_repository_test.dart test/data/repositories/form_copy_repository_test.dart`
Expected: FAIL. The new files don't exist yet, and `watchAllCopies` / `moveToFolder` are undefined.

- [ ] **Step 4: Write the models.**

`lib/data/models/personal_folder.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// A folder in someone's My files, at `users/{uid}/folders/{id}`. One level
/// only: a folder holds form copies and files, never other folders.
class PersonalFolder {
  const PersonalFolder({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  factory PersonalFolder.fromMap(String id, Map<String, dynamic> m) =>
      PersonalFolder(
        id: id,
        name: m['name'] as String? ?? '',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}
```

`lib/data/models/personal_file.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// A file someone uploaded to their My files. The bytes live in the private
/// bucket at [storagePath]; this record (at `users/{uid}/files/{id}`) is what
/// makes the file appear, and it is readable only by its owner.
class PersonalFile {
  const PersonalFile({
    required this.id,
    required this.name,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    this.folderId,
    this.createdAt,
  });

  final String id;

  /// The person's own filename, shown in the list.
  final String name;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final String? folderId;
  final DateTime? createdAt;

  factory PersonalFile.fromMap(String id, Map<String, dynamic> m) =>
      PersonalFile(
        id: id,
        name: m['name'] as String? ?? '',
        storagePath: m['storagePath'] as String? ?? '',
        contentType: m['contentType'] as String? ?? '',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        folderId: m['folderId'] as String?,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}
```

- [ ] **Step 5: Write the repository** at `lib/data/repositories/my_files_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/models/personal_folder.dart';

/// The longest folder name `firestore.rules` accepts.
const int kFolderNameMax = 60;

/// The longest file name `firestore.rules` accepts.
const int kFileNameMax = 200;

/// One person's My files: folders and uploaded-file records under
/// `users/{uid}`. Form copies live beside them (`formCopies`) and are
/// handled by `FormCopyRepository`, except that deleting a folder moves them
/// too.
class MyFilesRepository {
  MyFilesRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _folders(String uid) =>
      _db.collection('users').doc(uid).collection('folders');

  CollectionReference<Map<String, dynamic>> _files(String uid) =>
      _db.collection('users').doc(uid).collection('files');

  CollectionReference<Map<String, dynamic>> _copies(String uid) =>
      _db.collection('users').doc(uid).collection('formCopies');

  /// Folders by name, ignoring case.
  Stream<List<PersonalFolder>> watchFolders(String uid) =>
      _folders(uid).snapshots().map((s) => [
            for (final d in s.docs) PersonalFolder.fromMap(d.id, d.data()),
          ]..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Future<String> createFolder({
    required String uid,
    required String name,
  }) async {
    final ref = _folders(uid).doc();
    await ref.set({
      'name': _checked(name, kFolderNameMax),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameFolder({
    required String uid,
    required String folderId,
    required String name,
  }) =>
      _folders(uid)
          .doc(folderId)
          .update({'name': _checked(name, kFolderNameMax)});

  /// Moves every copy and file in the folder to the top level, then deletes
  /// the folder, in one batch. Nothing inside is deleted. Returns how many
  /// items moved.
  ///
  /// A copy's move also stamps `updatedAt`: the form-copy rules require it
  /// on every update.
  Future<int> deleteFolder({
    required String uid,
    required String folderId,
  }) async {
    final copies =
        await _copies(uid).where('folderId', isEqualTo: folderId).get();
    final files =
        await _files(uid).where('folderId', isEqualTo: folderId).get();
    final batch = _db.batch();
    for (final d in copies.docs) {
      batch.update(d.reference, {
        'folderId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final d in files.docs) {
      batch.update(d.reference, {'folderId': null});
    }
    batch.delete(_folders(uid).doc(folderId));
    await batch.commit();
    return copies.size + files.size;
  }

  /// Uploaded files, newest first. A record not yet stamped by the server
  /// counts as newest.
  Stream<List<PersonalFile>> watchFiles(String uid) =>
      _files(uid).snapshots().map((s) {
        final files = [
          for (final d in s.docs) PersonalFile.fromMap(d.id, d.data()),
        ];
        files.sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return -1;
          if (bt == null) return 1;
          return bt.compareTo(at);
        });
        return files;
      });

  /// A fresh record id, reserved before the upload so the storage path and
  /// the record carry the same id (the rules require it).
  String newFileId(String uid) => _files(uid).doc().id;

  /// Records an uploaded file under [fileId]. The person's filename is kept
  /// as given but trimmed, cut to [kFileNameMax], and "Untitled" if blank, so
  /// an unusual filename never blocks an upload that already happened.
  Future<void> addFile({
    required String uid,
    required String fileId,
    required String name,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
    String? folderId,
  }) {
    var shown = name.trim();
    if (shown.isEmpty) shown = 'Untitled';
    if (shown.length > kFileNameMax) shown = shown.substring(0, kFileNameMax);
    return _files(uid).doc(fileId).set({
      'name': shown,
      'storagePath': storagePath,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'folderId': folderId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renameFile({
    required String uid,
    required String fileId,
    required String name,
  }) =>
      _files(uid).doc(fileId).update({'name': _checked(name, kFileNameMax)});

  Future<void> moveFile({
    required String uid,
    required String fileId,
    String? folderId,
  }) =>
      _files(uid).doc(fileId).update({'folderId': folderId});

  Future<void> deleteFileRecord({
    required String uid,
    required String fileId,
  }) =>
      _files(uid).doc(fileId).delete();

  static String _checked(String name, int max) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > max) {
      throw ArgumentError.value(name, 'name', 'must be 1 to $max characters');
    }
    return trimmed;
  }
}
```

- [ ] **Step 6: Extend `FormCopyRepository`.** In `lib/data/repositories/form_copy_repository.dart`:

(a) Replace the body of `watchCopies` so both it and the new method share one sort, and add `watchAllCopies` right after it:

```dart
  Stream<List<FormCopy>> watchCopies(String uid, {required String formId}) {
    return _copies(uid).snapshots().map((s) => _newestFirst([
          for (final d in s.docs) FormCopy.fromMap(d.id, d.data()),
        ].where((c) => c.formId == formId)));
  }

  /// Every copy this person holds, of every form, newest first (My files).
  Stream<List<FormCopy>> watchAllCopies(String uid) {
    return _copies(uid).snapshots().map((s) => _newestFirst([
          for (final d in s.docs) FormCopy.fromMap(d.id, d.data()),
        ]));
  }

  // Not yet stamped by the server means written a moment ago: newest.
  static List<FormCopy> _newestFirst(Iterable<FormCopy> copies) {
    final list = copies.toList();
    list.sort((a, b) {
      final at = a.updatedAt;
      final bt = b.updatedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return bt.compareTo(at);
    });
    return list;
  }
```

Keep `watchCopies`'s existing doc comment above it.

(b) After `rename`, add:

```dart
  /// Puts the copy in a My files folder, or at the top level for null.
  /// Stamps `updatedAt`, as the rules require on every update.
  Future<void> moveToFolder({
    required String uid,
    required String copyId,
    String? folderId,
  }) =>
      _copies(uid).doc(copyId).update({
        'folderId': folderId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
```

- [ ] **Step 7: Write the providers** at `lib/providers/my_files_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/models/personal_folder.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

final myFilesRepositoryProvider = Provider<MyFilesRepository>(
  (ref) => MyFilesRepository(ref.watch(firestoreProvider)),
);

// Each awaits the auth state rather than reading its current value: while
// auth is still settling that value is null, which would read as "nothing
// here" and flash an empty page (the race `currentUserProvider` avoids).

final myFoldersProvider =
    StreamProvider<List<PersonalFolder>>((ref) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(myFilesRepositoryProvider).watchFolders(user.uid);
});

final myPersonalFilesProvider =
    StreamProvider<List<PersonalFile>>((ref) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(myFilesRepositoryProvider).watchFiles(user.uid);
});

final myAllFormCopiesProvider = StreamProvider<List<FormCopy>>((ref) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(formCopyRepositoryProvider).watchAllCopies(user.uid);
});
```

- [ ] **Step 8: Run the tests and watch them pass**

Run: `flutter test test/data/repositories/my_files_repository_test.dart test/data/repositories/form_copy_repository_test.dart`
Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/data/models/personal_folder.dart lib/data/models/personal_file.dart lib/data/repositories/my_files_repository.dart lib/data/repositories/form_copy_repository.dart lib/providers/my_files_providers.dart test/data/repositories/my_files_repository_test.dart test/data/repositories/form_copy_repository_test.dart
git status --short
git commit -m "feat(files): folders and file records for My files

Folders and uploaded-file records under users/{uid}; deleting a folder
moves its copies and files to the top level in one batch. Form copies
gain a cross-form list and moving into a folder.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Firestore rules for folders and file records

**Files:**
- Modify: `firestore.rules` (inside `match /users/{uid}`, after the `formCopies` block)
- Test: `rules-test/rules.test.js` (new tests immediately before `test.after(`)

**Interfaces:**
- Consumes: `verified()`; the JS helpers `env`, `asDefenceUser(uid, email)`, `seedUser(uid, role, email)`, and the imported `doc, getDoc, getDocs, collection, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp`. Use `asDefenceUser` (memoised) for **every** authenticated context: a second non-memoised context in one test throws "Firestore has already been started".
- Produces: the boundary described in Global Constraints for `users/{uid}/folders/{folderId}` and `users/{uid}/files/{fileId}`.

- [ ] **Step 1: Write the failing rules tests.** In `rules-test/rules.test.js`, insert immediately before `test.after(async () => {`:

```js
// --- My files: folders and file records (Phase 2) ---------------------------
//
// users/{uid}/folders and users/{uid}/files: one person's own, readable and
// writable by them alone. asDefenceUser (memoised) for every context.

const MF_OWNER = ["mf-owner", "mfowner@isufst.edu.ph"];
const MF_OTHER = ["mf-other", "mfother@isufst.edu.ph"];
const MF_AT = Timestamp.fromDate(new Date("2026-09-01T00:00:00Z"));

function folder(overrides = {}) {
  return { name: "Group 3", createdAt: serverTimestamp(), ...overrides };
}

function fileRecord(fileId, overrides = {}) {
  return {
    name: "Photo.png",
    storagePath: `personal/mf-owner/${fileId}/3f9a-b2.png`,
    contentType: "image/png",
    sizeBytes: 1234,
    folderId: null,
    createdAt: serverTimestamp(),
    ...overrides,
  };
}

async function seedMf(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

test("the owner may create, rename and delete a folder", async () => {
  const owner = asDefenceUser(...MF_OWNER);
  const ref = doc(owner, "users/mf-owner/folders/fo1");
  await assertSucceeds(setDoc(ref, folder()));
  await assertSucceeds(updateDoc(ref, { name: "Group 5" }));
  await assertSucceeds(deleteDoc(ref));
});

test("nobody else may read, list or write a folder, not even a coordinator or dean",
    async () => {
  await seedMf("users/mf-owner/folders/fo-private",
    { name: "Private", createdAt: MF_AT });
  await seedUser("mf-coord", "coordinator", "mfcoord@isufst.edu.ph");
  await seedUser("mf-dean", "dean", "mfdean@isufst.edu.ph");
  for (const [uid, email] of [
    MF_OTHER,
    ["mf-coord", "mfcoord@isufst.edu.ph"],
    ["mf-dean", "mfdean@isufst.edu.ph"],
  ]) {
    const db = asDefenceUser(uid, email);
    await assertFails(getDoc(doc(db, "users/mf-owner/folders/fo-private")));
    await assertFails(getDocs(collection(db, "users/mf-owner/folders")));
    await assertFails(updateDoc(doc(db, "users/mf-owner/folders/fo-private"),
      { name: "Taken" }));
    await assertFails(deleteDoc(doc(db, "users/mf-owner/folders/fo-private")));
    await assertFails(setDoc(doc(db, "users/mf-owner/folders/fo-planted"),
      folder()));
  }
});

test("a folder is exactly a 1-60 character name and a server time", async () => {
  const owner = asDefenceUser(...MF_OWNER);
  await assertFails(setDoc(doc(owner, "users/mf-owner/folders/fo-n0"),
    folder({ name: "" })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/folders/fo-n61"),
    folder({ name: "x".repeat(61) })));
  await assertSucceeds(setDoc(doc(owner, "users/mf-owner/folders/fo-n60"),
    folder({ name: "x".repeat(60) })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/folders/fo-extra"),
    folder({ parentId: "fo-n60" })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/folders/fo-t"),
    folder({ createdAt: MF_AT })));
});

test("a folder's createdAt never changes", async () => {
  await seedMf("users/mf-owner/folders/fo-ts",
    { name: "Dated", createdAt: MF_AT });
  const owner = asDefenceUser(...MF_OWNER);
  await assertFails(updateDoc(doc(owner, "users/mf-owner/folders/fo-ts"),
    { createdAt: serverTimestamp() }));
});

test("the owner may record an upload in their own area", async () => {
  const owner = asDefenceUser(...MF_OWNER);
  await assertSucceeds(setDoc(doc(owner, "users/mf-owner/files/fi1"),
    fileRecord("fi1")));
});

test("a file record must point inside the owner's area, at its own id",
    async () => {
  const owner = asDefenceUser(...MF_OWNER);
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-a"),
    fileRecord("fi-a", {
      storagePath: "personal/mf-other/fi-a/3f9a-b2.png",
    })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-b"),
    fileRecord("fi-b", {
      storagePath: "personal/mf-owner/some-other-id/3f9a-b2.png",
    })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-c"),
    fileRecord("fi-c", {
      storagePath: "theses/t1/chapterI/3f9a-b2.png",
    })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-d"),
    fileRecord("fi-d", {
      storagePath: "personal/mf-owner/fi-d/../x.png",
    })));
});

test("a file record must be an allowed type within 25 MB", async () => {
  const owner = asDefenceUser(...MF_OWNER);
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-exe"),
    fileRecord("fi-exe", { contentType: "application/x-msdownload" })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-0"),
    fileRecord("fi-0", { sizeBytes: 0 })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-big"),
    fileRecord("fi-big", { sizeBytes: 26214401 })));
  await assertSucceeds(setDoc(doc(owner, "users/mf-owner/files/fi-max"),
    fileRecord("fi-max", { sizeBytes: 26214400 })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-x"),
    fileRecord("fi-x", { sharedWith: ["mf-other"] })));
  await assertFails(setDoc(doc(owner, "users/mf-owner/files/fi-n"),
    fileRecord("fi-n", { name: "x".repeat(201) })));
});

test("the owner may rename or move a file but not rewrite what it is",
    async () => {
  await seedMf("users/mf-owner/files/fi-upd", {
    ...fileRecord("fi-upd"), createdAt: MF_AT,
  });
  const owner = asDefenceUser(...MF_OWNER);
  const ref = doc(owner, "users/mf-owner/files/fi-upd");
  await assertSucceeds(updateDoc(ref, { name: "Renamed.png" }));
  await assertSucceeds(updateDoc(ref, { folderId: "fo1" }));
  await assertSucceeds(updateDoc(ref, { folderId: null }));
  await assertFails(updateDoc(ref, {
    storagePath: "personal/mf-owner/fi-upd/other.png",
  }));
  await assertFails(updateDoc(ref, { sizeBytes: 99 }));
  await assertFails(updateDoc(ref, { contentType: "application/pdf" }));
  await assertFails(updateDoc(ref, { createdAt: serverTimestamp() }));
});

test("nobody else may read or change a file record; the owner may delete it",
    async () => {
  await seedMf("users/mf-owner/files/fi-del", {
    ...fileRecord("fi-del"), createdAt: MF_AT,
  });
  await seedUser("mf-coord2", "coordinator", "mfcoord2@isufst.edu.ph");
  for (const [uid, email] of [
    MF_OTHER,
    ["mf-coord2", "mfcoord2@isufst.edu.ph"],
  ]) {
    const db = asDefenceUser(uid, email);
    await assertFails(getDoc(doc(db, "users/mf-owner/files/fi-del")));
    await assertFails(getDocs(collection(db, "users/mf-owner/files")));
    await assertFails(updateDoc(doc(db, "users/mf-owner/files/fi-del"),
      { name: "Taken.png" }));
    await assertFails(deleteDoc(doc(db, "users/mf-owner/files/fi-del")));
  }
  const owner = asDefenceUser(...MF_OWNER);
  await assertSucceeds(getDocs(collection(owner, "users/mf-owner/files")));
  await assertSucceeds(deleteDoc(doc(owner, "users/mf-owner/files/fi-del")));
});

test("the owner may move a form copy into a folder", async () => {
  await seedMf("users/mf-owner/formCopies/c-mv", {
    formId: "form1", name: "Copy", overrides: {}, folderId: null,
    createdAt: MF_AT, updatedAt: MF_AT,
  });
  const owner = asDefenceUser(...MF_OWNER);
  await assertSucceeds(updateDoc(doc(owner, "users/mf-owner/formCopies/c-mv"),
    { folderId: "fo1", updatedAt: serverTimestamp() }));
});
```

- [ ] **Step 2: Run them and watch the owner-allowed ones fail**

Run: `cd rules-test && npm test`
Expected: the tests where the owner creates or updates a folder or file FAIL, because no rule grants anything under `folders` or `files` yet. Deny-only tests pass. `the owner may move a form copy into a folder` already PASSES (the Phase 1 rule allows it). Existing tests all pass.

- [ ] **Step 3: Add the rules.** In `firestore.rules`, find the end of the `formCopies` block inside `match /users/{uid}`. The unique text is:

```
        allow delete: if mine();
      }
    }

    match /facultyInvites/{email} {
```

and replace it with:

```
        allow delete: if mine();
      }

      // My files: folders (spec 2026-09-24 §6). One level; the owner's alone,
      // like form copies.
      match /folders/{folderId} {
        function mine() {
          return verified() && request.auth.uid == uid;
        }

        function validFolder(d) {
          return d.keys().hasOnly(['name', 'createdAt'])
              && d.keys().hasAll(['name', 'createdAt'])
              && d.name is string && d.name.size() >= 1 && d.name.size() <= 60;
        }

        allow read: if mine();
        allow create: if mine()
                      && validFolder(request.resource.data)
                      && request.resource.data.createdAt == request.time;
        allow update: if mine()
                      && validFolder(request.resource.data)
                      && request.resource.data.createdAt == resource.data.createdAt;
        allow delete: if mine();
      }

      // My files: uploaded-file records. The bytes live in Supabase under
      // personal/{uid}/{fileId}/...; this record is what makes a file show in
      // My files, so only the owner may create one, and only for a path in
      // their own area carrying this record's own id. What the file is
      // (path, type, size, time) never changes; its name and folder may.
      match /files/{fileId} {
        function mine() {
          return verified() && request.auth.uid == uid;
        }

        function validFile(d) {
          return d.keys().hasOnly(['name', 'storagePath', 'contentType',
                                   'sizeBytes', 'folderId', 'createdAt'])
              && d.keys().hasAll(['name', 'storagePath', 'contentType',
                                  'sizeBytes', 'folderId', 'createdAt'])
              && d.name is string && d.name.size() >= 1 && d.name.size() <= 200
              && d.storagePath is string
              && d.storagePath.matches('personal/' + uid + '/' + fileId
                     + '/[A-Za-z0-9][A-Za-z0-9_-]*[.][A-Za-z0-9]{1,8}')
              && d.contentType in [
                   'application/pdf',
                   'application/msword',
                   'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                   'application/vnd.ms-powerpoint',
                   'application/vnd.openxmlformats-officedocument.presentationml.presentation',
                   'image/png',
                   'image/jpeg']
              && d.sizeBytes is int && d.sizeBytes >= 1
              && d.sizeBytes <= 26214400
              && (d.folderId == null
                  || (d.folderId is string && d.folderId.size() <= 128));
        }

        allow read: if mine();
        allow create: if mine()
                      && validFile(request.resource.data)
                      && request.resource.data.createdAt == request.time;
        allow update: if mine()
                      && validFile(request.resource.data)
                      && request.resource.data.createdAt == resource.data.createdAt
                      && request.resource.data.storagePath == resource.data.storagePath
                      && request.resource.data.contentType == resource.data.contentType
                      && request.resource.data.sizeBytes == resource.data.sizeBytes;
        allow delete: if mine();
      }
    }

    match /facultyInvites/{email} {
```

- [ ] **Step 4: Run the rules tests and watch them all pass**

Run: `cd rules-test && npm test`
Expected: every test passes (295 before this task, plus 10 new).

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git status --short
git commit -m "feat(rules): owner-only folders and file records for My files

users/{uid}/folders and users/{uid}/files: the owner alone reads and
writes. A file record must point inside the owner's personal/ area at
its own id, be an allowed type within 25 MB, and never change what it
is; only its name and folder may change.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

> Deploy note (Task 7 lists it): `firebase deploy --only firestore:rules`.

---

### Task 5: The upload and delete flows, and deleting through the server function

**Files:**
- Modify: `lib/data/services/storage_service.dart` (add `PersonalFileRemover`)
- Modify: `lib/data/services/supabase_storage_service.dart`
- Modify: `lib/providers/service_providers.dart`
- Create: `lib/features/files/personal_file_actions.dart`
- Test: `test/features/files/personal_file_actions_test.dart` (new)

**Interfaces:**
- Consumes: Task 1 (`kPersonalFileTypes`, `kPersonalFileMaxBytes`, `validateDocument`, `contentTypeFor`, `PickedDocument`, `StoragePaths.personalFile`); Task 3 (`MyFilesRepository`, `PersonalFile`); `StorageService`, `StorageFailure`, `classifyStorageError`, `supabaseClientProvider`, `firebaseAuthProvider`.
- Produces:
  - `abstract class PersonalFileRemover { Future<void> deletePersonal(String path); }` (in `storage_service.dart`)
  - `SupabaseStorageService implements StorageService, PersonalFileRemover`
  - `final personalFileRemoverProvider = Provider<PersonalFileRemover>` (in `service_providers.dart`)
  - `class PersonalFileRejected implements Exception { const PersonalFileRejected(String message); final String message; }`
  - `Future<String> uploadPersonalFile({required StorageService storage, required PersonalFileRemover remover, required MyFilesRepository repo, required String uid, required PickedDocument file, String? folderId})`, which returns the new record id
  - `Future<void> deletePersonalFile({required PersonalFileRemover remover, required MyFilesRepository repo, required String uid, required PersonalFile file})`

- [ ] **Step 1: Write the failing flow test** at `test/features/files/personal_file_actions_test.dart`:

```dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/files/personal_file_actions.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

class FakeStorage implements StorageService {
  final uploads = <String>[];
  final contentTypes = <String>[];
  bool fail = false;

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    if (fail) {
      throw const StorageFailure('Storage is down.', code: 'storage-failed');
    }
    uploads.add(path);
    contentTypes.add(contentType);
    return StoredFile(path: path, url: 'https://example.test/$path');
  }

  @override
  Future<void> delete(String path) async {}

  @override
  Future<String> signedUrl(String path) async => 'https://example.test/$path';
}

class FakeRemover implements PersonalFileRemover {
  final deleted = <String>[];
  bool fail = false;

  @override
  Future<void> deletePersonal(String path) async {
    if (fail) {
      throw const StorageFailure('Refused.', code: 'storage-forbidden');
    }
    deleted.add(path);
  }
}

class FailingRecordRepo extends MyFilesRepository {
  FailingRecordRepo(super.db);

  @override
  Future<void> addFile({
    required String uid,
    required String fileId,
    required String name,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
    String? folderId,
  }) =>
      Future.error(StateError('permission-denied'));
}

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

PickedDocument picked(String name, String ext, List<int> bytes) =>
    PickedDocument(
      name: name,
      bytes: Uint8List.fromList(bytes),
      extension: ext,
      // Deliberately wrong: the flow must derive the type from the extension.
      contentType: 'application/octet-stream',
    );

void main() {
  late FakeFirebaseFirestore db;
  late MyFilesRepository repo;
  late FakeStorage storage;
  late FakeRemover remover;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = MyFilesRepository(db);
    storage = FakeStorage();
    remover = FakeRemover();
  });

  test('uploads under the owner\'s area and records it under the same id',
      () async {
    final id = await uploadPersonalFile(
      storage: storage, remover: remover, repo: repo, uid: 'u1',
      file: picked('My Photo.png', 'png', png), folderId: 'fold',
    );

    expect(storage.uploads, hasLength(1));
    final path = storage.uploads.single;
    expect(path, startsWith('personal/u1/$id/'));
    expect(storage.contentTypes.single, 'image/png');

    final data = (await db.doc('users/u1/files/$id').get()).data()!;
    expect(data['name'], 'My Photo.png');
    expect(data['storagePath'], path);
    expect(data['contentType'], 'image/png');
    expect(data['sizeBytes'], png.length);
    expect(data['folderId'], 'fold');
  });

  test('a file that fails the checks is refused before anything is stored',
      () async {
    for (final file in [
      picked('run.exe', 'exe', [0x4D, 0x5A]),
      picked('fake.png', 'png', [0x25, 0x50, 0x44, 0x46]),
      picked('empty.png', 'png', const []),
    ]) {
      await expectLater(
        uploadPersonalFile(
            storage: storage, remover: remover, repo: repo, uid: 'u1',
            file: file),
        throwsA(isA<PersonalFileRejected>()),
        reason: file.name,
      );
    }
    expect(storage.uploads, isEmpty);
    expect((await db.collection('users/u1/files').get()).docs, isEmpty);
  });

  test('an empty file is refused with its own message', () async {
    await expectLater(
      uploadPersonalFile(
          storage: storage, remover: remover, repo: repo, uid: 'u1',
          file: picked('empty.png', 'png', const [])),
      throwsA(isA<PersonalFileRejected>()
          .having((e) => e.message, 'message', 'That file is empty.')),
    );
  });

  test('if storage fails, no record is written', () async {
    storage.fail = true;
    await expectLater(
      uploadPersonalFile(
          storage: storage, remover: remover, repo: repo, uid: 'u1',
          file: picked('a.png', 'png', png)),
      throwsA(isA<StorageFailure>()),
    );
    expect((await db.collection('users/u1/files').get()).docs, isEmpty);
    expect(remover.deleted, isEmpty);
  });

  test('if the record fails, the uploaded object is removed again', () async {
    await expectLater(
      uploadPersonalFile(
          storage: storage, remover: remover,
          repo: FailingRecordRepo(db), uid: 'u1',
          file: picked('a.png', 'png', png)),
      throwsA(isA<StateError>()),
    );
    expect(remover.deleted, storage.uploads,
        reason: 'the orphan is cleaned up');
  });

  test('deleting removes the stored object, then the record', () async {
    await db.doc('users/u1/files/f1').set({
      'name': 'a.png', 'storagePath': 'personal/u1/f1/x.png',
      'contentType': 'image/png', 'sizeBytes': 8, 'folderId': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });
    final file = PersonalFile.fromMap(
        'f1', (await db.doc('users/u1/files/f1').get()).data()!);

    await deletePersonalFile(
        remover: remover, repo: repo, uid: 'u1', file: file);

    expect(remover.deleted, ['personal/u1/f1/x.png']);
    expect((await db.doc('users/u1/files/f1').get()).exists, isFalse);
  });

  test('if the stored object cannot be deleted, the record is kept',
      () async {
    await db.doc('users/u1/files/f1').set({
      'name': 'a.png', 'storagePath': 'personal/u1/f1/x.png',
      'contentType': 'image/png', 'sizeBytes': 8, 'folderId': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });
    final file = PersonalFile.fromMap(
        'f1', (await db.doc('users/u1/files/f1').get()).data()!);
    remover.fail = true;

    await expectLater(
      deletePersonalFile(remover: remover, repo: repo, uid: 'u1', file: file),
      throwsA(isA<StorageFailure>()),
    );
    expect((await db.doc('users/u1/files/f1').get()).exists, isTrue,
        reason: 'the person can try again');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/features/files/personal_file_actions_test.dart`
Expected: FAIL: `PersonalFileRemover` / `personal_file_actions.dart` not found.

- [ ] **Step 3: Add the remover interface.** In `lib/data/services/storage_service.dart`, after the `abstract class StorageService { … }` block, add:

```dart

/// Deletes a file from the signed-in person's own My files.
///
/// Separate from [StorageService] on purpose. The bucket grants the
/// anonymous client no delete, so this goes through the `document-url`
/// function, which checks that the caller owns the path before it removes
/// anything. Keeping it out of [StorageService] also leaves that interface's
/// test fakes untouched.
abstract class PersonalFileRemover {
  /// Throws [StorageFailure] when the function refuses or fails.
  Future<void> deletePersonal(String path);
}
```

- [ ] **Step 4: Implement it in `SupabaseStorageService`.** In `lib/data/services/supabase_storage_service.dart`:

(a) Change the class line to `class SupabaseStorageService implements StorageService, PersonalFileRemover {`.

(b) Replace the whole `signedUrl` method with the three methods below. The body of `_callDocumentFunction` is the request code `signedUrl` already had, moved verbatim: the signed-out check, the ID-token fetch, the `functions.invoke` call and the response decoding. Only the request map is now a parameter.

```dart
  @override
  Future<String> signedUrl(String path) async {
    final (status, body) = await _callDocumentFunction({'path': path});
    if (status == 200) {
      final url = body['url'];
      if (url is String && url.isNotEmpty) return url;
      throw const StorageFailure(
        'File storage returned no link for this document.',
        code: 'storage-failed',
      );
    }
    throw _refusal(status, body['error'],
        personal: path.startsWith('personal/'));
  }

  @override
  Future<void> deletePersonal(String path) async {
    final (status, body) =
        await _callDocumentFunction({'path': path, 'action': 'delete'});
    if (status == 200) return;
    throw _refusal(status, body['error'], personal: true);
  }

  /// Calls the `document-url` function as the signed-in reader, whose
  /// Firebase ID token is the only thing that tells one reader from another.
  Future<(int, Map<String, dynamic>)> _callDocumentFunction(
    Map<String, Object> request,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const StorageFailure(
        'You are signed out, so this file cannot be opened. Sign in and try '
        'again.',
        code: 'storage-unauthenticated',
      );
    }

    final String token;
    try {
      final t = await user.getIdToken();
      if (t == null || t.isEmpty) throw StateError('no token');
      token = t;
    } catch (e) {
      throw classifyStorageError(e);
    }

    try {
      final res = await _client.functions.invoke(
        'document-url',
        body: request,
        headers: {'Authorization': 'Bearer $token'},
      );
      final Map<String, dynamic> body = switch (res.data) {
        final Map<String, dynamic> m => m,
        final String s when s.isNotEmpty =>
          jsonDecode(s) as Map<String, dynamic>,
        _ => const {},
      };
      return (res.status, body);
    } catch (e) {
      throw classifyStorageError(e);
    }
  }
```

(c) Give `_refusal` a `personal` flag and a personal 403 case. Change its signature to `StorageFailure _refusal(int status, Object? code, {bool personal = false}) =>`, and insert this case **before** the existing `(403, _) =>` case:

```dart
        (403, _) when personal => const StorageFailure(
            'Only the person who added this file can open or delete it.',
            code: 'storage-forbidden',
          ),
```

- [ ] **Step 5: Add the provider.** In `lib/providers/service_providers.dart`, after `storageServiceProvider`, add:

```dart

/// Deletes personal files through the `document-url` function. Its own
/// provider, not a cast of [storageServiceProvider], so a test can replace
/// one without the other.
final personalFileRemoverProvider = Provider<PersonalFileRemover>(
  (ref) => SupabaseStorageService(
    ref.watch(supabaseClientProvider),
    ref.watch(firebaseAuthProvider),
  ),
);
```

- [ ] **Step 6: Write the flows** at `lib/features/files/personal_file_actions.dart`:

```dart
import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

/// A picked file My files will not take, with the sentence to show.
class PersonalFileRejected implements Exception {
  const PersonalFileRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adds a picked file to [uid]'s My files, into [folderId] or the top
/// level. Returns the new record's id.
///
/// Checks first (type, size, real content, not empty), so a bad file never
/// reaches storage. Then the bytes go up, then the record. If the record
/// cannot be written, the uploaded object is removed again: without a record
/// it would sit invisible and still use storage.
Future<String> uploadPersonalFile({
  required StorageService storage,
  required PersonalFileRemover remover,
  required MyFilesRepository repo,
  required String uid,
  required PickedDocument file,
  String? folderId,
}) async {
  if (file.bytes.isEmpty) {
    throw const PersonalFileRejected('That file is empty.');
  }
  final problem = validateDocument(
    file,
    allowed: kPersonalFileTypes,
    maxBytes: kPersonalFileMaxBytes,
  );
  if (problem != null) throw PersonalFileRejected(problem);

  final extension = file.extension.toLowerCase();
  // From the extension, not the picker: the rules accept only the types
  // this app itself names.
  final contentType = contentTypeFor(extension);
  final fileId = repo.newFileId(uid);
  final path = StoragePaths.personalFile(
    uid: uid,
    fileId: fileId,
    extension: extension,
  );

  await storage.upload(bytes: file.bytes, path: path, contentType: contentType);
  try {
    await repo.addFile(
      uid: uid,
      fileId: fileId,
      name: file.name,
      storagePath: path,
      contentType: contentType,
      sizeBytes: file.bytes.length,
      folderId: folderId,
    );
  } catch (_) {
    try {
      await remover.deletePersonal(path);
    } catch (_) {
      // Best effort: the record failure below is what the person needs to
      // see, not a second failure about cleaning up after it.
    }
    rethrow;
  }
  return fileId;
}

/// Deletes one of [uid]'s files: the stored object first (through the
/// server function), then the record. If the object cannot be deleted the
/// record stays, so the file is still listed and the person can try again.
Future<void> deletePersonalFile({
  required PersonalFileRemover remover,
  required MyFilesRepository repo,
  required String uid,
  required PersonalFile file,
}) async {
  await remover.deletePersonal(file.storagePath);
  await repo.deleteFileRecord(uid: uid, fileId: file.id);
}
```

- [ ] **Step 7: Run the flow test, then the suites that use storage**

Run: `flutter test test/features/files/personal_file_actions_test.dart test/features/titles/ test/features/documents/`
Expected: all PASS. The existing `StorageService` fakes are untouched, so their suites still compile and pass.

- [ ] **Step 8: Commit**

```bash
git add lib/data/services/storage_service.dart lib/data/services/supabase_storage_service.dart lib/providers/service_providers.dart lib/features/files/personal_file_actions.dart test/features/files/personal_file_actions_test.dart
git status --short
git commit -m "feat(files): upload to and delete from My files

Upload checks the file, stores it under the owner's personal area, then
records it; a failed record removes the upload again. Delete removes the
stored object through the document-url function (owner only), then the
record, and keeps the record if the object cannot be removed.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The My files screen, its route and sidebar entry

**Files:**
- Modify: `lib/features/forms/editable/name_dialog.dart` (optional `maxLength`)
- Create: `lib/features/files/my_files_screen.dart`
- Modify: `lib/core/routing/app_router.dart`
- Modify: `lib/core/widgets/app_shell_host.dart` (`_staticTitles`)
- Modify: `lib/core/navigation/shell_destination.dart`
- Test: `test/features/files/my_files_screen_test.dart` (new)
- Test: `test/core/navigation/shell_destination_test.dart` (known routes + one test)
- Test: `test/core/routing/files_route_test.dart` (new)

**Interfaces:**
- Consumes: Task 1 (`kPersonalFileTypes`, `realPicker`, `DocumentPicker`); Task 3 (`PersonalFolder`, `PersonalFile`, `kFolderNameMax`, `kFileNameMax`, `myFilesRepositoryProvider`, `myFoldersProvider`, `myPersonalFilesProvider`, `myAllFormCopiesProvider`, `FormCopyRepository.moveToFolder/rename/delete`); Task 5 (`uploadPersonalFile`, `deletePersonalFile`, `PersonalFileRejected`, `personalFileRemoverProvider`); Phase 1 (`promptForName`, `kFormCopyNameMax`, `formCopyRepositoryProvider`, editor route `/forms/:formId/copies/:copyId`); `openStoredDocument`, `confirmAction`, `PageShell`, `Gap`, `Panel`, `RecordRow`, `EmptyState`, `ErrorState`, `LoadingState.page`, `Dates.relative`, `signedInUidProvider`, `storageServiceProvider`.
- Produces:
  - `Future<String?> promptForName(BuildContext context, {required String title, required String initial, required String confirmLabel, int maxLength = kFormCopyNameMax})`
  - `class MyFilesScreen extends ConsumerStatefulWidget { const MyFilesScreen({Key? key, String? folderId, DocumentPicker? pickDocument}); }`
  - Route `/files` (`?folder={id}` opens a folder). Title `My files`. A **My files** entry in the Resources section for every role, after Forms.
  - Keys: `myFiles`, `myFilesEmpty`, `folderMissing`, `newFolder`, `uploadFile`, `backToAllFiles`, `renameFolder`, `deleteFolder`, `confirmDeleteFolder`, `folder-<id>`, `item-<id>`, `itemMenu-<id>`, `moveTo-top`, `moveTo-<folderId>`, `confirmDeleteItem`.

- [ ] **Step 1: Give the name prompt a length.** In `lib/features/forms/editable/name_dialog.dart`:
  - add `int maxLength = kFormCopyNameMax` to `promptForName`'s named parameters and pass it through;
  - add a `final int maxLength;` field (required in its constructor) to `_NameDialog`;
  - in `_NameDialogState`, use `widget.maxLength` in place of `kFormCopyNameMax` in both `_valid` and the `TextField`'s `maxLength`.

Existing callers pass nothing, so they keep the limit of 100.

- [ ] **Step 2: Write the failing screen test** at `test/features/files/my_files_screen_test.dart`:

```dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/files/my_files_screen.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

class FakeStorage implements StorageService {
  final uploads = <String>[];
  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    uploads.add(path);
    return StoredFile(path: path, url: 'https://example.test/$path');
  }

  @override
  Future<void> delete(String path) async {}
  @override
  Future<String> signedUrl(String path) async => 'https://example.test/$path';
}

class FakeRemover implements PersonalFileRemover {
  final deleted = <String>[];
  @override
  Future<void> deletePersonal(String path) async => deleted.add(path);
}

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

class Harness {
  final db = FakeFirebaseFirestore();
  final storage = FakeStorage();
  final remover = FakeRemover();
  PickedDocument? nextPick;
  late GoRouter router;

  Timestamp at(int day) => Timestamp.fromDate(DateTime(2026, 9, day));

  Future<void> seedUser() => db.collection('users').doc('u1').set({
        'fullName': 'Test User', 'email': 't@isufst.edu.ph',
        'role': 'student', 'active': true,
      });

  Future<void> folder(String id, String name) =>
      db.doc('users/u1/folders/$id').set({'name': name, 'createdAt': at(1)});

  Future<void> copy(String id, String name, {String? folderId, int day = 1}) =>
      db.doc('users/u1/formCopies/$id').set({
        'formId': 'form1', 'name': name, 'overrides': <String, String>{},
        'folderId': folderId, 'createdAt': at(day), 'updatedAt': at(day),
      });

  Future<void> file(String id, String name, {String? folderId, int day = 1}) =>
      db.doc('users/u1/files/$id').set({
        'name': name, 'storagePath': 'personal/u1/$id/x.pdf',
        'contentType': 'application/pdf', 'sizeBytes': 2048,
        'folderId': folderId, 'createdAt': at(day),
      });

  Future<void> pump(WidgetTester tester, {String location = '/files'}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<PickedDocument?> picker({required Set<String> allowed}) async =>
        nextPick;

    router = GoRouter(initialLocation: location, routes: [
      GoRoute(
        path: '/files',
        builder: (_, s) => Scaffold(
          body: MyFilesScreen(
            folderId: s.uri.queryParameters['folder'],
            pickDocument: picker,
          ),
        ),
      ),
      GoRoute(
        path: '/forms/:formId/copies/:copyId',
        builder: (_, s) => Scaffold(
          body: Text('editor ${s.pathParameters['copyId']}',
              key: const Key('editorStub')),
        ),
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'u1', email: 't@isufst.edu.ph', isEmailVerified: true),
        )),
        storageServiceProvider.overrideWithValue(storage),
        personalFileRemoverProvider.overrideWithValue(remover),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }
}

/// Fake Firestore writes finish on the real event loop.
Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

Future<void> chooseFromMenu(WidgetTester tester, String id, String label) async {
  await tester.tap(find.byKey(Key('itemMenu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seedUser();
  });

  testWidgets('an empty My files says what to do', (tester) async {
    await h.pump(tester);
    expect(find.byKey(const Key('myFilesEmpty')), findsOneWidget);
  });

  testWidgets('the top level lists folders, then loose copies and files',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.copy('c-top', 'Loose copy');
    await h.file('f-top', 'Loose.pdf');
    await h.file('f-in', 'Inside.pdf', folderId: 'fo1');
    await h.copy('c-orphan', 'Orphan copy', folderId: 'gone');
    await h.pump(tester);

    expect(find.byKey(const Key('folder-fo1')), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-c-top')), findsOneWidget);
    expect(find.byKey(const Key('item-f-top')), findsOneWidget);
    expect(find.byKey(const Key('item-f-in')), findsNothing,
        reason: 'inside a folder, not at the top');
    expect(find.byKey(const Key('item-c-orphan')), findsOneWidget,
        reason: 'a missing folder never hides an item');
  });

  testWidgets('New folder makes a folder', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('newFolder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('copyNameField')), 'Group 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    final folders = await h.db.collection('users/u1/folders').get();
    expect(folders.docs.single.data()['name'], 'Group 5');
    expect(find.text('Group 5'), findsOneWidget);
  });

  testWidgets('opening a folder shows only its items, and All files returns',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.file('f-in', 'Inside.pdf', folderId: 'fo1');
    await h.file('f-top', 'Loose.pdf');
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('folder-fo1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-f-in')), findsOneWidget);
    expect(find.byKey(const Key('item-f-top')), findsNothing);
    expect(find.byKey(const Key('newFolder')), findsNothing,
        reason: 'folders are one level deep');

    await tester.tap(find.byKey(const Key('backToAllFiles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-f-top')), findsOneWidget);
  });

  testWidgets('uploading inside a folder stores the file in that folder',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.pump(tester, location: '/files?folder=fo1');
    h.nextPick = PickedDocument(
      name: 'Scan.png', bytes: Uint8List.fromList(png), extension: 'png',
      contentType: 'image/png',
    );

    await tester.tap(find.byKey(const Key('uploadFile')));
    await settleReal(tester);

    expect(h.storage.uploads.single, startsWith('personal/u1/'));
    final files = await h.db.collection('users/u1/files').get();
    expect(files.docs.single.data()['folderId'], 'fo1');
    expect(files.docs.single.data()['name'], 'Scan.png');
    expect(find.text('Added Scan.png.'), findsOneWidget);
  });

  testWidgets('a file My files will not take is refused with a reason',
      (tester) async {
    await h.pump(tester);
    h.nextPick = PickedDocument(
      name: 'run.exe', bytes: Uint8List.fromList([0x4D, 0x5A]),
      extension: 'exe', contentType: 'application/octet-stream',
    );

    await tester.tap(find.byKey(const Key('uploadFile')));
    await settleReal(tester);

    expect(h.storage.uploads, isEmpty);
    expect(find.textContaining('Choose a'), findsOneWidget);
  });

  testWidgets('Move to puts a file in a folder and a copy back at the top',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.file('f1', 'Notes.pdf');
    await h.copy('c1', 'A copy', folderId: 'fo1');
    await h.pump(tester);

    await chooseFromMenu(tester, 'f1', 'Move to…');
    await tester.tap(find.byKey(const Key('moveTo-fo1')));
    await settleReal(tester);
    expect((await h.db.doc('users/u1/files/f1').get())['folderId'], 'fo1');

    await tester.tap(find.byKey(const Key('folder-fo1')));
    await tester.pumpAndSettle();
    await chooseFromMenu(tester, 'c1', 'Move to…');
    await tester.tap(find.byKey(const Key('moveTo-top')));
    await settleReal(tester);
    expect((await h.db.doc('users/u1/formCopies/c1').get())['folderId'],
        isNull);
  });

  testWidgets('Rename changes a file\'s name', (tester) async {
    await h.file('f1', 'Notes.pdf');
    await h.pump(tester);

    await chooseFromMenu(tester, 'f1', 'Rename');
    await tester.enterText(
        find.byKey(const Key('copyNameField')), 'Chapter notes.pdf');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    expect((await h.db.doc('users/u1/files/f1').get())['name'],
        'Chapter notes.pdf');
  });

  testWidgets('deleting a file asks, then removes the object and the record',
      (tester) async {
    await h.file('f1', 'Notes.pdf');
    await h.pump(tester);

    await chooseFromMenu(tester, 'f1', 'Delete');
    expect(find.byKey(const Key('confirmDeleteItem')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteItem')));
    await settleReal(tester);

    expect(h.remover.deleted, ['personal/u1/f1/x.pdf']);
    expect((await h.db.doc('users/u1/files/f1').get()).exists, isFalse);
  });

  testWidgets('deleting a folder asks, then moves its items to the top',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.file('f-in', 'Inside.pdf', folderId: 'fo1');
    await h.copy('c-in', 'In copy', folderId: 'fo1');
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('folder-fo1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteFolder')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The 2 items in it move to the top level'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteFolder')));
    await settleReal(tester);

    expect((await h.db.doc('users/u1/folders/fo1').get()).exists, isFalse);
    expect((await h.db.doc('users/u1/files/f-in').get())['folderId'], isNull);
    expect(find.byKey(const Key('item-f-in')), findsOneWidget,
        reason: 'back at the top level, still there');
  });

  testWidgets('opening a form copy goes to its editor', (tester) async {
    await h.copy('c1', 'A copy');
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('item-c1')));
    await tester.pumpAndSettle();
    expect(find.text('editor c1'), findsOneWidget);
  });

  testWidgets('a folder that no longer exists says so', (tester) async {
    await h.pump(tester, location: '/files?folder=gone');
    expect(find.byKey(const Key('folderMissing')), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/features/files/my_files_screen_test.dart`
Expected: FAIL: `my_files_screen.dart` not found.

- [ ] **Step 4: Write the screen** at `lib/features/files/my_files_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/open_document.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/models/personal_folder.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/files/personal_file_actions.dart';
import 'package:ethesishub/features/forms/editable/name_dialog.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';
import 'package:ethesishub/providers/my_files_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// One thing in My files: a form copy or an uploaded file.
sealed class _Item {
  const _Item();
  String get id;
  String get name;
  String? get folderId;
  DateTime? get when;
}

class _CopyItem extends _Item {
  const _CopyItem(this.copy);
  final FormCopy copy;
  @override
  String get id => copy.id;
  @override
  String get name => copy.name;
  @override
  String? get folderId => copy.folderId;
  @override
  DateTime? get when => copy.updatedAt;
}

class _FileItem extends _Item {
  const _FileItem(this.file);
  final PersonalFile file;
  @override
  String get id => file.id;
  @override
  String get name => file.name;
  @override
  String? get folderId => file.folderId;
  @override
  DateTime? get when => file.createdAt;
}

enum _Act { open, rename, move, delete }

/// The "top level" choice in Move to. Folder ids are never empty.
const _topLevel = '';

/// A person's own form copies and uploaded files, in one-level folders.
/// Nobody else can see them (spec E9).
///
/// [folderId] null is the top level; otherwise the open folder, reached by
/// pushing `/files?folder={id}` so the system back closes it.
class MyFilesScreen extends ConsumerStatefulWidget {
  const MyFilesScreen({super.key, this.folderId, this.pickDocument});

  final String? folderId;

  /// Replaces the platform file dialog in tests.
  final DocumentPicker? pickDocument;

  @override
  ConsumerState<MyFilesScreen> createState() => _MyFilesScreenState();
}

class _MyFilesScreenState extends ConsumerState<MyFilesScreen> {
  bool _uploading = false;

  String? get _uid => ref.read(signedInUidProvider);

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _sayError(String what, Object e) => _say(e is StorageFailure
      ? '${e.message} [${e.code}]'
      : 'Could not $what: $e');

  void _leaveFolder() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/files');
    }
  }

  Future<void> _newFolder() async {
    final uid = _uid;
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'New folder',
      initial: 'New folder',
      confirmLabel: 'Create',
      maxLength: kFolderNameMax,
    );
    if (name == null) return;
    try {
      await ref.read(myFilesRepositoryProvider).createFolder(uid: uid, name: name);
    } catch (e) {
      _sayError('create the folder', e);
    }
  }

  Future<void> _upload() async {
    final uid = _uid;
    if (uid == null || _uploading) return;
    final picked = await (widget.pickDocument ?? realPicker)(
      allowed: kPersonalFileTypes,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await uploadPersonalFile(
        storage: ref.read(storageServiceProvider),
        remover: ref.read(personalFileRemoverProvider),
        repo: ref.read(myFilesRepositoryProvider),
        uid: uid,
        file: picked,
        folderId: widget.folderId,
      );
      _say('Added ${picked.name}.');
    } on PersonalFileRejected catch (e) {
      _say(e.message);
    } catch (e) {
      _sayError('add the file', e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(_Item item) async {
    switch (item) {
      case _CopyItem(:final copy):
        context.push('/forms/${copy.formId}/copies/${copy.id}');
      case _FileItem(:final file):
        await openStoredDocument(context, ref, file.storagePath,
            label: file.name);
    }
  }

  Future<void> _rename(_Item item) async {
    final uid = _uid;
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Rename',
      initial: item.name,
      confirmLabel: 'Rename',
      maxLength: item is _FileItem ? kFileNameMax : kFormCopyNameMax,
    );
    if (name == null || name == item.name) return;
    try {
      switch (item) {
        case _CopyItem(:final copy):
          await ref
              .read(formCopyRepositoryProvider)
              .rename(uid: uid, copyId: copy.id, name: name);
        case _FileItem(:final file):
          await ref
              .read(myFilesRepositoryProvider)
              .renameFile(uid: uid, fileId: file.id, name: name);
      }
    } catch (e) {
      _sayError('rename it', e);
    }
  }

  Future<void> _move(_Item item, List<PersonalFolder> folders) async {
    final uid = _uid;
    if (uid == null) return;
    final inAFolder = folders.any((f) => f.id == item.folderId);
    final targets = [for (final f in folders) if (f.id != item.folderId) f];
    if (!inAFolder && targets.isEmpty) {
      _say('Make a folder first with New folder.');
      return;
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Move to'),
        children: [
          if (inAFolder)
            SimpleDialogOption(
              key: const Key('moveTo-top'),
              onPressed: () => Navigator.of(dialogContext).pop(_topLevel),
              child: const Text('Top level'),
            ),
          for (final f in targets)
            SimpleDialogOption(
              key: Key('moveTo-${f.id}'),
              onPressed: () => Navigator.of(dialogContext).pop(f.id),
              child: Text(f.name),
            ),
        ],
      ),
    );
    if (choice == null) return;
    final folderId = choice == _topLevel ? null : choice;
    try {
      switch (item) {
        case _CopyItem(:final copy):
          await ref
              .read(formCopyRepositoryProvider)
              .moveToFolder(uid: uid, copyId: copy.id, folderId: folderId);
        case _FileItem(:final file):
          await ref
              .read(myFilesRepositoryProvider)
              .moveFile(uid: uid, fileId: file.id, folderId: folderId);
      }
    } catch (e) {
      _sayError('move it', e);
    }
  }

  Future<void> _delete(_Item item) async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await confirmAction(
      context,
      title: item is _FileItem ? 'Delete this file?' : 'Delete this copy?',
      message: '"${item.name}" will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmKey: const Key('confirmDeleteItem'),
    );
    if (!confirmed) return;
    try {
      switch (item) {
        case _CopyItem(:final copy):
          await ref
              .read(formCopyRepositoryProvider)
              .delete(uid: uid, copyId: copy.id);
        case _FileItem(:final file):
          await deletePersonalFile(
            remover: ref.read(personalFileRemoverProvider),
            repo: ref.read(myFilesRepositoryProvider),
            uid: uid,
            file: file,
          );
      }
    } catch (e) {
      _sayError('delete it', e);
    }
  }

  Future<void> _renameFolder(PersonalFolder folder) async {
    final uid = _uid;
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Rename folder',
      initial: folder.name,
      confirmLabel: 'Rename',
      maxLength: kFolderNameMax,
    );
    if (name == null || name == folder.name) return;
    try {
      await ref
          .read(myFilesRepositoryProvider)
          .renameFolder(uid: uid, folderId: folder.id, name: name);
    } catch (e) {
      _sayError('rename the folder', e);
    }
  }

  Future<void> _deleteFolder(PersonalFolder folder, int count) async {
    final uid = _uid;
    if (uid == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Delete this folder?',
      message: switch (count) {
        0 => 'The folder is empty.',
        1 => 'The 1 item in it moves to the top level. Nothing in it is '
            'deleted.',
        _ => 'The $count items in it move to the top level. Nothing in it '
            'is deleted.',
      },
      confirmLabel: 'Delete folder',
      confirmKey: const Key('confirmDeleteFolder'),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(myFilesRepositoryProvider)
          .deleteFolder(uid: uid, folderId: folder.id);
      if (mounted) _leaveFolder();
    } catch (e) {
      _sayError('delete the folder', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(myFoldersProvider);
    final filesAsync = ref.watch(myPersonalFilesProvider);
    final copiesAsync = ref.watch(myAllFormCopiesProvider);

    final error = foldersAsync.error ?? filesAsync.error ?? copiesAsync.error;
    if (error != null) {
      return _framed(PageShell(
        title: 'My files',
        children: [ErrorState(error: error, message: 'Could not load your files.')],
      ));
    }
    if (!foldersAsync.hasValue ||
        !filesAsync.hasValue ||
        !copiesAsync.hasValue) {
      return _framed(const PageShell(
        children: [LoadingState.page(label: 'Loading your files…')],
      ));
    }

    final folders = foldersAsync.value!;
    final files = filesAsync.value!;
    final copies = copiesAsync.value!;
    final folderIds = {for (final f in folders) f.id};

    PersonalFolder? open;
    for (final f in folders) {
      if (f.id == widget.folderId) open = f;
    }
    if (widget.folderId != null && open == null) {
      return _framed(PageShell(title: 'My files', children: [
        EmptyState(
          key: const Key('folderMissing'),
          icon: Icons.folder_off_outlined,
          title: 'This folder no longer exists',
          message: 'It may have been deleted. Its files are at the top level '
              'of My files.',
          action: TextButton(
            onPressed: _leaveFolder,
            child: const Text('All files'),
          ),
        ),
      ]));
    }

    // At the top level, anything whose folder is gone shows here too, so
    // nothing becomes unreachable.
    bool here(String? itemFolder) => widget.folderId == null
        ? (itemFolder == null || !folderIds.contains(itemFolder))
        : itemFolder == widget.folderId;
    final items = <_Item>[
      for (final c in copies)
        if (here(c.folderId)) _CopyItem(c),
      for (final f in files)
        if (here(f.folderId)) _FileItem(f),
    ]..sort(_newestFirst);

    int countIn(String folderId) =>
        copies.where((c) => c.folderId == folderId).length +
        files.where((f) => f.folderId == folderId).length;

    final atTop = open == null;
    final showFolders = atTop && folders.isNotEmpty;

    return _framed(PageShell(
      maxWidth: AppTokens.measureWide,
      kicker: atTop ? 'Resources' : 'My files',
      title: open?.name ?? 'My files',
      subtitle: atTop
          ? 'Your form copies and uploaded files. Only you can see them.'
          : null,
      actions: [
        if (atTop)
          OutlinedButton.icon(
            key: const Key('newFolder'),
            onPressed: _newFolder,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('New folder'),
          ),
        FilledButton.icon(
          key: const Key('uploadFile'),
          onPressed: _uploading ? null : _upload,
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: Text(_uploading ? 'Uploading…' : 'Upload file'),
        ),
      ],
      children: [
        if (!atTop) ...[
          Wrap(
            spacing: AppTokens.sm,
            runSpacing: AppTokens.sm,
            children: [
              TextButton.icon(
                key: const Key('backToAllFiles'),
                onPressed: _leaveFolder,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('All files'),
              ),
              TextButton.icon(
                key: const Key('renameFolder'),
                onPressed: () => _renameFolder(open!),
                icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                label: const Text('Rename folder'),
              ),
              TextButton.icon(
                key: const Key('deleteFolder'),
                onPressed: () => _deleteFolder(open!, items.length),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete folder'),
              ),
            ],
          ),
          const Gap.md(),
        ],
        if (!showFolders && items.isEmpty)
          EmptyState(
            key: const Key('myFilesEmpty'),
            icon: Icons.folder_open_outlined,
            title: 'Nothing here yet',
            message: atTop
                ? 'Upload a file, or start a form copy from the Forms screen.'
                : 'Move files here, or upload one while this folder is open.',
          ),
        if (showFolders) ...[
          Panel(
            title: 'Folders',
            flush: true,
            child: Column(children: [
              for (final f in folders)
                RecordRow(
                  key: Key('folder-${f.id}'),
                  leading: Icon(Icons.folder_outlined,
                      color: Tone.neutral.color(context)),
                  title: f.name,
                  subtitle: _itemCount(countIn(f.id)),
                  onTap: () => context.push('/files?folder=${f.id}'),
                ),
            ]),
          ),
          const Gap.lg(),
        ],
        if (items.isNotEmpty)
          Panel(
            title: 'Files and copies',
            flush: true,
            child: Column(children: [
              for (final item in items)
                RecordRow(
                  key: Key('item-${item.id}'),
                  leading: Icon(_iconFor(item),
                      color: Tone.neutral.color(context)),
                  title: item.name,
                  subtitle: _subtitleFor(item),
                  onTap: () => _open(item),
                  trailing: PopupMenuButton<_Act>(
                    key: Key('itemMenu-${item.id}'),
                    tooltip: 'More',
                    onSelected: (act) => switch (act) {
                      _Act.open => _open(item),
                      _Act.rename => _rename(item),
                      _Act.move => _move(item, folders),
                      _Act.delete => _delete(item),
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: _Act.open, child: Text('Open')),
                      PopupMenuItem(value: _Act.rename, child: Text('Rename')),
                      PopupMenuItem(value: _Act.move, child: Text('Move to…')),
                      PopupMenuItem(value: _Act.delete, child: Text('Delete')),
                    ],
                  ),
                ),
            ]),
          ),
      ],
    ));
  }

  Widget _framed(Widget child) =>
      KeyedSubtree(key: const Key('myFiles'), child: child);

  static int _newestFirst(_Item a, _Item b) {
    final at = a.when;
    final bt = b.when;
    if (at == null && bt == null) return 0;
    if (at == null) return -1;
    if (bt == null) return 1;
    return bt.compareTo(at);
  }

  static String _itemCount(int n) => n == 1 ? '1 item' : '$n items';

  static IconData _iconFor(_Item item) => switch (item) {
        _CopyItem() => Icons.edit_note_rounded,
        _FileItem(:final file) => switch (file.contentType) {
            'application/pdf' => Icons.picture_as_pdf_outlined,
            'image/png' || 'image/jpeg' => Icons.image_outlined,
            'application/vnd.ms-powerpoint' ||
            'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
              Icons.slideshow_outlined,
            _ => Icons.description_outlined,
          },
      };

  static String _subtitleFor(_Item item) {
    final when = item.when == null ? 'Just now' : Dates.relative(item.when!);
    return switch (item) {
      _CopyItem() => 'Form copy · Last edited: $when',
      _FileItem(:final file) => '${_size(file.sizeBytes)} · Added: $when',
    };
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
```

- [ ] **Step 5: Run the screen test and watch it pass**

Run: `flutter test test/features/files/my_files_screen_test.dart`
Expected: PASS (12 tests).
- If a `PageShell`, `Panel`, `RecordRow` or `EmptyState` parameter named here doesn't exist, read that widget's constructor (`lib/core/widgets/page_shell.dart`, `lib/core/design/panel.dart`, `lib/core/components/document.dart`, `lib/core/widgets/states.dart`) and use the actual parameter. Report the change.
- Do not drop an assertion to make a test pass.

- [ ] **Step 6: Register the route, the title and the sidebar entry.**

(a) `lib/core/routing/app_router.dart`: add the import `import 'package:ethesishub/features/files/my_files_screen.dart';` next to the other feature imports. Then, immediately after the `GoRoute(path: '/forms/:formId/copies/:copyId', …)` entry, add:

```dart
      // My files: a person's own form copies and uploads. Every role; the
      // rules keep each person's to themselves. `?folder=` opens a folder
      // (pushed, so the system back closes it).
      GoRoute(
        path: '/files',
        builder: (context, state) => MyFilesScreen(
          folderId: state.uri.queryParameters['folder'],
        ),
      ),
```

(b) `lib/core/widgets/app_shell_host.dart`: in `_staticTitles`, after `'/forms': 'Forms',` add `'/files': 'My files',`.

(c) `lib/core/navigation/shell_destination.dart`: in `destinationsFor`, after the `const forms = ShellDestination(…);` declaration, add:

```dart
  // A person's own form copies and uploads. Every role, unconditionally,
  // like Forms: an empty My files is still a useful page.
  const myFiles = ShellDestination(
    label: 'My files',
    icon: Icons.folder_outlined,
    route: '/files',
    section: ShellSection.resources,
  );
```

and in each of the four role lists (student, faculty, dean, coordinator), add `myFiles,` on the line right after `forms,`.

- [ ] **Step 7: Update the destination tests.** In `test/core/navigation/shell_destination_test.dart`:
  - add `'/files'` to the `known` set in `no role is given a route that does not exist in the app`;
  - add this test after `every role gets the Forms destination`:

```dart
    test('every role gets My files, in Resources', () {
      for (final role in UserRole.values) {
        final files = destinationsFor(role: role)
            .where((d) => d.route == '/files')
            .toList();
        expect(files, hasLength(1), reason: role.name);
        expect(files.single.section, ShellSection.resources,
            reason: role.name);
      }
    });
```

- [ ] **Step 8: Prove the route through the real router.** Create `test/core/routing/files_route_test.dart`. Copy the `containerFor` and `pumpApp` helpers and imports from `test/core/routing/forms_route_test.dart` exactly, then add:

```dart
void main() {
  testWidgets('/files resolves to My files', (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await pumpApp(tester, c);

    c.read(goRouterProvider).go('/files');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('myFiles')), findsOneWidget);
  });
}
```

(Keep only the imports this file actually uses.)

- [ ] **Step 9: Run the affected suites**

Run: `flutter test test/features/files/ test/features/forms/ test/core/`
Expected: all PASS.
- If a test elsewhere counts the sidebar destinations and now fails by exactly one, update its expected count and say so in your report. Stage that test too.
- If any other failure appears, report it; don't work around it.

- [ ] **Step 10: Commit**

```bash
git add lib/features/forms/editable/name_dialog.dart lib/features/files/my_files_screen.dart lib/core/routing/app_router.dart lib/core/widgets/app_shell_host.dart lib/core/navigation/shell_destination.dart test/features/files/my_files_screen_test.dart test/core/navigation/shell_destination_test.dart test/core/routing/files_route_test.dart
# plus any destination-count test Step 9 required, by explicit path
git status --short
git commit -m "feat(files): the My files page

Folders one level deep, with form copies and uploaded files together;
New folder, Upload file, and Open / Rename / Move to / Delete on every
item. Deleting a folder moves its items to the top level. In the
Resources section for every role.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Whole-app verification

**Files:** none changed unless a check fails.

- [ ] **Step 1:** `flutter analyze`: no new issues in any file this plan created or changed.
- [ ] **Step 2:** `flutter test`: `All tests passed!`. The count before this plan was 1,166.
- [ ] **Step 3:** `cd rules-test && npm test`: every test passes (305 expected).
- [ ] **Step 4:** `deno test supabase/functions/document-url/`: every test passes.
- [ ] **Step 5: Report the deploy steps, with no commit:**
  1. Supabase SQL Editor: run `supabase/policies.sql`.
  2. Supabase bucket settings: add `image/png` and `image/jpeg` if an allowed-MIME list is set.
  3. `supabase functions deploy document-url --no-verify-jwt`
  4. `firebase deploy --only firestore:rules`
  5. Rebuild the APK.
  6. On a device: My files → New folder → open it → Upload file (a photo) → open the photo → Move to… top level → Delete (asks first) → delete the folder (its items move up).
