# Editable forms and My files — design

**Date:** 2026-09-24
**Status:** Draft for review
**Origin:** Feedback from the adviser and faculty consultation. Forms should
open inside the app as documents whose text can be edited, not only downloaded
as PDFs. Each person should also have a place to keep those copies and their
own uploaded files, in folders.

## 1. Goal

1. Any signed-in user can open any research form on the Forms screen **inside
   the app**, edit **all of its text**, see the result in the form's official
   printed layout, save it as their own named copy, and download it as a PDF.
2. Each user gets a **My files** page where they organise their form copies
   and their **uploaded files** (PDF, Word, PowerPoint, images) into folders.
3. Separately and later, the faculty accept/decline screen and the Dean and
   Coordinator review screens show **Form 1 itself** (view only) instead of the
   nominee summary. This is piece A (§10), a separate small change.

## 2. Decisions made during design

| # | Decision | Why |
|---|----------|-----|
| E1 | Editing happens **in the app**, not by downloading a file to edit elsewhere. | The faculty asked for it explicitly. |
| E2 | **All text** on a form is editable, not only the blanks. | The faculty asked for it explicitly. Wording differs between offices and changes over time. |
| E3 | Each person edits **their own copy**. Copies are never shared. | No two people edit the same thing, so there are no edit conflicts and the security rules stay owner-only. |
| E4 | The editor keeps the form's **official layout** (header, bordered tables, signature lines). Text changes; structure doesn't. | The printed form must still look like the official ISUFST form. A Word-style editor would only approximate it. |
| E5 | A person may keep **several named copies** of the same form. | A panel member fills Form 5c for several groups. |
| E6 | **My files** holds form copies **and** uploaded files. | Asked for explicitly. |
| E7 | Folders are **one level deep**. | Moving and deleting stay simple. Nested folders can come later if asked for. |
| E8 | Deleting a folder **moves its contents to the top level**; it never deletes them. | Nothing is lost to one mis-tap. |
| E9 | A person's personal files are readable **only by that person**, including not by the Dean or Coordinator. | They are personal working files, not thesis records. |
| E10 | The letterhead lines (Republic of the Philippines, the university name, Research and Development, the address line) stay fixed; everything below them is editable, including the form code and title. | The letterhead is the institution's identity; an edited one would make an unofficial document. |

## 3. What exists today (what this builds on)

- **Forms screen** (`lib/features/forms/forms_screen.dart`, route `/forms`):
  nine form cards (1, 3, 4a, 4b, 5a, 5b, 5c, 7, 8). Each offers a blank PDF
  download; some also offer a filled one. Nothing is editable.
- **Form PDFs** (`lib/features/forms/formN_pdf.dart`, shared layout pieces in
  `form_chrome.dart`): built with the `pdf` package. Fixed wording is written
  directly into each `_page()` next to the variable parts. Blanks are
  `ruledLine()`s.
- **Storage**: one private Supabase bucket, `thesis-documents`. The app talks
  to Supabase anonymously (it authenticates with Firebase, not Supabase), so
  Supabase's own per-user access rules can't tell users apart.
  - **Upload:** `supabase/policies.sql` lets the anonymous client insert under
    `theses/` only. It cannot read, update or delete anything.
  - **Read:** the `document-url` server function checks the caller's Firebase
    ID token, checks access with the same rule `firestore.rules` uses
    (`authorize.ts`, `thesisIdForPath`, `mayReadDocument`), then returns a
    short-lived signed link.
- **File checks** (`lib/features/titles/file_upload.dart`): `validateDocument`
  checks the extension, size, and the file's leading bytes
  (`contentMatchesExtension`: PDF, ZIP-based Office files, older OLE2 Office
  files).
- **Opening a stored file:** `openStoredDocument` in
  `lib/core/widgets/open_document.dart`.

## 4. Editable text model

### 4.1 Templates

Each form gets a **template**: its id plus an ordered list of **blocks**.

```dart
enum BlockKind { text, blank }

class FormBlock {
  final String id;          // stable key, e.g. 'salutation', 'panel.1'
  final String label;       // what the editor shows, e.g. 'Salutation'
  final String defaultText; // today's printed wording; '' for a blank
  final BlockKind kind;
  final bool multiline;     // paragraph vs one line
}

class FormTemplate {
  final String formId;      // 'form1', 'form3', …; also the Firestore id
  final String title;
  final List<FormBlock> blocks; // in page order
}
```

