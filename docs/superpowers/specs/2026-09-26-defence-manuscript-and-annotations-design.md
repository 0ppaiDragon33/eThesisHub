# Defence manuscript viewer, highlights and typing indicator — design

**Status:** approved in conversation 2026-09-26; awaiting written-spec review.
**Branch:** docs/ui-overhaul-spec.

## 1. What this is for

During a defence the group presents their slides while the panel reads the
manuscript. The panel wants that manuscript inside the app — for a pre-oral,
Chapters I–III as one document; for a final, Chapters I–V — and to mark it
up as they listen. The group reads those marks after the adviser releases
them, alongside the consolidated comments.

Also requested: the defence room shows when someone is typing a comment, as
the title defence already does.

Success:
- A panel member opens a defence's room and sees the approved chapters as
  one scrolling document beside the room comments.
- While the defence is in progress they drag a box over a passage, write a
  comment, and everyone on the panel sees it at once, in that person's own
  colour.
- The group sees every highlight, read-only, once the adviser releases.
- "Dr. Santos is typing…" shows in the room comments and while someone
  writes a highlight comment.

## 2. Decisions taken in conversation

| Question | Decision |
|---|---|
| What document? | The app merges each chapter's **latest approved** version: I–III for a pre-oral, I–V for a final (a re-defence uses its type). |
| Word chapters? | Chapter uploads become **PDF-only**. Showing Word in-app is not practical (no reliable renderer; conversion needs a paid service or a LibreOffice server). Existing Word chapters show a placeholder page with an **Open file** button. |
| Annotation kind | **Highlight + comment**: drag a box over a passage, attach a comment. |
| Who sees them | The adviser, panel, Coordinator and Dean, **live**; the group **after the adviser releases** (the room-comment rule). |
| When | Anyone who can read may open the manuscript once the defence is scheduled; **highlights can be added only while it is in progress**; each person may **delete their own** until it closes. |
| Room layout | **Option A**: manuscript on the left; on the right one panel switching between **Room comments** and **Highlights**. On a phone the pages fill the screen and the comments slide up from the bottom. |
| Colours | Each person's highlights have **their own colour**, with a name ↔ colour legend. |
| Typing indicator | Added to the defence room comments and the highlight composer. |
| The Dean and chapter files | The Dean may read chapter files **everywhere**, like the Coordinator (the old "Dean never sees chapter files" exclusion is removed). |

## 3. Findings that shaped the design

- **Chapters are per-chapter uploads** at
  `theses/{id}/documents/{chapterId}` with immutable versions in
  `…/versions/{n}` (`storagePath`, `mimeType`). Allowed types today:
  `kChapterTypes = {'pdf','doc','docx'}` (`file_upload.dart:65`).
- **An approved chapter cannot take a new upload** (`addVersion` throws on
  `approved`, `document_repository.dart:131`); the adviser must reopen it
  first. So while a chapter is `approved`, its `currentVersion` **is** its
  approved version — no new field is needed to find it.
- **Files are private** in the Supabase bucket; the app gets a 120-second
  signed URL through the `document-url` function
  (`StorageService.signedUrl`). Its `mayReadDocument` already admits the
  adviser, panel (incl. accepted nominees) and Coordinator, and excludes the
  Dean from chapter files — mirroring the Firestore `versions` read rule,
  which also has no Dean arm (`firestore.rules` ~1393).