- `text` blocks print their text. If someone empties one, it prints nothing.
- `blank` blocks print a ruled line while empty and the typed text once filled.
  This keeps today's blank-template look exactly.
- Block ids never change once shipped. Saved copies refer to them. Removing a
  block from a template makes any saved override for it ignored, not an error.

### 4.2 Resolving text

```dart
class FormText {
  FormText(this.template, [Map<String, String> overrides = const {}]);
  String of(String blockId);        // override if present, else default
  bool isBlank(String blockId);     // blank block with no text yet
}
```

A saved copy stores **only overrides**: blocks whose text differs from the
default. Untouched blocks always show the template's current wording, so a
fix to a template reaches existing copies.

### 4.3 PDF builders

Each `formN_pdf.dart` `_page()` is rewritten to take a `FormText` and get
every string through `text.of(...)`, drawing a ruled line where
`text.isBlank(...)` is true. The layout stays the same.

The existing entry points keep their signatures and output:

- `buildFormNBlank()` means `FormText(template)` with no overrides.
- `buildFormNPdf(data)` (where one exists) turns its `FormNData` into
  overrides and renders through the same `_page()`.

A new entry point renders an edited copy:
`buildFormPdf(FormTemplate, Map<String, String> overrides)`.

**Guarantee:** for every form, the blank and filled PDFs produced after the
rewrite contain the same text as before. The existing PDF tests, which read
the text of uncompressed PDFs, must pass unchanged. That is how this rewrite is
checked.

**Form 1 is the exception.** It has no blank template today, on purpose: its
filled PDF (`buildForm1Pdf`) is built from live nominations, with a variable
number of researchers and e-signature status lines. That builder is left
untouched. The editable copy gets its own blank Form 1 layout
(`form1_template.dart`) with fixed slots: 5 researchers, the adviser, 3 panel
members, the Coordinator and the Dean. Blanks inside sentences are underscores
in the editable text. The "Electronically completed in eThesisHub" notice is
left off, since it would be false on a hand-edited copy.

**Phase 3 note (forms 3, 4a, 4b, 5a, 5b, 5c, 7, 8).** A filled builder does not
turn its app data into overrides. `_page` keeps its data parameter and prints
the data where the official form does, falling back to the block (its typed
text, or a ruled line while blank) when there is no data. Variable-length parts
(a panel list, names joined into a sentence) therefore stay exactly as they are.
An editable copy is simply the page with no data. On Form 5c the criterion
weights stay fixed, because they define the scoring; the criterion names,
prompts, scores and comments are editable.

## 5. Form copies

### 5.1 Data

`users/{uid}/formCopies/{copyId}`:

| field | type | notes |
|---|---|---|
| `formId` | string | one of the nine known ids |
| `name` | string | 1–100 chars, e.g. "Group 3 – Santos" |
| `overrides` | map<string,string> | edited blocks only |
| `folderId` | string \| null | a folder in `users/{uid}/folders`, or top level |
| `createdAt` | timestamp | server time, set at create |
| `updatedAt` | timestamp | server time, set on every write |

### 5.2 Editor

Route `/forms/:formId/copies/:copyId`, inside the shell.

- The left pane lists the template's blocks in page order, each as a labelled
  field. Multi-line blocks get multi-line fields. A per-field "reset" puts back
  the default.
- The right pane is a **live preview** of the real form (`PdfPreview` from the
  `printing` package), rebuilt about 400 ms after typing stops.
- Wide screens (≥ 860 px, the same point where `SplitColumns` stops stacking)
  show both panes side by side. Phones get **Edit / Preview** tabs.
- Actions: **Save**, **Download PDF** (shares the edited copy), **Reset all**
  (asks first).
- Leaving with unsaved edits asks first, using the shared `confirmAction`.
- Download works on unsaved edits: it prints what's on screen.

### 5.3 Forms screen changes

Each form card keeps **Download blank** (and any filled download it has now)
and adds:

- **New copy**: asks for a name, creates the copy with no overrides, opens the
  editor.
- **My copies (n)**: lists this user's copies of that form (open, rename,
  delete). Only shown when n > 0.

## 6. My files

### 6.1 Data

`users/{uid}/folders/{folderId}`: `name` (1–60 chars), `createdAt`.

`users/{uid}/files/{fileId}`:

| field | type | notes |
|---|---|---|
| `name` | string | shown name, 1–200 chars; defaults to the original filename |
| `storagePath` | string | `personal/{uid}/{fileId}/{generated}.{ext}`: the last segment is generated; the person's own filename is kept in `name` |
| `contentType` | string | from the extension |
| `sizeBytes` | int | ≤ cap (§6.3) |
| `folderId` | string \| null | |
| `createdAt` | timestamp | |

Form copies (§5.1) share the same `folderId` field, so one folder holds both
kinds.

### 6.2 Screen

A **My files** entry in the sidebar's Resources section, route `/files`, for
every role.

- The top level shows the folders, then the items not in a folder.
- Opening a folder shows its items: form copies and uploaded files together,
  newest first, each with an icon for its kind.
- Actions: **New folder**, **Upload file** (into the open folder), and per item
  **Open**, **Rename**, **Move to…**, **Delete**.
- Opening a form copy opens the editor (§5.2). Opening an uploaded file uses
  `openStoredDocument` (signed link from `document-url`).
- Deleting a folder moves its items to the top level, then deletes the folder
  (it asks first and says how many items will move).
- Deleting a file asks first, removes the stored file through the server
  function (§7.3), then the record.

### 6.3 Upload checks

- Types: `pdf`, `doc`, `docx`, `ppt`, `pptx`, `png`, `jpg`, `jpeg`.
- Size cap: **25 MB** (`kPersonalFileMaxBytes`), matching presentations and
  under the bucket's 50 MB ceiling.
- `contentMatchesExtension` gains PNG (`89 50 4E 47`) and JPEG (`FF D8 FF`)
  signatures.
- The upload order is fixed: pick → `validateDocument` → store the file →
  create the Firestore record. A failed store creates no record. A failed
  record leaves an unlisted object, which is the same exposure uploads already
  have (§8).

## 7. Storage and server function changes

### 7.1 Upload policy (`supabase/policies.sql`)

Widen the anonymous INSERT policy from `theses/` to `theses/` **or**
`personal/`. There is still no anonymous read, update or delete.

The bucket's MIME allow-list, if one is set, must add `image/png` and
`image/jpeg`.

### 7.2 Read: `document-url`

`authorize.ts` gains `personalOwnerForPath(path)`. It accepts exactly
`personal/{uid}/{fileId}/{filename}`, applying the same segment, filename and
traversal checks as `thesisIdForPath`.

When a path matches, the function signs only if the verified token's `uid`
equals `{uid}`. No role gets past this check, the Dean and Coordinator
included. Thesis paths behave as before.

### 7.3 Delete: `document-url`

The same function gains a delete action, `{ action: "delete", path }`. It is
allowed **only** for `personal/{uid}/…` paths owned by the caller. It removes
the object with the service-role key the function already holds.

Thesis documents cannot be deleted this way. That's intentional: nothing in
the app deletes them today.

One function, not two, so there is only one set of secrets and one deploy.

**Phase 2 note.** The app deletes personal files through a separate
`PersonalFileRemover` interface (implemented by the Supabase storage service),
so `StorageService` and its test fakes stay unchanged. If a record write fails
after an upload, the uploaded object is removed through this same delete
action on a best-effort basis.

## 8. Security

- **Firestore rules**, under `match /users/{uid}`:
  - `formCopies`, `folders`, `files`: read and write only when
    `request.auth.uid == uid` and the account is verified and active.
  - On create and update, check: allowed keys only (`keys().hasOnly`); field
    types; `formId` in the known list; name length limits; `overrides` at most
    300 keys; `storagePath` starts with `personal/` + uid + `/`; `sizeBytes`
    no more than 25 MB; `createdAt` fixed after create; `updatedAt ==
    request.time`.
  - These rules sit outside the `theses` block, so they don't count against
    its 1000-expression limit.