- **The app can already draw PDF pages** (`Printing.raster`, used by the form
  editor's `ZoomablePages`), including one page at a time
  (`Printing.raster(bytes, pages: [i])`).
- **Room comments** (`defenses/{id}/comments`) are readable by the adviser,
  panel, Coordinator and Dean, and by the leader once `consolidatedAt` is
  set; writable by the same people only while `status == 'inProgress'`.
  Highlights mirror this exactly.
- **The title defence's typing indicator** is a per-user marker at
  `theses/{id}/titleComposing/{uid}` refreshed about every 5 s while typing,
  deleted on send/blur, and ignored by readers after 15 s
  (`ComposingIndicator.staleAfter`). The defence room reuses this mechanism.
- `lib/features/defence/consolidated_defence_screen.dart` carries the
  user's own uncommitted edits, so this work does not touch it; the group's
  read-only manuscript lives on its own route instead.

## 4. Data model

### 4.1 `DefenceAnnotation` (`defenses/{defenceId}/annotations/{annotationId}`)

- `authorUid`, `authorName`
- `authorPosition` — `Adviser`, `Panel Member`, `Research Coordinator` or
  `Dean`, resolved the way room comments resolve it, stored so the label
  does not change if a role changes later.
- `chapter` — a `ChapterId` value (`chapterI` …).
- `version` — the chapter version the box was drawn on.
- `page` — 0-based page index **within that chapter's file**.
- `rect` — `{x, y, w, h}`, each a fraction 0–1 of the page's width/height,
  so the box lands on the same passage at any zoom or screen size.
- `body` — the comment (1–2000 characters).
- `createdAt` — server time.

A highlight whose `version` no longer matches the chapter's approved
version (the chapter was reopened and re-approved) is not drawn on the page;
it stays in the list, marked "On an earlier version of Chapter II".

### 4.2 `DefenceComposing` (`defenses/{defenceId}/composing/{uid}`)

- `name`, `position`, `target` (`room` or `manuscript`), `updatedAt`
  (server time). Same lifecycle as `ComposingIndicator`: written on first
  keystroke, refreshed about every 5 s while the field has focus and text,
  deleted on send, blur or leaving; readers hide markers older than 15 s and
  never show their own.

## 5. The merged manuscript

- **Chapters shown:** pre-oral (and pre-oral re-defence) → Chapters I–III;
  final (and final re-defence) → I–V, in order, each introduced by a
  chapter divider ("Chapter II — Review of Related Literature").
- **For each chapter:**
  - `approved` and its current version is a PDF → its pages.
  - Not approved → one placeholder page: "Chapter II is not approved yet."
  - Approved but not a PDF (an older Word upload) → one placeholder page:
    "Chapter II was uploaded as a Word file and can't be shown here." with
    an **Open file** button (the existing signed-URL download).
  - Missing → "Chapter II has not been uploaded."
- **Loading:** each chapter's PDF is downloaded once (signed URL → bytes)
  and its pages are drawn **lazily**, a page at a time as it scrolls into
  view, and released when far off-screen, so a long manuscript does not hold
  every page image in a phone's memory.
- **Zoom:** buttons, 100 / 150 / 200 / 300 %, scrolling sideways when the
  pages are wider than the view. No pinch: the page list is built lazily for
  memory's sake, and pinch-zoom needs the whole document built at once.
- **Page labels:** "Ch. II · p. 3" (chapter-relative) on each page and in
  the highlight list.

## 6. Highlights

- **Adding** (only while the defence is in progress, for the adviser,
  panel, Coordinator and Dean): turn on the **Highlight** tool, drag a box
  over the page, then a small dialog asks for the comment. The tool turns
  itself off after each box, so a drag scrolls the pages again. Cancel
  discards the box.
- **Showing:** each box is drawn in its author's colour with a numbered tag;
  numbers follow the order highlights were made, so a number keeps meaning
  the same box; the **Highlights** tab lists them in page order (number,
  author, position, page, comment). Tapping one jumps the manuscript to its
  box and pulses it (a jump rather than an animated scroll: the page list is
  built lazily and cannot animate to a page it has not laid out yet).
- **Colours:** a fixed palette of 8 clearly distinct, colour-blind-safe
  colours, assigned per defence in roster order — the adviser, then
  `panelUids` in order, then anyone else who has highlighted (Coordinator,
  Dean) in order of their first highlight — and repeating after 8. Computed,
  not stored, so every viewer sees the same colours. A legend (name ↔ colour)
  sits at the top of the Highlights tab.
- **Deleting:** the author may delete their own highlight while the defence
  is in progress (a confirm dialog). No editing: delete and redraw.
- **Before the defence opens:** the manuscript is readable and the
  highlights (none yet) listed, but the Highlight tool shows "Highlighting
  opens when the defence starts." After it closes, the tool is gone and the
  set is the record.

## 7. Screens

### 7.1 Defence room — panel view (`defence_room_screen.dart`)

- **Wide screens (Option A):** the manuscript fills the left, larger area.
  The right column holds the existing session controls (open/close,
  evaluate, grades) compactly at the top, then a tabbed panel: **Room
  comments** (the existing log and composer, plus the typing line) |
  **Highlights (n)** (legend, list, and the typing line when someone is
  writing a highlight comment).
- **Phone:** the manuscript fills the screen; a sheet dragged up from the
  bottom holds the tabbed panel, then the session controls, then the
  records. Medium widths (tablets) keep the stacked room with the
  manuscript as a tall panel below it.
- The room's existing behaviour is otherwise unchanged.

### 7.2 Group view (read-only, after release)

- The leader's branch of the room screen gains **View manuscript** once the
  adviser has released (`consolidatedAt` set), opening
  `/defence/room/:defenceId/manuscript`: the same merged pages with every
  highlight and the Highlights list, no tools. Before release the route shows
  "Available once your adviser releases the comments."

### 7.3 Chapter upload

- `kChapterTypes` becomes `{'pdf'}`. The chapter screen's upload area adds:
  "Upload chapters as PDF. From Word: File → Save As → PDF."

### 7.4 Typing indicator in the room

- The Room comments composer writes a `room` marker; the highlight comment
  sheet writes a `manuscript` marker. Both tabs show "Dr. Santos is
  typing…" (or "Dr. Santos and Prof. Cruz are typing…") from fresh markers
  of others.

## 8. Security

### 8.1 Firestore rules

- `defenses/{id}/annotations/{aid}`
  - read: same as `comments` — the adviser, panel, Coordinator, Dean; the
    leader once `consolidatedAt` is set.
  - create: the same writers as comments, while the defence is
    `inProgress`, with `authorUid == request.auth.uid`, `createdAt ==
    request.time`, only the listed fields, `rect` values within 0–1, `page`
    a non-negative int, `body` 1–2000 chars.
  - delete: the author, while the defence is `inProgress`.
  - update: never.
- `defenses/{id}/composing/{uid}`
  - read: the adviser, panel, Coordinator, Dean (not the leader).
  - create/update: only your own (`uid == request.auth.uid`), only
    `name/position/target/updatedAt`, `updatedAt == request.time`, `target in
    ['room','manuscript']`.
  - delete: your own.
- **Dean and chapter files:** the `versions` read rule gains `isDean()`.

### 8.2 `document-url` function

- `mayReadDocument` drops the Dean exclusion for chapter files (the Dean
  reads them like the Coordinator). Its Deno tests change accordingly.

## 9. Testing

- **Rules (emulator):** annotations — each role's read before/after
  release, create only while in progress and only as oneself, field and
  `rect` validation, delete own only while in progress, no update, the
  leader never writes; composing — own only, readers, leader denied; the
  Dean reading chapter versions.
- **Deno:** `mayReadDocument` lets the Dean read chapter files.
- **Dart:**
  - the merge plan (which chapters for each defence type; approved /
    unapproved / non-PDF / missing placeholders);
  - colour assignment (roster order, others by first highlight, wrap);
  - rect normalisation round-trip;
  - the stale-version rule;
  - repository create/delete/watch for annotations and composing markers;
  - the room: highlight tool disabled before in progress, adding a
    highlight, deleting own, the typing line appearing and expiring;
  - the leader's read-only route before and after release;
  - PDF-only chapter upload.

## 10. Deploy

- `firestore.rules` (annotations, composing, the Dean on versions).
- The `document-url` Supabase function (the Dean on chapter files).
- Rebuild the APK. No data migration; no new Firestore index (all reads are
  per-defence subcollections).

## 11. Out of scope

- Freehand drawing, text-selection highlights, editing a highlight.
- Showing or converting Word files in the app.
- Highlights on the title defence.
- The student presenting their slides through the app.
- Changes to `consolidated_defence_screen.dart`.