- **Accepted, already present:** the anonymous client can insert objects under
  `personal/` for any uid. Those objects never appear in anyone's My files
  (listing comes only from owner-only Firestore records), can't be read (the
  function checks the owner), and can't overwrite (no update policy). The
  risk is storage abuse, which already exists under `theses/`.
- **No total quota** in this version. Only the per-file cap applies. The free
  Supabase plan has 1 GB total. If usage grows, add a per-user quota: a usage
  counter kept consistent by the rules on file create and delete.
- New audit entries: none. These are personal working files, not privileged
  actions.

## 9. Error handling

- Storage failures reuse `StorageFailure` and `classifyStorageError`: missing
  bucket, forbidden, wrong type, too large, and unreachable each get their
  plain-language message.
- A save that fails leaves the editor open with the edits intact and an
  `ErrorState` showing the Firestore code.
- A preview that fails to render shows an inline error in the preview pane;
  the fields stay editable.
- Opening a copy whose `formId` is unknown (for example after a rollback)
  shows "This form is no longer available" instead of crashing.

## 10. Piece A: Form 1 on the accept/decline and review screens

Separate from the above, and done after it.

- **Faculty accept/decline card** (`nomination_inbox_screen.dart`): a **View
  Form 1** control opens a view-only preview of Form 1 filled from the thesis
  and its nominations (`Form1Data.assemble` + `buildForm1Pdf`), with
  signatures blank.
- **Dean and Coordinator review card** (`review_queue_screen.dart`): the same
  view replaces the nominee summary.
- **Open question to confirm with the faculty before building:** the summary
  shows each nominee's live Accepted/Pending/Declined status, which the form
  doesn't show. Should the status stay somewhere (for example as a line of
  small badges above the form), or should it really go?

## 11. Order of work

1. **Phase 1: editable forms, Form 1.** Template model, `FormText`, the Form 1
   builder rewrite, form copies (data, rules, repository), the editor, and the
   Forms screen's New copy / My copies.
2. **Phase 2: My files.** Folders, file records, upload, signature checks, the
   `document-url` read and delete changes, the policy update, and the My files
   screen.
3. **Phase 3: the other eight forms.** One builder rewrite each, following the
   Form 1 pattern.
4. **Piece A** (§10), after its open question is answered.

## 12. Testing

- **Template model:** defaults, overrides, emptying a text block, blank vs
  filled blank, an unknown block id ignored.
- **PDF builders:** the existing blank and filled PDF tests pass unchanged. A
  new test per form confirms an edited block's text appears in the PDF and the
  replaced default doesn't.
- **Repository:** create, rename, delete copies, folders and files; moving an
  item; deleting a folder moves its items to the top level.
- **Firestore rules (emulator):** owner allowed. Another user denied for read
  and write, including Dean and Coordinator. Refused: unknown `formId`,
  oversize `overrides`, a `storagePath` outside the owner's prefix, extra keys,
  `sizeBytes` over the cap, changing `createdAt`.
- **Editor widget:** edit → preview updates → save → reopen shows the edit;
  leaving with unsaved edits asks; reset puts back the default.
- **My files widget:** folder create, rename and delete (items move up);
  upload refused on a bad type or a spoofed signature.
- **Server function (Deno tests):** `personalOwnerForPath` accepts the right
  shape and refuses traversal, wrong depth and a bad filename. Read is signed
  for the owner and refused for anyone else. Delete is allowed for the owner's
  personal path and refused for someone else's path and for any `theses/` path.

## 13. One-time setup (step-by-step guide at the time)

1. Supabase SQL editor: run the updated `supabase/policies.sql`.
2. Bucket settings: add `image/png` and `image/jpeg` if a MIME allow-list is
   set.
3. Redeploy the function: `supabase functions deploy document-url
   --no-verify-jwt`.
4. `firebase deploy --only firestore:rules`.
5. Rebuild the APK.

## 14. Out of scope

- Sharing a copy or file with another person.
- Prefilling a new copy from the user's own thesis data.
- Adding, removing or reordering sections or tables on a form.
- Nested folders.
- A total storage quota per person (§8).
- Editing uploaded files in the app (they open read-only in the device's
  viewer).
