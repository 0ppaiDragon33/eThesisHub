# Defence Manuscript, Highlights and Typing Indicator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the defence room, show the approved chapters as one scrolling manuscript beside the room comments. The panel can draw highlight boxes with comments, each person in their own colour. Add a typing indicator. Make chapter uploads PDF-only and let the Dean read chapter files.

**Architecture:** A pure planner decides what each chapter contributes: pages, or a placeholder. A lazy `ListView` draws one page image at a time through a small rasterizer interface, so tests can replace `printing` with a fake. Highlights are append/delete-own documents in `defenses/{id}/annotations`; typing markers live in `defenses/{id}/composing/{uid}`. The rules for both mirror the room comments. The room screen gets three layouts: a wide row, the existing stacked page at medium width, and a bottom sheet on phones.

**Tech Stack:** Flutter 3.44, Riverpod 2.6.1, go_router 17.5, cloud_firestore with fake_cloud_firestore in tests, `printing` (`Printing.raster`), `http` (download bytes from a signed URL), Firestore rules tested on the emulator, Deno for the `document-url` edge function.

**Spec:** `docs/superpowers/specs/2026-09-26-defence-manuscript-and-annotations-design.md`

## Global Constraints

- Branch `docs/ui-overhaul-spec`. Never touch these uncommitted files: `android/app/src/main/kotlin/com/example/ethesishub/MainActivity.kt`, `lib/app.dart`, `lib/core/config/app_config.dart`, `lib/core/theme/app_theme.dart`, `lib/core/widgets/app_shell.dart`, `lib/features/dashboard/progress_rail.dart`, `lib/features/defence/consolidated_defence_screen.dart`, `lib/features/forms/form_chrome.dart`, `lib/core/platform/native_back.dart`, `test/core/platform/`, the deleted `double_back_to_exit` files, `macos/`, `android/build/`.
- Commit only named paths (`git add <path> …`); never `git add -A`, `.` or `-a`. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never deploy anything (rules, functions, indexes). The user deploys.
- Riverpod stays 2.6.1 and go_router stays 17.5: no Riverpod 3 APIs. The only new direct dependency is `http: 1.6.0`, which is already resolved transitively (pubspec.lock).
- Every Firestore write the rules pin to `request.time` uses `FieldValue.serverTimestamp()`.
- fake_cloud_firestore enforces no rules, so every repository write repeats its rule's checks in Dart.
- Chapter set: pre-oral (and pre-oral re-defence) → Chapters I–III (`ChapterId.proposalChapters`); final (and final re-defence) → I–V (`ChapterId.finalChapters`).
- A highlight comment is 1–2000 characters (`kAnnotationMaxLength = 2000`).
- Typing markers refresh every 5 s; readers ignore a marker older than 15 s (`ComposingIndicator.staleAfter`).
- Colours: 8-colour palette, assigned per defence: the adviser, then `panelUids` in order, then other authors in order of their first highlight, wrapping after 8.
- Copy, verbatim:
  - "Chapter II is not approved yet."
  - "Chapter II was uploaded as a Word file and can't be shown here."
  - "Chapter II has not been uploaded."
  - "Highlighting opens when the defence starts."
  - "On an earlier version of Chapter II"
  - "Available once your adviser releases the comments."
  - "Upload chapters as PDF. From Word: File → Save As → PDF."
  - "Dr. Santos is typing…" / "Dr. Santos and Prof. Cruz are typing…"
  - Each chapter's numeral is substituted in the chapter strings.
- Commands: `flutter test <path>`; rules: `cd rules-test && npm test`; edge function: `deno test supabase/functions/document-url/`.

## Review Focus

1. **A chapter PDF fails to download or cannot be read** (the signed URL expired, the network dropped, the PDF is corrupt). Expected: that chapter alone shows "Chapter N could not be loaded" and the other chapters still show. *Test: Task 7, "a chapter that fails to load says so and the rest still show".*
2. **A box dragged past the right or bottom edge of the page.** Rounding can make `x + w` slightly exceed 1. Expected: the box is clipped to the page and saves. *Tests: Task 2, "a box drawn to the page edge saves" (the rules control); Task 3, "a drag past the page edge is clipped to it".*
3. **A chapter is reopened and re-approved after highlights were made.** Expected: the old highlights are no longer drawn on the new pages and are listed as "On an earlier version of Chapter N". *Tests: Task 7, "draws a box only on its own page and version"; Task 8, "marks a highlight on an earlier version".*
4. **A panel member leaves the room mid-comment.** Expected: their "is typing…" marker is removed at once, not left to go stale. *Test: Task 6, "dispose clears the marker".*
5. **A leader opens `/defence/room/:id/manuscript` straight from a link before the adviser releases.** Expected: the leader sees only "Available once your adviser releases the comments." and nothing of the pages or highlights. *Test: Task 9, "the leader sees nothing before release".*

## File Structure

| Path | Responsibility |
|---|---|
| `firestore.rules` | the Dean may read chapter versions; `annotations` and `composing` under `defenses` |
| `rules-test/rules.test.js` | rules tests for the above |
| `supabase/functions/document-url/authorize.ts` (+ `_test.ts`) | the Dean may sign chapter-file URLs |
| `lib/data/models/defence_annotation.dart` | `NormRect`, `DefenceAnnotation`, `kAnnotationMaxLength` |
| `lib/data/models/defence_composing.dart` | `ComposingTarget`, `DefenceComposing` |
| `lib/data/repositories/defence_repository.dart` | watch/add/delete highlights; watch/mark/clear typing markers |
| `lib/providers/defence_providers.dart` | `defenceAnnotationsProvider`, `defenceComposingProvider` |
| `lib/features/defence/manuscript/manuscript_plan.dart` | pure: which chapters, and what each shows |
| `lib/features/defence/manuscript/manuscript_providers.dart` | parts provider, byte loader, rasterizer, per-chapter PDF |
| `lib/features/defence/manuscript/highlight_colours.dart` | palette, colour assignment, numbering, page order, legend, `HighlightTag` |
| `lib/features/defence/manuscript/defence_typing.dart` | `DefenceTyping` heartbeat, `typingText`, `TypingLine` |
| `lib/features/defence/manuscript/manuscript_view.dart` | the lazy page list, placeholders, zoom, drawing, reveal |
| `lib/features/defence/manuscript/highlights_panel.dart` | `HighlightsList`, `HighlightsTab`, `showHighlightComposer` |
| `lib/features/defence/manuscript/manuscript_pane.dart` | `DefenceManuscriptPane` (framed view bound to a defence), `openChapterFile` |
| `lib/features/defence/manuscript/defence_manuscript_screen.dart` | the read-only route |
| `lib/features/defence/defence_room_screen.dart` | layouts, tabs, highlight and typing wiring, the leader's button |
| `lib/core/routing/app_router.dart`, `lib/core/widgets/app_shell_host.dart` | route and bar title |
| `lib/features/titles/file_upload.dart`, `lib/features/documents/chapter_detail_screen.dart` | PDF-only chapters and the hint |

---

### Task 1: The Dean may read chapter files

**Files:**
- Modify: `firestore.rules:1344-1348` (comment) and `:1392-1395` (versions rule)
- Modify: `rules-test/rules.test.js:2857-2879` and `:3173-3185`
- Modify: `supabase/functions/document-url/authorize.ts:60-113`
- Modify: `supabase/functions/document-url/authorize_test.ts:108-117`

**Interfaces:**
- Consumes: none
- Produces: the Dean can `get`/`list` `theses/{id}/documents/{chapter}/versions/{n}`, and `mayReadDocument(dean, thesis, 'chapterI') == true`. The Dean still cannot read `feedback`.

- [ ] **Step 1: Flip the two rules tests to the new expectation**

In `rules-test/rules.test.js`, replace the test at line 2857 (`"M2: the dean reads chapter STATUS but NOT its versions or feedback"`) with:

```js
test("M2: the dean reads chapter status and versions but NOT its feedback",
  async () => {
    // Spec 2026-09-26: the Dean sits on defences and reads the manuscript,
    // so chapter files are open to them like the Coordinator. The adviser's
    // feedback stays between the adviser and the group.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedChapters(db);
      await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
      await setDoc(doc(db, "theses/m2/documents/chapterI/feedback/f1"), {
        version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "Tighten it.",
        createdAt: Timestamp.now(),
      });
    });
    const dean = asDocUser("dean-uid", "dean@isufst.edu.ph");
    await assertSucceeds(getDoc(doc(dean, "theses/m2/documents/chapterI")));
    await assertSucceeds(
      getDoc(doc(dean, "theses/m2/documents/chapterI/versions/1")));
    await assertSucceeds(
      getDocs(collection(dean, "theses/m2/documents/chapterI/versions")));
    await assertFails(
      getDoc(doc(dean, "theses/m2/documents/chapterI/feedback/f1")));
    // Control: the adviser reads the feedback the dean was denied.
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
    await assertSucceeds(
      getDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f1")));
  });
```

Replace the test at line 3173 (`"M3: the dean still reads chapter STATUS but not its versions"`) with:

```js
test("M3: the dean reads a chapter's versions, as the panel does",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedChapters(db);
      await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
    });
    const dean = asDocUser("dean-uid", "dean@isufst.edu.ph");
    await assertSucceeds(getDoc(doc(dean, "theses/m2/documents/chapterI")));
    await assertSucceeds(
      getDoc(doc(dean, "theses/m2/documents/chapterI/versions/1")));
    // Reading is not writing.
    await assertFails(updateDoc(
      doc(dean, "theses/m2/documents/chapterI/versions/1"), { sizeBytes: 1 }));
  });
```

- [ ] **Step 2: Run the rules tests to verify the two fail**

Run: `cd rules-test && npm test`
Expected: FAIL. Both tests fail at the Dean's `versions/1` read (`assertSucceeds` rejected with PERMISSION_DENIED); every other test passes.

- [ ] **Step 3: Widen the rule**

In `firestore.rules`, replace lines 1344–1346, the comment above `match /documents/{chapterId}`'s read rule:

```
        // The dean reads status here and the files below it (spec
        // 2026-09-26), but not the adviser's feedback: that is between the
        // adviser and the group.
```

Replace lines 1393–1395:

```
          // The dean reads chapter files like the coordinator: they sit on
          // defences and read the manuscript there (spec 2026-09-26 §8.1).
          allow get, list: if isThesisLeader(thesisId) || isAdviser(thesisId)
                           || isOnPanel() || isCoordinator() || isDean();
```

- [ ] **Step 4: Run the rules tests**

Run: `cd rules-test && npm test`
Expected: PASS, every test.

- [ ] **Step 5: Flip the Deno test**

In `supabase/functions/document-url/authorize_test.ts`, replace lines 108–117 (the section header and the test `"the dean may read the manuscript but NOT a chapter version"`) with:

```ts
// --- the dean and chapter files --------------------------------------------

Deno.test("the dean may read the manuscript and a chapter version", () => {
  // Spec 2026-09-26: the dean reads the defence manuscript, which is made of
  // chapter files. firestore.rules lets them read the version records too,
  // so this must agree or the room shows a chapter it cannot open.
  const dean = caller({ role: "dean" });
  assertEquals(mayReadDocument(dean, thesis, "manuscript"), true);
  assertEquals(mayReadDocument(dean, thesis, "chapterI"), true);
});
```

- [ ] **Step 6: Run the Deno tests to verify it fails**

Run: `deno test supabase/functions/document-url/`
Expected: FAIL in "the dean may read the manuscript and a chapter version" (`false` != `true`).

- [ ] **Step 7: Drop the exclusion**

In `supabase/functions/document-url/authorize.ts`:
- Delete the two lines in `mayReadThesis`'s doc comment that begin `/// The dean is included here where the chapter-version rule excludes them.` and `/// That is not an oversight — see`, together with the line `/// narrower rule for chapter files.`.
- Replace `mayReadDocument`'s doc comment paragraph that begins `/// \`firestore.rules\` draws one distinction` and ends `/// could still fetch the file it points at, and the rule would be decorative.` with:

```ts
/// A document's audience is the thesis's audience. The dean used to be
/// excluded from chapter files; since spec 2026-09-26 they read them like the
/// coordinator, matching the `versions` rule in firestore.rules.
```

- Delete the line `if (documentId !== "manuscript" && caller.role === "dean") return false;`.

- [ ] **Step 8: Run the Deno tests**

Run: `deno test supabase/functions/document-url/`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add firestore.rules rules-test/rules.test.js supabase/functions/document-url/authorize.ts supabase/functions/document-url/authorize_test.ts
git commit -m "feat(rules): the Dean reads chapter files, as the defence manuscript needs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Rules for highlights and typing markers

**Files:**
- Modify: `firestore.rules`: insert after the closing `}` of `match /comments/{commentId}` (currently line 1766)
- Test: `rules-test/rules.test.js`: append at the end of the file

**Interfaces:**
- Consumes: `seedM3Defence(db, extra)`, `asDefUser(uid, email)`, `defDoc`, `defThesis` (already in rules.test.js)
- Produces:
  - `defenses/{id}/annotations/{aid}` with fields `authorUid, authorName, authorPosition, chapter, version, page, rect{x,y,w,h}, body, createdAt`.
  - `defenses/{id}/composing/{uid}` with fields `name, position, target, updatedAt`.

- [ ] **Step 1: Write the failing rules tests**

Append to `rules-test/rules.test.js`:

```js
// ---------- Manuscript highlights and typing (spec 2026-09-26) ----------

function highlight(uid, extra = {}) {
  return {
    authorUid: uid, authorName: "Dr. Panel", authorPosition: "Panel Member",
    chapter: "chapterII", version: 2, page: 3,
    rect: { x: 0.1, y: 0.2, w: 0.5, h: 0.05 },
    body: "Cite the 2024 data here.", createdAt: serverTimestamp(), ...extra,
  };
}

function marker(extra = {}) {
  return {
    name: "Dr. Panel", position: "Panel Member", target: "room",
    updatedAt: serverTimestamp(), ...extra,
  };
}

test("highlights: added only while the defence is in progress", async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) => seedM3Defence(ctx.firestore()));
  const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
  const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");

  await assertFails(setDoc(doc(pan, "defenses/df1/annotations/h1"),
    highlight("pan-uid")));
  await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
    { status: "inProgress" }));
  await assertSucceeds(setDoc(doc(pan, "defenses/df1/annotations/h1"),
    highlight("pan-uid")));
  await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
    { status: "completed" }));
  await assertFails(setDoc(doc(pan, "defenses/df1/annotations/h2"),
    highlight("pan-uid")));
});

test("highlights: the adviser, panel, coordinator and dean may add; the group and outsiders may not",
  async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled((ctx) =>
      seedM3Defence(ctx.firestore(), { status: "inProgress" }));
    for (const uid of ["pan-uid", "adviser-uid", "coord-uid", "dean-uid"]) {
      await assertSucceeds(setDoc(
        doc(asDefUser(uid, `${uid}@isufst.edu.ph`),
          `defenses/df1/annotations/by-${uid}`),
        highlight(uid)));
    }
    await assertFails(setDoc(
      doc(asDefUser("leader-uid", "leader@isufst.edu.ph"),
        "defenses/df1/annotations/by-leader"),
      highlight("leader-uid")));
    await assertFails(setDoc(
      doc(asDefUser("outsider-uid", "out@isufst.edu.ph"),
        "defenses/df1/annotations/by-outsider"),
      highlight("outsider-uid")));
  });

test("highlights: filed in your own name, with a valid box and comment",
  async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled((ctx) =>
      seedM3Defence(ctx.firestore(), { status: "inProgress" }));
    const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
    const bad = [
      highlight("adviser-uid"),
      highlight("pan-uid", { rect: { x: 0.6, y: 0.2, w: 0.5, h: 0.1 } }),
      highlight("pan-uid", { rect: { x: 0.1, y: 0.95, w: 0.5, h: 0.1 } }),
      highlight("pan-uid", { rect: { x: 0.1, y: 0.2, w: 0, h: 0.1 } }),
      highlight("pan-uid", { rect: { x: -0.1, y: 0.2, w: 0.5, h: 0.1 } }),
      highlight("pan-uid", { rect: { x: 0.1, y: 0.2, w: 0.5, h: 0.1, z: 1 } }),
      highlight("pan-uid", { rect: { x: 0.1, y: 0.2, w: 0.5 } }),
      highlight("pan-uid", { chapter: "chapterVI" }),
      highlight("pan-uid", { page: -1 }),
      highlight("pan-uid", { page: 1.5 }),
      highlight("pan-uid", { version: 0 }),
      highlight("pan-uid", { body: "" }),
      highlight("pan-uid", { body: "x".repeat(2001) }),
      highlight("pan-uid", { createdAt: Timestamp.now() }),
      highlight("pan-uid", { colour: "red" }),
    ];
    for (let i = 0; i < bad.length; i++) {
      await assertFails(
        setDoc(doc(pan, `defenses/df1/annotations/bad${i}`), bad[i]));
    }
    // Control: the longest comment allowed.
    await assertSucceeds(setDoc(doc(pan, "defenses/df1/annotations/ok1"),
      highlight("pan-uid", { body: "x".repeat(2000) })));
  });

test("highlights: a box drawn to the page edge saves", async () => {
  // 0.1 + 0.9 is 1.0000000000000002 in floating point; a box dragged to the
  // right edge must not be denied for it.
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) =>
    seedM3Defence(ctx.firestore(), { status: "inProgress" }));
  const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
  await assertSucceeds(setDoc(doc(pan, "defenses/df1/annotations/edge"),
    highlight("pan-uid", { rect: { x: 0.1, y: 0.7, w: 0.9, h: 0.3 } })));
});

test("highlights: the group reads them only after the adviser releases",
  async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedM3Defence(db, { status: "completed" });
      await setDoc(doc(db, "defenses/df1/annotations/h1"),
        { ...highlight("pan-uid"), createdAt: Timestamp.now() });
    });
    const leader = asDefUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
    const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");

    await assertFails(getDoc(doc(leader, "defenses/df1/annotations/h1")));
    await assertSucceeds(getDoc(doc(adv, "defenses/df1/annotations/h1")));
    await assertSucceeds(getDocs(collection(pan, "defenses/df1/annotations")));

    await assertSucceeds(updateDoc(doc(adv, "defenses/df1"),
      { consolidatedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(leader, "defenses/df1/annotations/h1")));
    await assertSucceeds(
      getDocs(collection(leader, "defenses/df1/annotations")));
  });

test("highlights: delete your own only while in progress, and never edit",
  async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled((ctx) =>
      seedM3Defence(ctx.firestore(), { status: "inProgress" }));
    const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
    const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
    const coord = asDefUser("coord-uid", "coord@isufst.edu.ph");

    await assertSucceeds(setDoc(doc(pan, "defenses/df1/annotations/h1"),
      highlight("pan-uid")));
    await assertFails(deleteDoc(doc(adv, "defenses/df1/annotations/h1")));
    await assertFails(updateDoc(doc(pan, "defenses/df1/annotations/h1"),
      { body: "Changed my mind." }));
    await assertSucceeds(deleteDoc(doc(pan, "defenses/df1/annotations/h1")));

    await assertSucceeds(setDoc(doc(pan, "defenses/df1/annotations/h2"),
      highlight("pan-uid")));
    await assertSucceeds(updateDoc(doc(coord, "defenses/df1"),
      { status: "completed" }));
    await assertFails(deleteDoc(doc(pan, "defenses/df1/annotations/h2")));
  });

test("typing: your own marker only, and never read by the group", async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled((ctx) =>
    seedM3Defence(ctx.firestore(), { status: "inProgress" }));
  const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
  const leader = asDefUser("leader-uid", "leader@isufst.edu.ph");
  const adv = asDefUser("adviser-uid", "adviser@isufst.edu.ph");
  const dean = asDefUser("dean-uid", "dean@isufst.edu.ph");

  await assertSucceeds(setDoc(doc(pan, "defenses/df1/composing/pan-uid"),
    marker()));
  await assertSucceeds(setDoc(doc(pan, "defenses/df1/composing/pan-uid"),
    marker({ target: "manuscript" })));
  await assertFails(setDoc(doc(pan, "defenses/df1/composing/adviser-uid"),
    marker()));
  await assertFails(setDoc(doc(pan, "defenses/df1/composing/pan-uid"),
    marker({ target: "elsewhere" })));
  await assertFails(setDoc(doc(pan, "defenses/df1/composing/pan-uid"),
    marker({ extra: 1 })));
  await assertFails(setDoc(doc(pan, "defenses/df1/composing/pan-uid"),
    marker({ updatedAt: Timestamp.now() })));

  await assertFails(getDoc(doc(leader, "defenses/df1/composing/pan-uid")));
  await assertFails(setDoc(doc(leader, "defenses/df1/composing/leader-uid"),
    marker()));
  await assertSucceeds(getDoc(doc(adv, "defenses/df1/composing/pan-uid")));
  await assertSucceeds(getDocs(collection(dean, "defenses/df1/composing")));

  await assertFails(deleteDoc(doc(adv, "defenses/df1/composing/pan-uid")));
  await assertSucceeds(deleteDoc(doc(pan, "defenses/df1/composing/pan-uid")));
});

test("typing: markers only while in progress, but your own may always be cleared",
  async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedM3Defence(db, { status: "completed" });
      await setDoc(doc(db, "defenses/df1/composing/pan-uid"),
        { ...marker(), updatedAt: Timestamp.now() });
    });
    const pan = asDefUser("pan-uid", "pan@isufst.edu.ph");
    await assertFails(setDoc(doc(pan, "defenses/df1/composing/pan-uid"),
      marker()));
    await assertSucceeds(deleteDoc(doc(pan, "defenses/df1/composing/pan-uid")));
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd rules-test && npm test`
Expected: FAIL. The new tests' `assertSucceeds` writes and reads are denied: there is no rule yet, so Firestore denies by default. The earlier tests pass.

- [ ] **Step 3: Add the rules**

In `firestore.rules`, directly after the closing `}` of `match /comments/{commentId} { … }` (after the line `allow update, delete: if false;` and its `}`), insert:

```
      // ---- Manuscript highlights (spec 2026-09-26 §8.1) ----
      //
      // A box on one page of an approved chapter, with a comment. Read like
      // the room comments: the panel throughout, the group once the adviser
      // has released. Written only while the defence is open.
      match /annotations/{annotationId} {
        function parent() {
          return get(/databases/$(database)/documents/defenses/$(defenseId)).data;
        }
        function mayComment() {
          let d = parent();
          return signedIn() && isActive() && (
            d.adviserUid == request.auth.uid ||
            request.auth.uid in d.panelUids
          );
        }
        function validRect(r) {
          return r is map
              && r.keys().hasAll(['x', 'y', 'w', 'h'])
              && r.keys().hasOnly(['x', 'y', 'w', 'h'])
              && r.x is number && r.y is number
              && r.w is number && r.h is number
              && r.x >= 0 && r.y >= 0 && r.w > 0 && r.h > 0
              // A hair of slack: 0.1 + 0.9 is not exactly 1.0 in floating
              // point, and a box drawn to the page's edge must not be denied.
              && r.x + r.w <= 1.001 && r.y + r.h <= 1.001;
        }

        allow get, list: if mayComment() || isCoordinator() || isDean()
                         || (signedIn()
                             && 'consolidatedAt' in parent()
                             && parent().leaderUid == request.auth.uid);

        allow create: if verified()
                      && (mayComment() || isCoordinator() || isDean())
                      && parent().status == 'inProgress'
                      && request.resource.data.keys().hasAll(
                           ['authorUid', 'authorName', 'authorPosition',
                            'chapter', 'version', 'page', 'rect', 'body',
                            'createdAt'])
                      && request.resource.data.keys().hasOnly(
                           ['authorUid', 'authorName', 'authorPosition',
                            'chapter', 'version', 'page', 'rect', 'body',
                            'createdAt'])
                      && request.resource.data.authorUid == request.auth.uid
                      && request.resource.data.chapter in
                           ['chapterI', 'chapterII', 'chapterIII',
                            'chapterIV', 'chapterV']
                      && request.resource.data.version is int
                      && request.resource.data.version >= 1
                      && request.resource.data.page is int
                      && request.resource.data.page >= 0
                      && validRect(request.resource.data.rect)
                      && request.resource.data.body is string
                      && request.resource.data.body.size() > 0
                      && request.resource.data.body.size() <= 2000
                      && request.resource.data.createdAt == request.time;

        // Your own, and only while the defence is open: once it closes the
        // set of highlights is the record.
        allow delete: if verified()
                      && resource.data.authorUid == request.auth.uid
                      && parent().status == 'inProgress';

        // No edits: delete and redraw.
        allow update: if false;
      }

      // ---- "Is typing" markers for the room (spec 2026-09-26 §4.2) ----
      //
      // The title defence's titleComposing, for a defence. Never the group:
      // an indicator would tell them remarks are being written about them.
      match /composing/{uid} {
        function parent() {
          return get(/databases/$(database)/documents/defenses/$(defenseId)).data;
        }
        function mayComment() {
          let d = parent();
          return signedIn() && isActive() && (
            d.adviserUid == request.auth.uid ||
            request.auth.uid in d.panelUids
          );
        }

        allow get, list: if mayComment() || isCoordinator() || isDean();

        allow create, update: if verified()
                              && (mayComment() || isCoordinator() || isDean())
                              && uid == request.auth.uid
                              && parent().status == 'inProgress'
                              && request.resource.data.keys().hasOnly(
                                   ['name', 'position', 'target', 'updatedAt'])
                              && request.resource.data.target
                                 in ['room', 'manuscript']
                              && request.resource.data.updatedAt
                                 == request.time;

        // Your own, whenever: a marker left by a closed laptop must still be
        // clearable after the defence ends.
        allow delete: if signedIn() && uid == request.auth.uid;
      }
```

- [ ] **Step 4: Run the rules tests**

Run: `cd rules-test && npm test`
Expected: PASS, every test.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat(rules): manuscript highlights and typing markers on a defence

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Highlight and typing-marker models, repository, providers

**Files:**
- Create: `lib/data/models/defence_annotation.dart`
- Create: `lib/data/models/defence_composing.dart`
- Modify: `lib/data/repositories/defence_repository.dart`: add imports, and methods after `addComment` (line 406)
- Modify: `lib/providers/defence_providers.dart`: add two providers after `defenceCommentsProvider` (line 57)
- Test: `test/data/models/defence_annotation_test.dart`
- Test: `test/data/repositories/defence_annotation_repository_test.dart`

**Interfaces:**
- Consumes: `ChapterId` (`lib/data/models/chapter.dart`), `ComposingIndicator.staleAfter`, `DefenceStatus.acceptsComments`
- Produces:
  - `class NormRect { final double x, y, w, h; factory NormRect.fromDrag(Offset a, Offset b, Size page); bool get isValid; bool get isBigEnough; Rect toRect(Size page); Map<String, double> toMap(); static NormRect? fromMap(Object?); static const minSide = 0.01; }`
  - `class DefenceAnnotation { id, authorUid, authorName, authorPosition, ChapterId chapter, int version, int page, NormRect rect, String body, DateTime? createdAt; static DefenceAnnotation? fromMap(String id, Map<String, dynamic>) }`
  - `const kAnnotationMaxLength = 2000;`
  - `enum ComposingTarget { room, manuscript }` with `value` and `static ComposingTarget fromString(String?)`
  - `class DefenceComposing { uid, name, position, ComposingTarget target, DateTime? updatedAt; bool isStaleAt(DateTime); factory fromMap(String uid, Map) }`
  - `DefenceRepository`:
    - `Stream<List<DefenceAnnotation>> watchAnnotations(String defenceId)` (oldest first)
    - `Future<void> addAnnotation({required String defenceId, required String authorUid, required String authorName, required String authorPosition, required ChapterId chapter, required int version, required int page, required NormRect rect, required String body})`
    - `Future<void> deleteAnnotation({required String defenceId, required String annotationId, required String uid})`
    - `Stream<List<DefenceComposing>> watchComposing(String defenceId)`
    - `Future<void> markComposing({required String defenceId, required String uid, required String name, required String position, required ComposingTarget target})`
    - `Future<void> clearComposing({required String defenceId, required String uid})`
  - `defenceAnnotationsProvider` (`StreamProvider.family<List<DefenceAnnotation>, String>`), `defenceComposingProvider` (`StreamProvider.family<List<DefenceComposing>, String>`)

- [ ] **Step 1: Write the failing model test**

Create `test/data/models/defence_annotation_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';

void main() {
  const page = Size(400, 600);

  group('NormRect.fromDrag', () {
    test('orders the corners and scales to the page', () {
      final r = NormRect.fromDrag(
          const Offset(300, 120), const Offset(100, 60), page);
      expect(r, const NormRect(x: 0.25, y: 0.1, w: 0.5, h: 0.1));
    });

    test('a drag past the page edge is clipped to it', () {
      final r = NormRect.fromDrag(
          const Offset(40, 540), const Offset(480, 700), page);
      expect(r.x, 0.1);
      expect(r.y, 0.9);
      expect(r.x + r.w, lessThanOrEqualTo(1.001));
      expect(r.y + r.h, lessThanOrEqualTo(1.001));
      expect(r.isValid, isTrue);
    });

    test('rounds to four places', () {
      final r = NormRect.fromDrag(
          const Offset(1, 1), const Offset(101, 101), const Size(300, 300));
      // 1/300 = 0.00333… and 101/300 = 0.33666…, each rounded first.
      expect(r.x, 0.0033);
      expect(r.w, 0.3334);
    });

    test('a tap is not big enough', () {
      final r = NormRect.fromDrag(
          const Offset(100, 100), const Offset(102, 101), page);
      expect(r.isBigEnough, isFalse);
    });
  });

  test('toRect is the inverse of fromDrag', () {
    // Quarters, so the products are exact in floating point.
    const r = NormRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5);
    expect(r.toRect(page), const Rect.fromLTWH(100, 150, 200, 300));
  });

  test('isValid refuses a box off the page or with no area', () {
    expect(const NormRect(x: 0.6, y: 0, w: 0.5, h: 0.1).isValid, isFalse);
    expect(const NormRect(x: 0, y: 0, w: 0, h: 0.1).isValid, isFalse);
    expect(const NormRect(x: -0.1, y: 0, w: 0.5, h: 0.1).isValid, isFalse);
  });

  test('fromMap reads ints and doubles and refuses a partial box', () {
    expect(NormRect.fromMap({'x': 0, 'y': 0.5, 'w': 1, 'h': 0.25}),
        const NormRect(x: 0, y: 0.5, w: 1, h: 0.25));
    expect(NormRect.fromMap({'x': 0, 'y': 0.5, 'w': 1}), isNull);
    expect(NormRect.fromMap('nope'), isNull);
  });

  group('DefenceAnnotation.fromMap', () {
    Map<String, dynamic> raw([Map<String, dynamic> extra = const {}]) => {
          'authorUid': 'p1',
          'authorName': 'Dr. Panel',
          'authorPosition': 'Panel Member',
          'chapter': 'chapterII',
          'version': 2,
          'page': 3,
          'rect': {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.05},
          'body': 'Cite it.',
          ...extra,
        };

    test('reads every field', () {
      final a = DefenceAnnotation.fromMap('h1', raw())!;
      expect(a.id, 'h1');
      expect(a.chapter, ChapterId.chapterII);
      expect(a.version, 2);
      expect(a.page, 3);
      expect(a.rect, const NormRect(x: 0.1, y: 0.2, w: 0.5, h: 0.05));
      expect(a.body, 'Cite it.');
    });

    test('is null for a record it cannot place', () {
      expect(DefenceAnnotation.fromMap('h1', raw({'chapter': 'chapterVI'})),
          isNull);
      expect(DefenceAnnotation.fromMap('h1', raw({'rect': null})), isNull);
      expect(DefenceAnnotation.fromMap('h1', raw({'page': null})), isNull);
    });
  });

  test('a composing marker is stale after 15 seconds', () {
    final at = DateTime(2026, 9, 26, 9);
    final m = DefenceComposing.fromMap('p1', {
      'name': 'Dr. Panel',
      'position': 'Panel Member',
      'target': 'manuscript',
      'updatedAt': at,
    });
    expect(m.target, ComposingTarget.manuscript);
    expect(m.isStaleAt(at.add(const Duration(seconds: 14))), isFalse);
    expect(m.isStaleAt(at.add(const Duration(seconds: 16))), isTrue);
    expect(ComposingTarget.fromString('bogus'), ComposingTarget.room);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/models/defence_annotation_test.dart`
Expected: FAIL to compile: `defence_annotation.dart` not found.

- [ ] **Step 3: Write the models**

Create `lib/data/models/defence_annotation.dart`:

```dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:ethesishub/data/models/chapter.dart';

/// The longest comment a highlight may carry. The same number is in
/// `firestore.rules`, which cannot import Dart.
const kAnnotationMaxLength = 2000;

/// A box on a page, as fractions 0–1 of the page's width and height, so it
/// lands on the same passage at any zoom or screen size.
class NormRect {
  const NormRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  /// The smallest side worth keeping. A tap or a slip of the finger draws
  /// something narrower than this.
  static const minSide = 0.01;

  /// The box between two points dragged on a page of [page] size, clipped
  /// to the page and rounded to four places.
  factory NormRect.fromDrag(Offset a, Offset b, Size page) {
    double fx(double v) => (v / page.width).clamp(0.0, 1.0);
    double fy(double v) => (v / page.height).clamp(0.0, 1.0);
    final left = _round(fx(math.min(a.dx, b.dx)));
    final right = _round(fx(math.max(a.dx, b.dx)));
    final top = _round(fy(math.min(a.dy, b.dy)));
    final bottom = _round(fy(math.max(a.dy, b.dy)));
    return NormRect(
      x: left,
      y: top,
      w: _round(right - left),
      h: _round(bottom - top),
    );
  }

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  /// Mirrors the rules' `validRect`, including its hair of slack at the edge.
  bool get isValid =>
      x >= 0 &&
      y >= 0 &&
      w > 0 &&
      h > 0 &&
      x + w <= 1.001 &&
      y + h <= 1.001;

  bool get isBigEnough => w >= minSide && h >= minSide;

  Rect toRect(Size page) => Rect.fromLTWH(
      x * page.width, y * page.height, w * page.width, h * page.height);

  Map<String, double> toMap() => {'x': x, 'y': y, 'w': w, 'h': h};

  static NormRect? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double? n(Object? v) => v is num ? v.toDouble() : null;
    final x = n(raw['x']);
    final y = n(raw['y']);
    final w = n(raw['w']);
    final h = n(raw['h']);
    if (x == null || y == null || w == null || h == null) return null;
    return NormRect(x: x, y: y, w: w, h: h);
  }

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'NormRect($x, $y, $w, $h)';
}

/// One highlight on the defence manuscript: a box on one page of one
/// chapter version, with a comment. Append-only, like the room comments;
/// its author may delete it while the defence is open.
///
/// `authorPosition` is stored, not derived, for the reason [DefenceComment]
/// gives: the position held at this defence must not change later.
class DefenceAnnotation {
  const DefenceAnnotation({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.authorPosition,
    required this.chapter,
    required this.version,
    required this.page,
    required this.rect,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String authorPosition;
  final ChapterId chapter;

  /// The chapter version the box was drawn on. A chapter reopened and
  /// re-approved later has a new version, and the box no longer fits it.
  final int version;

  /// 0-based, within that chapter's own file.
  final int page;
  final NormRect rect;
  final String body;
  final DateTime? createdAt;

  /// Null for a record this build cannot place (an unknown chapter, a
  /// malformed box), so one bad document hides itself instead of breaking
  /// the whole list.
  static DefenceAnnotation? fromMap(String id, Map<String, dynamic> map) {
    final chapter = ChapterId.fromString(map['chapter'] as String?);
    final rect = NormRect.fromMap(map['rect']);
    final version = (map['version'] as num?)?.toInt();
    final page = (map['page'] as num?)?.toInt();
    if (chapter == null || rect == null || version == null || page == null) {
      return null;
    }
    return DefenceAnnotation(
      id: id,
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorPosition: map['authorPosition'] as String? ?? '',
      chapter: chapter,
      version: version,
      page: page,
      rect: rect,
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
```

Create `lib/data/models/defence_composing.dart`:

```dart
import 'package:ethesishub/data/models/composing_indicator.dart';

/// Where in the defence room someone is writing.
enum ComposingTarget {
  /// The room comment box.
  room,

  /// A highlight's comment.
  manuscript;

  String get value => name;

  static ComposingTarget fromString(String? raw) =>
      raw == 'manuscript' ? ComposingTarget.manuscript : ComposingTarget.room;
}

/// "Someone is typing" in a defence room: [ComposingIndicator]'s mechanism,
/// keyed by uid under `defenses/{id}/composing`. Readers expire it, because
/// nothing sweeps a marker left by a closed laptop.
class DefenceComposing {
  const DefenceComposing({
    required this.uid,
    required this.name,
    required this.position,
    required this.target,
    this.updatedAt,
  });

  final String uid;
  final String name;
  final String position;
  final ComposingTarget target;
  final DateTime? updatedAt;

  bool isStaleAt(DateTime now) {
    final at = updatedAt;
    if (at == null) return true;
    return now.difference(at) > ComposingIndicator.staleAfter;
  }

  factory DefenceComposing.fromMap(String uid, Map<String, dynamic> map) {
    return DefenceComposing(
      uid: uid,
      name: map['name'] as String? ?? '',
      position: map['position'] as String? ?? '',
      target: ComposingTarget.fromString(map['target'] as String?),
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}
```

- [ ] **Step 4: Run the model test**

Run: `flutter test test/data/models/defence_annotation_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing repository test**

Create `test/data/repositories/defence_annotation_repository_test.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

Future<FakeFirebaseFirestore> seed({String status = 'inProgress'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'preOral',
    'panelUids': ['p1'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
  });
  return db;
}

const box = NormRect(x: 0.1, y: 0.2, w: 0.5, h: 0.05);

Future<void> add(DefenceRepository repo,
        {String uid = 'p1', String body = 'Cite it.', NormRect rect = box}) =>
    repo.addAnnotation(
      defenceId: 'd1',
      authorUid: uid,
      authorName: 'Dr. Panel',
      authorPosition: 'Panel Member',
      chapter: ChapterId.chapterII,
      version: 2,
      page: 3,
      rect: rect,
      body: body,
    );

void main() {
  test('adds a highlight with every field, trimmed', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    await add(repo, body: '  Cite it.  ');

    final docs = (await db.collection('defenses/d1/annotations').get()).docs;
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['authorUid'], 'p1');
    expect(data['chapter'], 'chapterII');
    expect(data['version'], 2);
    expect(data['page'], 3);
    expect(data['rect'], {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.05});
    expect(data['body'], 'Cite it.');
    expect(data['createdAt'], isA<Timestamp>());
  });

  test('refuses an empty or over-long comment, and a tiny box', () async {
    final repo = DefenceRepository(await seed());
    await expectLater(add(repo, body: '  '), throwsArgumentError);
    await expectLater(add(repo, body: 'x' * (kAnnotationMaxLength + 1)),
        throwsArgumentError);
    await expectLater(
        add(repo, rect: const NormRect(x: 0.1, y: 0.1, w: 0.001, h: 0.1)),
        throwsArgumentError);
  });

  test('refuses a highlight unless the defence is in progress', () async {
    for (final status in ['scheduled', 'completed', 'cancelled']) {
      final repo = DefenceRepository(await seed(status: status));
      await expectLater(add(repo), throwsStateError, reason: status);
    }
  });

  test('watches highlights oldest first and skips a malformed one', () async {
    final db = await seed();
    await db.collection('defenses/d1/annotations').doc('b').set({
      'authorUid': 'a1', 'chapter': 'chapterI', 'version': 1, 'page': 0,
      'rect': {'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5}, 'body': 'second',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 26, 9, 2)),
    });
    await db.collection('defenses/d1/annotations').doc('a').set({
      'authorUid': 'p1', 'chapter': 'chapterI', 'version': 1, 'page': 0,
      'rect': {'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5}, 'body': 'first',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 26, 9, 1)),
    });
    await db.collection('defenses/d1/annotations').doc('bad').set({
      'authorUid': 'p1', 'chapter': 'chapterIX', 'version': 1, 'page': 0,
      'rect': {'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5}, 'body': 'lost',
    });

    final list = await DefenceRepository(db).watchAnnotations('d1').first;
    expect(list.map((a) => a.body), ['first', 'second']);
  });

  test('deletes your own highlight only, and only while in progress',
      () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    await add(repo);
    final id = (await db.collection('defenses/d1/annotations').get())
        .docs
        .single
        .id;

    await expectLater(
        repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'a1'),
        throwsStateError);

    await db.collection('defenses').doc('d1').update({'status': 'completed'});
    await expectLater(
        repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'p1'),
        throwsStateError);

    await db.collection('defenses').doc('d1').update({'status': 'inProgress'});
    await repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'p1');
    expect((await db.collection('defenses/d1/annotations').get()).docs,
        isEmpty);
    // A second delete of the same highlight is not an error.
    await repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'p1');
  });

  test('marks, watches and clears a typing marker', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    await repo.markComposing(
      defenceId: 'd1',
      uid: 'p1',
      name: 'Dr. Panel',
      position: 'Panel Member',
      target: ComposingTarget.manuscript,
    );
    final markers = await repo.watchComposing('d1').first;
    expect(markers.single.uid, 'p1');
    expect(markers.single.target, ComposingTarget.manuscript);

    await repo.clearComposing(defenceId: 'd1', uid: 'p1');
    await repo.clearComposing(defenceId: 'd1', uid: 'p1');
    expect(await repo.watchComposing('d1').first, isEmpty);
  });
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `flutter test test/data/repositories/defence_annotation_repository_test.dart`
Expected: FAIL to compile: `addAnnotation` is not defined on `DefenceRepository`.

- [ ] **Step 7: Add the repository methods**

In `lib/data/repositories/defence_repository.dart`, add imports after the existing ones:

```dart
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
```

Insert after the closing `}` of `addComment` (before `/// The adviser's release, which is what opens the log to the group.`):

```dart
  CollectionReference<Map<String, dynamic>> _annotations(String defenceId) =>
      _defence(defenceId).collection('annotations');

  /// Oldest first, so a highlight's number (its place in this list) does not
  /// change as others arrive.
  Stream<List<DefenceAnnotation>> watchAnnotations(String defenceId) {
    return _annotations(defenceId).snapshots().map((s) {
      final list = <DefenceAnnotation>[];
      for (final d in s.docs) {
        final a = DefenceAnnotation.fromMap(d.id, {
          ...d.data(),
          'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate(),
        });
        if (a != null) list.add(a);
      }
      list.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null || bt == null) return a.id.compareTo(b.id);
        final byTime = at.compareTo(bt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
      return list;
    });
  }

  /// A highlight on the manuscript. Every check here is also a rule; they
  /// are repeated because fake_cloud_firestore enforces none of them, and a
  /// refusal here can say why.
  Future<void> addAnnotation({
    required String defenceId,
    required String authorUid,
    required String authorName,
    required String authorPosition,
    required ChapterId chapter,
    required int version,
    required int page,
    required NormRect rect,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Write a comment for this highlight.');
    if (text.length > kAnnotationMaxLength) {
      throw ArgumentError(
          'Keep the comment under $kAnnotationMaxLength characters.');
    }
    if (!rect.isValid || !rect.isBigEnough) {
      throw ArgumentError('Draw a box over the passage first.');
    }
    if (page < 0 || version < 1) {
      throw ArgumentError('That page is not part of the manuscript.');
    }

    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final status = DefenceStatus.fromString(snap.data()!['status'] as String?);
    if (!status.acceptsComments) {
      throw StateError(
          'Highlights can only be added while the defence is under way.');
    }

    await _annotations(defenceId).add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPosition': authorPosition,
      'chapter': chapter.value,
      'version': version,
      'page': page,
      'rect': rect.toMap(),
      'body': text,
      // The rule pins createdAt to request.time; see schedule().
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes the caller's own highlight while the defence is open. A
  /// highlight already gone is not an error: two taps must not throw.
  Future<void> deleteAnnotation({
    required String defenceId,
    required String annotationId,
    required String uid,
  }) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final status = DefenceStatus.fromString(snap.data()!['status'] as String?);
    if (status != DefenceStatus.inProgress) {
      throw StateError(
          'Highlights can only be removed while the defence is under way.');
    }
    final ref = _annotations(defenceId).doc(annotationId);
    final existing = await ref.get();
    if (!existing.exists) return;
    if (existing.data()!['authorUid'] != uid) {
      throw StateError('You can only remove your own highlights.');
    }
    await ref.delete();
  }

  CollectionReference<Map<String, dynamic>> _composing(String defenceId) =>
      _defence(defenceId).collection('composing');

  /// Live "is typing" markers, stale ones included; readers expire them.
  Stream<List<DefenceComposing>> watchComposing(String defenceId) {
    return _composing(defenceId).snapshots().map((s) => s.docs
        .map((d) => DefenceComposing.fromMap(d.id, {
              ...d.data(),
              'updatedAt': (d.data()['updatedAt'] as Timestamp?)?.toDate(),
            }))
        .toList());
  }

  /// Written when someone starts typing and about every 5 seconds after,
  /// never per keystroke: the Spark plan's daily write quota would not
  /// survive it. Keyed by uid, so one person makes one marker.
  Future<void> markComposing({
    required String defenceId,
    required String uid,
    required String name,
    required String position,
    required ComposingTarget target,
  }) {
    return _composing(defenceId).doc(uid).set({
      'name': name,
      'position': position,
      'target': target.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// On send, blur or leaving. A double clear is normal and must not throw.
  Future<void> clearComposing({
    required String defenceId,
    required String uid,
  }) {
    return _composing(defenceId).doc(uid).delete();
  }
```

- [ ] **Step 8: Add the providers**

In `lib/providers/defence_providers.dart`, add imports:

```dart
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
```

and after `defenceCommentsProvider`:

```dart
/// The manuscript highlights of one defence, oldest first.
final defenceAnnotationsProvider =
    StreamProvider.family<List<DefenceAnnotation>, String>((ref, defenceId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(defenceRepositoryProvider).watchAnnotations(defenceId);
});

/// Who is typing in one defence room. Denied to the group by the rules, so
/// only the panel side of the room watches it.
final defenceComposingProvider =
    StreamProvider.family<List<DefenceComposing>, String>((ref, defenceId) {
  ref.watch(signedInUidProvider);
  return ref.watch(defenceRepositoryProvider).watchComposing(defenceId);
});
```

- [ ] **Step 9: Run the tests**

Run: `flutter test test/data/models/defence_annotation_test.dart test/data/repositories/defence_annotation_repository_test.dart test/data/repositories/defence_repository_test.dart`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/data/models/defence_annotation.dart lib/data/models/defence_composing.dart lib/data/repositories/defence_repository.dart lib/providers/defence_providers.dart test/data/models/defence_annotation_test.dart test/data/repositories/defence_annotation_repository_test.dart
git commit -m "feat(defence): highlight and typing-marker records for the defence room

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The manuscript plan, byte loader and rasterizer

**Files:**
- Modify: `pubspec.yaml`: add `http: 1.6.0` under `url_launcher`
- Create: `lib/features/defence/manuscript/manuscript_plan.dart`
- Create: `lib/features/defence/manuscript/manuscript_providers.dart`
- Test: `test/features/defence/manuscript/manuscript_plan_test.dart`
- Test: `test/features/defence/manuscript/manuscript_providers_test.dart`

**Interfaces:**
- Consumes:
  - `chaptersProvider`, `chapterVersionsProvider` (`lib/providers/document_providers.dart`)
  - `storageServiceProvider`, `StorageFailure`
  - `DefenceType`, `DefenceAnnotation`
- Produces:
  - `enum ManuscriptPartKind { pdf, notApproved, notPdf, missing }`
  - `class ManuscriptPart { final ChapterId chapter; final ManuscriptPartKind kind; final ChapterVersion? version; }`
  - `List<ChapterId> manuscriptChapters(DefenceType)`
  - `String chapterNumeral(ChapterId)` → `'I'…'V'`
  - `bool isPdfVersion(ChapterVersion)`
  - `List<ManuscriptPart> planManuscript({required DefenceType type, required List<ThesisChapter> chapters, required Map<ChapterId, ChapterVersion> approvedVersions})`
  - `bool isOnCurrentVersion(DefenceAnnotation a, List<ManuscriptPart> parts)`
  - `typedef ManuscriptKey = ({String thesisId, DefenceType type});`
  - `manuscriptPartsProvider`: `Provider.autoDispose.family<AsyncValue<List<ManuscriptPart>>, ManuscriptKey>`
  - `typedef ChapterFileLoader = Future<Uint8List> Function(String storagePath);`
  - `chapterFileLoaderProvider`: `Provider<ChapterFileLoader>`
  - `abstract interface class ManuscriptRasterizer { Future<List<Size>> pageSizes(Uint8List pdf); Future<ui.Image> renderPage(Uint8List pdf, int index); }`
  - `manuscriptRasterizerProvider`: `Provider<ManuscriptRasterizer>`
  - `class ChapterPdf { final Uint8List bytes; final List<Size> pageSizes; }`
  - `chapterPdfProvider`: `FutureProvider.autoDispose.family<ChapterPdf, String>`, keyed by storage path

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, after the `url_launcher: 6.3.2` line, add:

```yaml
  # Downloads a chapter's bytes from its signed URL for the defence
  # manuscript. Already resolved at 1.6.0 through supabase; declared so lib/
  # may import it. No version moves.
  http: 1.6.0
```

Run: `flutter pub get`
Expected: exits 0; `pubspec.lock` shows `http` as `direct main` at 1.6.0.

- [ ] **Step 2: Write the failing plan test**

Create `test/features/defence/manuscript/manuscript_plan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';

ThesisChapter chapter(ChapterId id, ChapterStatus status, {int current = 1}) =>
    ThesisChapter(id: id, currentVersion: current, status: status);

ChapterVersion version(int n,
        {String mime = 'application/pdf', String path = 'theses/t1/c/a.pdf'}) =>
    ChapterVersion(
      version: n,
      storagePath: path,
      fileUrl: '',
      uploadedBy: 'l1',
      mimeType: mime,
      sizeBytes: 4,
    );

DefenceAnnotation note(ChapterId c, int v) => DefenceAnnotation(
      id: 'h',
      authorUid: 'p1',
      authorName: 'P',
      authorPosition: 'Panel Member',
      chapter: c,
      version: v,
      page: 0,
      rect: const NormRect(x: 0, y: 0, w: 0.5, h: 0.5),
      body: 'b',
    );

void main() {
  test('a pre-oral shows Chapters I to III, a final I to V', () {
    expect(manuscriptChapters(DefenceType.preOral),
        [ChapterId.chapterI, ChapterId.chapterII, ChapterId.chapterIII]);
    expect(manuscriptChapters(DefenceType.final_), ChapterId.values);
  });

  test('numerals', () {
    expect(ChapterId.values.map(chapterNumeral),
        ['I', 'II', 'III', 'IV', 'V']);
  });

  test('each chapter shows its pages or says why not', () {
    final parts = planManuscript(
      type: DefenceType.final_,
      chapters: [
        chapter(ChapterId.chapterI, ChapterStatus.approved, current: 2),
        chapter(ChapterId.chapterII, ChapterStatus.revise),
        chapter(ChapterId.chapterIII, ChapterStatus.approved),
        chapter(ChapterId.chapterV, ChapterStatus.approved),
      ],
      approvedVersions: {
        ChapterId.chapterI: version(2),
        ChapterId.chapterIII: version(1,
            mime: 'application/vnd.openxmlformats-officedocument'
                '.wordprocessingml.document',
            path: 'theses/t1/c/a.docx'),
      },
    );
    expect(parts.map((p) => p.kind), [
      ManuscriptPartKind.pdf,
      ManuscriptPartKind.notApproved,
      ManuscriptPartKind.notPdf,
      ManuscriptPartKind.missing, // IV was never uploaded
      ManuscriptPartKind.missing, // V approved, but its version is unreadable
    ]);
    expect(parts.first.version!.version, 2);
    expect(parts[2].version, isNotNull);
  });

  test('a PDF is recognised by its type or, failing that, its name', () {
    expect(isPdfVersion(version(1)), isTrue);
    expect(isPdfVersion(version(1, mime: 'application/octet-stream')),
        isTrue);
    expect(
        isPdfVersion(version(1,
            mime: 'application/msword', path: 'theses/t1/c/a.doc')),
        isFalse);
  });

  test('a highlight is current only on the version the manuscript shows', () {
    final parts = planManuscript(
      type: DefenceType.preOral,
      chapters: [
        chapter(ChapterId.chapterI, ChapterStatus.approved, current: 3),
      ],
      approvedVersions: {ChapterId.chapterI: version(3)},
    );
    expect(isOnCurrentVersion(note(ChapterId.chapterI, 3), parts), isTrue);
    expect(isOnCurrentVersion(note(ChapterId.chapterI, 2), parts), isFalse);
    expect(isOnCurrentVersion(note(ChapterId.chapterII, 1), parts), isFalse);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `flutter test test/features/defence/manuscript/manuscript_plan_test.dart`
Expected: FAIL to compile: `manuscript_plan.dart` not found.

- [ ] **Step 4: Write the planner**

Create `lib/features/defence/manuscript/manuscript_plan.dart`:

```dart
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';

/// What one chapter contributes to the defence manuscript.
enum ManuscriptPartKind {
  /// Approved, and its approved version is a PDF: its pages.
  pdf,

  /// Uploaded but not approved: one placeholder page.
  notApproved,

  /// Approved, but uploaded as a Word file before chapters became
  /// PDF-only: a placeholder with an Open file button.
  notPdf,

  /// Never uploaded, or its version record cannot be read.
  missing,
}

class ManuscriptPart {
  const ManuscriptPart({
    required this.chapter,
    required this.kind,
    this.version,
  });

  final ChapterId chapter;
  final ManuscriptPartKind kind;

  /// Set for [ManuscriptPartKind.pdf] and [ManuscriptPartKind.notPdf].
  final ChapterVersion? version;
}

/// The chapters a defence of [type] is about. A re-defence has the same
/// type as the defence it re-does, so it shows the same chapters.
List<ChapterId> manuscriptChapters(DefenceType type) =>
    type == DefenceType.preOral
        ? ChapterId.proposalChapters
        : ChapterId.finalChapters;

String chapterNumeral(ChapterId c) =>
    const ['I', 'II', 'III', 'IV', 'V'][c.index];

bool isPdfVersion(ChapterVersion v) =>
    v.mimeType == 'application/pdf' ||
    v.storagePath.toLowerCase().endsWith('.pdf');

/// The manuscript, chapter by chapter. [approvedVersions] holds, for each
/// approved chapter, the version whose number is its `currentVersion` — an
/// approved chapter cannot take a new upload, so that is the approved one.
List<ManuscriptPart> planManuscript({
  required DefenceType type,
  required List<ThesisChapter> chapters,
  required Map<ChapterId, ChapterVersion> approvedVersions,
}) {
  final byId = {for (final c in chapters) c.id: c};
  return [
    for (final id in manuscriptChapters(type))
      _partFor(id, byId[id], approvedVersions[id]),
  ];
}

ManuscriptPart _partFor(ChapterId id, ThesisChapter? c, ChapterVersion? v) {
  if (c == null) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.missing);
  }
  if (c.status != ChapterStatus.approved) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.notApproved);
  }
  if (v == null) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.missing);
  }
  if (!isPdfVersion(v)) {
    return ManuscriptPart(
        chapter: id, kind: ManuscriptPartKind.notPdf, version: v);
  }
  return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.pdf, version: v);
}

/// Whether [a] sits on the chapter version the manuscript shows now. One
/// drawn before the chapter was reopened and re-approved does not, and is
/// listed as being on an earlier version instead of drawn on the wrong page.
bool isOnCurrentVersion(DefenceAnnotation a, List<ManuscriptPart> parts) =>
    parts.any((p) =>
        p.chapter == a.chapter &&
        p.kind == ManuscriptPartKind.pdf &&
        p.version?.version == a.version);
```

- [ ] **Step 5: Run the plan test**

Run: `flutter test test/features/defence/manuscript/manuscript_plan_test.dart`
Expected: PASS.

- [ ] **Step 6: Write the failing providers test**

Create `test/features/defence/manuscript/manuscript_providers_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class _SizesOnly implements ManuscriptRasterizer {
  _SizesOnly(this.count);
  final int count;
  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async =>
      List.filled(count, const Size(210, 297));
  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) =>
      throw UnimplementedError();
}

ProviderContainer container(FakeFirebaseFirestore db,
    {List<Override> overrides = const []}) {
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'p1', email: 'p1@isufst.edu.ph'),
    )),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('reads the approved version of each approved chapter', () async {
    final db = FakeFirebaseFirestore();
    final docs = db.collection('theses/t1/documents');
    await docs.doc('chapterI').set(
        {'type': 'chapterI', 'currentVersion': 2, 'status': 'approved'});
    for (final n in [1, 2]) {
      await docs.doc('chapterI').collection('versions').doc('$n').set({
        'version': n,
        'storagePath': 'theses/t1/chapterI/v$n.pdf',
        'fileUrl': '',
        'uploadedBy': 'l1',
        'uploadedAt': Timestamp.now(),
        'mimeType': 'application/pdf',
        'sizeBytes': 4,
      });
    }
    await docs.doc('chapterII').set(
        {'type': 'chapterII', 'currentVersion': 1, 'status': 'revise'});

    final c = container(db);
    const key = (thesisId: 't1', type: DefenceType.preOral);
    c.listen(manuscriptPartsProvider(key), (_, _) {});
    List<ManuscriptPart>? parts;
    for (var i = 0; i < 20 && parts == null; i++) {
      await Future<void>.delayed(Duration.zero);
      parts = c.read(manuscriptPartsProvider(key)).valueOrNull;
    }

    expect(parts!.map((p) => p.kind), [
      ManuscriptPartKind.pdf,
      ManuscriptPartKind.notApproved,
      ManuscriptPartKind.missing,
    ]);
    expect(parts.first.version!.storagePath, 'theses/t1/chapterI/v2.pdf');
  });

  test('a chapter PDF is downloaded once and measured', () async {
    var downloads = 0;
    final c = container(FakeFirebaseFirestore(), overrides: [
      chapterFileLoaderProvider.overrideWithValue((path) async {
        downloads++;
        return Uint8List(4);
      }),
      manuscriptRasterizerProvider.overrideWithValue(_SizesOnly(3)),
    ]);
    c.listen(chapterPdfProvider('p.pdf'), (_, _) {});
    final pdf = await c.read(chapterPdfProvider('p.pdf').future);
    await c.read(chapterPdfProvider('p.pdf').future);
    expect(pdf.pageSizes, hasLength(3));
    expect(downloads, 1);
  });

  test('a PDF with no pages is a failure, not an empty chapter', () async {
    final c = container(FakeFirebaseFirestore(), overrides: [
      chapterFileLoaderProvider.overrideWithValue((path) async => Uint8List(4)),
      manuscriptRasterizerProvider.overrideWithValue(_SizesOnly(0)),
    ]);
    c.listen(chapterPdfProvider('p.pdf'), (_, _) {});
    await expectLater(c.read(chapterPdfProvider('p.pdf').future),
        throwsA(isA<StorageFailure>()));
  });
}
```

- [ ] **Step 7: Run to verify it fails**

Run: `flutter test test/features/defence/manuscript/manuscript_providers_test.dart`
Expected: FAIL to compile: `manuscript_providers.dart` not found.

- [ ] **Step 8: Write the providers**

Create `lib/features/defence/manuscript/manuscript_providers.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

typedef ManuscriptKey = ({String thesisId, DefenceType type});

/// The defence manuscript's chapters, each with what it shows. Loading until
/// every approved chapter's versions have arrived, so a chapter is never
/// shown as missing when it is merely still loading.
final manuscriptPartsProvider = Provider.autoDispose
    .family<AsyncValue<List<ManuscriptPart>>, ManuscriptKey>((ref, key) {
  final chaptersAsync = ref.watch(chaptersProvider(key.thesisId));
  if (chaptersAsync.hasError) {
    return AsyncValue.error(
        chaptersAsync.error!, chaptersAsync.stackTrace ?? StackTrace.current);
  }
  final chapters = chaptersAsync.valueOrNull;
  if (chapters == null) return const AsyncValue.loading();

  final wanted = manuscriptChapters(key.type);
  final approved = [
    for (final c in chapters)
      if (wanted.contains(c.id) && c.status == ChapterStatus.approved) c,
  ];
  // Watch every one before deciding, so they load side by side.
  final versionsAsync = {
    for (final c in approved)
      c.id: ref.watch(
          chapterVersionsProvider((thesisId: key.thesisId, chapter: c.id))),
  };

  final approvedVersions = <ChapterId, ChapterVersion>{};
  for (final c in approved) {
    final v = versionsAsync[c.id]!;
    if (v.hasError) {
      return AsyncValue.error(v.error!, v.stackTrace ?? StackTrace.current);
    }
    final list = v.valueOrNull;
    if (list == null) return const AsyncValue.loading();
    for (final version in list) {
      if (version.version == c.currentVersion) {
        approvedVersions[c.id] = version;
        break;
      }
    }
  }
  return AsyncValue.data(planManuscript(
    type: key.type,
    chapters: chapters,
    approvedVersions: approvedVersions,
  ));
});

/// Fetches a stored file's bytes: a fresh signed URL (the bucket is
/// private), then the download.
typedef ChapterFileLoader = Future<Uint8List> Function(String storagePath);

final chapterFileLoaderProvider = Provider<ChapterFileLoader>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return (path) async {
    final url = await storage.signedUrl(path);
    http.Response res;
    try {
      res = await http.get(Uri.parse(url));
    } catch (_) {
      throw const StorageFailure(
        'Could not download this chapter. Check the connection and open the '
        'room again.',
        code: 'storage-download',
      );
    }
    if (res.statusCode != 200) {
      throw StorageFailure(
        'Could not download this chapter. The server answered '
        '${res.statusCode}.',
        code: 'storage-download',
      );
    }
    return res.bodyBytes;
  };
});

/// Draws PDF pages. An interface so widget tests can draw without `printing`.
abstract interface class ManuscriptRasterizer {
  /// Every page's size, in any unit: only the shape is used.
  Future<List<Size>> pageSizes(Uint8List pdf);

  /// One page as an image; the caller disposes it.
  Future<ui.Image> renderPage(Uint8List pdf, int index);
}

class PrintingManuscriptRasterizer implements ManuscriptRasterizer {
  const PrintingManuscriptRasterizer();

  /// Tiny: this pass only learns how many pages there are and their shape.
  static const double probeDpi = 12;

  /// Readable at the viewer's largest zoom on a laptop, and one page at a
  /// time, so a long chapter is never held in memory whole.
  static const double pageDpi = 150;

  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async {
    final sizes = <Size>[];
    await for (final page in Printing.raster(pdf, dpi: probeDpi)) {
      sizes.add(Size(page.width.toDouble(), page.height.toDouble()));
    }
    return sizes;
  }

  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) async {
    final page =
        await Printing.raster(pdf, pages: [index], dpi: pageDpi).first;
    return page.toImage();
  }
}

final manuscriptRasterizerProvider = Provider<ManuscriptRasterizer>(
    (ref) => const PrintingManuscriptRasterizer());

/// One chapter's file, downloaded and measured.
class ChapterPdf {
  const ChapterPdf({required this.bytes, required this.pageSizes});

  final Uint8List bytes;
  final List<Size> pageSizes;
}

/// Keyed by storage path, which is unique per version, so a re-approved
/// chapter is fetched afresh. Auto-disposed: a closed room frees the bytes.
final chapterPdfProvider = FutureProvider.autoDispose
    .family<ChapterPdf, String>((ref, storagePath) async {
  final bytes = await ref.watch(chapterFileLoaderProvider)(storagePath);
  final sizes = await ref.watch(manuscriptRasterizerProvider).pageSizes(bytes);
  if (sizes.isEmpty) {
    throw const StorageFailure(
      "This chapter's PDF has no pages that can be shown.",
      code: 'pdf-empty',
    );
  }
  return ChapterPdf(bytes: bytes, pageSizes: sizes);
});
```

- [ ] **Step 9: Run the tests**

Run: `flutter test test/features/defence/manuscript/`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/defence/manuscript/manuscript_plan.dart lib/features/defence/manuscript/manuscript_providers.dart test/features/defence/manuscript/manuscript_plan_test.dart test/features/defence/manuscript/manuscript_providers_test.dart
git commit -m "feat(defence): plan the manuscript from each chapter's approved version

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Highlight colours, numbers, page order and legend

**Files:**
- Create: `lib/features/defence/manuscript/highlight_colours.dart`
- Test: `test/features/defence/manuscript/highlight_colours_test.dart`

**Interfaces:**
- Consumes: `Defence`, `DefenceAnnotation`
- Produces:
  - `const List<Color> kHighlightPalette` (8 colours)
  - `Map<String, Color> highlightColours({required Defence defence, required List<DefenceAnnotation> annotations})`, keyed by uid
  - `Map<String, int> highlightNumbers(List<DefenceAnnotation> oldestFirst)`, annotation id → 1-based number
  - `List<DefenceAnnotation> inPageOrder(List<DefenceAnnotation> list)`
  - `class HighlightAuthor { final String uid; final String name; final Color colour; }`
  - `List<HighlightAuthor> highlightLegend(List<DefenceAnnotation> annotations, Map<String, Color> colours)`
  - `class HighlightTag extends StatelessWidget { const HighlightTag({super.key, required int number, required Color colour}); }`

- [ ] **Step 1: Write the failing test**

Create `test/features/defence/manuscript/highlight_colours_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';

Defence defence({List<String> panel = const ['p1', 'p2']}) => Defence(
      id: 'd1',
      thesisId: 't1',
      type: DefenceType.preOral,
      venue: 'AVR',
      panelUids: panel,
      adviserUid: 'a1',
      leaderUid: 'l1',
      status: DefenceStatus.inProgress,
      createdBy: 'c1',
    );

DefenceAnnotation note(String id, String uid,
        {ChapterId chapter = ChapterId.chapterI,
        int page = 0,
        double y = 0,
        String name = ''}) =>
    DefenceAnnotation(
      id: id,
      authorUid: uid,
      authorName: name.isEmpty ? uid : name,
      authorPosition: 'Panel Member',
      chapter: chapter,
      version: 1,
      page: page,
      rect: NormRect(x: 0, y: y, w: 0.5, h: 0.05),
      body: id,
    );

void main() {
  test('eight distinct colours', () {
    expect(kHighlightPalette, hasLength(8));
    expect(kHighlightPalette.toSet(), hasLength(8));
  });

  test('adviser, then panel in order, then others by first highlight', () {
    final colours = highlightColours(
      defence: defence(),
      annotations: [note('h1', 'dean1'), note('h2', 'p2'), note('h3', 'c1')],
    );
    expect(colours['a1'], kHighlightPalette[0]);
    expect(colours['p1'], kHighlightPalette[1]);
    expect(colours['p2'], kHighlightPalette[2]);
    expect(colours['dean1'], kHighlightPalette[3]);
    expect(colours['c1'], kHighlightPalette[4]);
  });

  test('the same defence gives everyone the same colours', () {
    final list = [note('h1', 'c1'), note('h2', 'p1')];
    expect(highlightColours(defence: defence(), annotations: list),
        highlightColours(defence: defence(), annotations: list));
  });

  test('wraps after eight', () {
    final panel = [for (var i = 0; i < 8; i++) 'p$i'];
    final colours =
        highlightColours(defence: defence(panel: panel), annotations: []);
    // a1 is 0, p0..p7 are 1..8, so p7 wraps to 0.
    expect(colours['p7'], kHighlightPalette[0]);
  });

  test('numbers follow creation order; the list follows page order', () {
    final oldestFirst = [
      note('late-page', 'p1', chapter: ChapterId.chapterII, page: 4),
      note('early-page', 'p1', chapter: ChapterId.chapterI, page: 2, y: 0.5),
      note('earliest', 'p1', chapter: ChapterId.chapterI, page: 2, y: 0.1),
    ];
    expect(highlightNumbers(oldestFirst),
        {'late-page': 1, 'early-page': 2, 'earliest': 3});
    expect(inPageOrder(oldestFirst).map((a) => a.id),
        ['earliest', 'early-page', 'late-page']);
  });

  test('the legend lists who has highlighted, in colour order', () {
    final list = [
      note('h1', 'c1', name: 'Coordinator'),
      note('h2', 'p1', name: 'Dr. Panel'),
    ];
    final colours = highlightColours(defence: defence(), annotations: list);
    final legend = highlightLegend(list, colours);
    expect(legend.map((a) => a.name), ['Dr. Panel', 'Coordinator']);
    expect(legend.first.colour, kHighlightPalette[1]);
  });

  testWidgets('a tag shows its number', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: HighlightTag(number: 7, colour: Color(0xFF0072B2))));
    expect(find.text('7'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/defence/manuscript/highlight_colours_test.dart`
Expected: FAIL to compile: `highlight_colours.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/features/defence/manuscript/highlight_colours.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';

/// Eight colours told apart by most colour-blind readers too (after
/// Okabe and Ito), so each person's highlights are recognisably theirs.
const kHighlightPalette = <Color>[
  Color(0xFFE69F00), // orange
  Color(0xFF56B4E9), // sky blue
  Color(0xFF009E73), // green
  Color(0xFFF0E442), // yellow
  Color(0xFF0072B2), // blue
  Color(0xFFD55E00), // vermilion
  Color(0xFFCC79A7), // pink
  Color(0xFF8C6BB1), // violet
];

/// Each person's colour on this defence: the adviser first, then the panel
/// in the order they were named, then anyone else (the Coordinator, the
/// Dean) in the order of their first highlight. Computed, not stored, so
/// every viewer sees the same colours. [annotations] must be oldest first.
Map<String, Color> highlightColours({
  required Defence defence,
  required List<DefenceAnnotation> annotations,
}) {
  final order = <String>[];
  void add(String uid) {
    if (uid.isNotEmpty && !order.contains(uid)) order.add(uid);
  }

  add(defence.adviserUid);
  defence.panelUids.forEach(add);
  for (final a in annotations) {
    add(a.authorUid);
  }
  return {
    for (var i = 0; i < order.length; i++)
      order[i]: kHighlightPalette[i % kHighlightPalette.length],
  };
}

/// Each highlight's number: its place in creation order, so "see 3" still
/// means the same box after others are added.
Map<String, int> highlightNumbers(List<DefenceAnnotation> oldestFirst) => {
      for (var i = 0; i < oldestFirst.length; i++) oldestFirst[i].id: i + 1,
    };

/// Chapter, then page, then down the page: the order a reader meets them.
List<DefenceAnnotation> inPageOrder(List<DefenceAnnotation> list) =>
    [...list]..sort((a, b) {
        final byChapter = a.chapter.index.compareTo(b.chapter.index);
        if (byChapter != 0) return byChapter;
        final byPage = a.page.compareTo(b.page);
        if (byPage != 0) return byPage;
        final byY = a.rect.y.compareTo(b.rect.y);
        if (byY != 0) return byY;
        return a.rect.x.compareTo(b.rect.x);
      });

class HighlightAuthor {
  const HighlightAuthor({
    required this.uid,
    required this.name,
    required this.colour,
  });

  final String uid;
  final String name;
  final Color colour;
}

/// Who has highlighted, in colour order, with the name from their first one.
List<HighlightAuthor> highlightLegend(
  List<DefenceAnnotation> annotations,
  Map<String, Color> colours,
) {
  final names = <String, String>{};
  for (final a in annotations) {
    names.putIfAbsent(a.authorUid, () => a.authorName);
  }
  return [
    for (final entry in colours.entries)
      if (names.containsKey(entry.key))
        HighlightAuthor(
            uid: entry.key, name: names[entry.key]!, colour: entry.value),
  ];
}

/// A highlight's number in its author's colour, on the box and in the list.
class HighlightTag extends StatelessWidget {
  const HighlightTag({super.key, required this.number, required this.colour});

  final int number;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final ink =
        colour.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$number',
        style: TextStyle(
            color: ink, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/defence/manuscript/highlight_colours_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/defence/manuscript/highlight_colours.dart test/features/defence/manuscript/highlight_colours_test.dart
git commit -m "feat(defence): a highlight colour per person, by roster order

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The typing heartbeat and the typing line

**Files:**
- Create: `lib/features/defence/manuscript/defence_typing.dart`
- Test: `test/features/defence/manuscript/defence_typing_test.dart`

**Interfaces:**
- Consumes: `DefenceRepository.markComposing/clearComposing`, `DefenceComposing`, `ComposingTarget`
- Produces:
  - `class DefenceTyping { DefenceTyping({required DefenceRepository repo, required String defenceId, required String uid, required String name, required String position, Duration beat = const Duration(seconds: 5)}); void typing(ComposingTarget target, {required bool active}); void stop(); void dispose(); bool get isTyping; }`
  - `String? typingText(List<String> names)`
  - `class TypingLine extends StatefulWidget { const TypingLine({super.key, required List<DefenceComposing> markers, required ComposingTarget target, String? myUid, DateTime Function()? now}); }`, keyed `Key('typingLine-${target.name}')` when shown

- [ ] **Step 1: Write the failing test**

Create `test/features/defence/manuscript/defence_typing_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';
import 'package:ethesishub/features/defence/manuscript/defence_typing.dart';

DefenceComposing marker(String uid, String name,
        {ComposingTarget target = ComposingTarget.room, DateTime? at}) =>
    DefenceComposing(
      uid: uid,
      name: name,
      position: 'Panel Member',
      target: target,
      updatedAt: at ?? DateTime(2026, 9, 26, 9),
    );

void main() {
  test('typingText', () {
    expect(typingText([]), isNull);
    expect(typingText(['Dr. Santos']), 'Dr. Santos is typing…');
    expect(typingText(['Dr. Santos', 'Prof. Cruz']),
        'Dr. Santos and Prof. Cruz are typing…');
    expect(typingText(['A', 'B', 'C', 'D']), 'A, B and 2 more are typing…');
  });

  group('DefenceTyping', () {
    late FakeFirebaseFirestore db;
    late DefenceTyping typing;

    setUp(() {
      db = FakeFirebaseFirestore();
      typing = DefenceTyping(
        repo: DefenceRepository(db),
        defenceId: 'd1',
        uid: 'p1',
        name: 'Dr. Panel',
        position: 'Panel Member',
      );
    });

    Future<Map<String, dynamic>?> read() async =>
        (await db.doc('defenses/d1/composing/p1').get()).data();

    test('writes a marker when typing starts and clears it when it stops',
        () async {
      typing.typing(ComposingTarget.room, active: true);
      await pumpEventQueue();
      expect((await read())!['target'], 'room');
      expect(typing.isTyping, isTrue);

      typing.typing(ComposingTarget.room, active: false);
      await pumpEventQueue();
      expect(await read(), isNull);
      expect(typing.isTyping, isFalse);
      typing.dispose();
    });

    test('moving to the highlight box rewrites the target', () async {
      typing.typing(ComposingTarget.room, active: true);
      typing.typing(ComposingTarget.manuscript, active: true);
      await pumpEventQueue();
      expect((await read())!['target'], 'manuscript');
      // Stopping the room box does not stop the highlight box.
      typing.typing(ComposingTarget.room, active: false);
      await pumpEventQueue();
      expect(await read(), isNotNull);
      typing.dispose();
    });

    test('dispose clears the marker', () async {
      typing.typing(ComposingTarget.room, active: true);
      await pumpEventQueue();
      typing.dispose();
      await pumpEventQueue();
      expect(await read(), isNull);
    });
  });

  group('TypingLine', () {
    final now = DateTime(2026, 9, 26, 9, 0, 5);

    Future<void> pump(WidgetTester tester, List<DefenceComposing> markers,
            {ComposingTarget target = ComposingTarget.room}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TypingLine(
              markers: markers,
              target: target,
              myUid: 'me',
              now: () => now,
            ),
          ),
        ));

    testWidgets('names others typing in this box', (tester) async {
      await pump(tester, [
        marker('a1', 'Dr. Santos'),
        marker('p2', 'Prof. Cruz'),
      ]);
      expect(find.text('Dr. Santos and Prof. Cruz are typing…'),
          findsOneWidget);
      expect(find.byKey(const Key('typingLine-room')), findsOneWidget);
    });

    testWidgets('never shows yourself, a stale marker, or the other box',
        (tester) async {
      await pump(tester, [
        marker('me', 'Me'),
        marker('a1', 'Dr. Santos', at: DateTime(2026, 9, 26, 8, 59, 40)),
        marker('p2', 'Prof. Cruz', target: ComposingTarget.manuscript),
      ]);
      expect(find.byKey(const Key('typingLine-room')), findsNothing);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/defence/manuscript/defence_typing_test.dart`
Expected: FAIL to compile: `defence_typing.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/features/defence/manuscript/defence_typing.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

/// One person's "is typing" marker in a defence room: written when they
/// start, refreshed every [beat] while they keep at it, deleted when they
/// stop, send or leave.
class DefenceTyping {
  DefenceTyping({
    required DefenceRepository repo,
    required this.defenceId,
    required this.uid,
    required this.name,
    required this.position,
    this.beat = const Duration(seconds: 5),
  }) : _repo = repo;

  final DefenceRepository _repo;
  final String defenceId;
  final String uid;
  final String name;
  final String position;
  final Duration beat;

  ComposingTarget? _target;
  Timer? _timer;

  bool get isTyping => _target != null;

  /// [active] is whether the box for [target] has focus and text. Turning
  /// one box off leaves a marker for the other box alone.
  void typing(ComposingTarget target, {required bool active}) {
    if (active) {
      final changed = _target != target;
      _target = target;
      if (changed) _write();
      _timer ??= Timer.periodic(beat, (_) => _write());
    } else if (_target == target) {
      stop();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_target == null) return;
    _target = null;
    _quiet(_repo.clearComposing(defenceId: defenceId, uid: uid));
  }

  void dispose() => stop();

  void _write() {
    final target = _target;
    if (target == null) return;
    _quiet(_repo.markComposing(
      defenceId: defenceId,
      uid: uid,
      name: name,
      position: position,
      target: target,
    ));
  }

  /// A marker is decoration: a refused or failed write costs the reader
  /// nothing, and must not surface as an uncaught error (see the title
  /// defence screen's `_presence`).
  static void _quiet(Future<void> write) {
    write.catchError((Object _) {});
  }
}

/// "Dr. Santos is typing…", "Dr. Santos and Prof. Cruz are typing…", or
/// null when nobody is.
String? typingText(List<String> names) {
  if (names.isEmpty) return null;
  if (names.length == 1) return '${names.first} is typing…';
  if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
  return '${names[0]}, ${names[1]} and ${names.length - 2} more are typing…';
}

/// Who else is typing in one box of the room. Re-checks every few seconds
/// so a marker left behind by a closed laptop disappears on its own.
class TypingLine extends StatefulWidget {
  const TypingLine({
    super.key,
    required this.markers,
    required this.target,
    this.myUid,
    this.now,
  });

  final List<DefenceComposing> markers;
  final ComposingTarget target;
  final String? myUid;

  /// The clock, for tests.
  final DateTime Function()? now;

  @override
  State<TypingLine> createState() => _TypingLineState();
}

class _TypingLineState extends State<TypingLine> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now)();
    final names = [
      for (final m in widget.markers)
        if (m.target == widget.target &&
            m.uid != widget.myUid &&
            !m.isStaleAt(now))
          m.name,
    ];
    final text = typingText(names);
    if (text == null) return const SizedBox.shrink();
    final seal = Palette.of(context).seal;
    return Padding(
      key: Key('typingLine-${widget.target.name}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 18, color: seal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: seal, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
```

If `Palette` is not exported by `core/design/tone.dart`, import the file that `defence_room_screen.dart` gets `Palette` from. It uses `Palette.of(context)` with the imports shown at the top of that file.

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/defence/manuscript/defence_typing_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/defence/manuscript/defence_typing.dart test/features/defence/manuscript/defence_typing_test.dart
git commit -m "feat(defence): a typing heartbeat and typing line for the defence room

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The manuscript view

**Files:**
- Create: `lib/features/defence/manuscript/manuscript_view.dart`
- Test: `test/features/defence/manuscript/manuscript_view_test.dart`

**Interfaces:**
- Consumes:
  - `ManuscriptPart`, `ManuscriptPartKind`, `chapterNumeral`
  - `chapterPdfProvider`, `manuscriptRasterizerProvider`, `ChapterPdf`
  - `DefenceAnnotation`, `NormRect`, `HighlightTag`, `kHighlightPalette`
- Produces:
  - `class DrawnHighlight { final ChapterId chapter; final int version; final int page; final NormRect rect; }`
  - `class ManuscriptController extends ChangeNotifier { DefenceAnnotation? get target; void reveal(DefenceAnnotation a); }`
  - `class ManuscriptView extends ConsumerStatefulWidget { const ManuscriptView({super.key, required List<ManuscriptPart> parts, List<DefenceAnnotation> annotations = const [], Map<String, Color> colours = const {}, Map<String, int> numbers = const {}, bool canHighlight = false, String? highlightClosedReason, void Function(DrawnHighlight)? onHighlightDrawn, void Function(ChapterVersion)? onOpenFile, ManuscriptController? controller}); }`
  - Keys:
    - `manuscriptPages` (the ListView)
    - `highlightTool`, `highlightClosed`
    - `manuscriptZoomOut`, `manuscriptZoomIn`, `manuscriptZoomLevel`
    - `chapterHeader-<chapterId>`, `chapterLoading-<id>`, `chapterFailed-<id>`, `chapterNotApproved-<id>`, `chapterNotPdf-<id>`, `chapterMissing-<id>`, `openChapterFile-<id>`
    - `drawSurface-<chapterId>-<page>`, `highlightBox-<annotationId>`

Ruling recorded in this plan (spec §5 said "pinch, drag, and zoom buttons"):
- Zoom is by buttons (100/150/200/300%), with horizontal scrolling when wider than the view. Pinch-zoom is not built. The lazy page list (the spec's memory requirement) and an `InteractiveViewer` do not compose, because the viewer builds its whole child.
- The Highlight tool switches off after each box, so a drag scrolls the pages again.

Task 10 records both in the spec.

- [ ] **Step 1: Write the failing test**

Create `test/features/defence/manuscript/manuscript_view_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';

class FakeRasterizer implements ManuscriptRasterizer {
  FakeRasterizer(this.image, {this.pages = 2});
  final ui.Image image;
  final int pages;
  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async =>
      List.filled(pages, const Size(210, 297));
  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) async => image.clone();
}

ChapterVersion v(int n, {String path = 'theses/t1/chapterI/a.pdf',
        String mime = 'application/pdf'}) =>
    ChapterVersion(
      version: n,
      storagePath: path,
      fileUrl: '',
      uploadedBy: 'l1',
      mimeType: mime,
      sizeBytes: 4,
    );

DefenceAnnotation note(String id,
        {int version = 2, int page = 0, double y = 0.1}) =>
    DefenceAnnotation(
      id: id,
      authorUid: 'p1',
      authorName: 'Dr. Panel',
      authorPosition: 'Panel Member',
      chapter: ChapterId.chapterI,
      version: version,
      page: page,
      rect: NormRect(x: 0.1, y: y, w: 0.5, h: 0.05),
      body: 'b',
    );

final pdfPart = ManuscriptPart(
    chapter: ChapterId.chapterI, kind: ManuscriptPartKind.pdf, version: v(2));

Future<ui.Image> page(WidgetTester tester) async =>
    (await tester.runAsync(() => createTestImage(width: 210, height: 297)))!;

Future<void> pumpView(
  WidgetTester tester,
  Widget view, {
  required ui.Image image,
  int pages = 2,
  ChapterFileLoader? loader,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      chapterFileLoaderProvider
          .overrideWithValue(loader ?? (path) async => Uint8List(4)),
      manuscriptRasterizerProvider
          .overrideWithValue(FakeRasterizer(image, pages: pages)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 600, child: view)),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('shows each chapter: pages, or a placeholder saying why',
      (tester) async {
    ChapterVersion? opened;
    await pumpView(
      tester,
      ManuscriptView(
        parts: [
          pdfPart,
          const ManuscriptPart(
              chapter: ChapterId.chapterII,
              kind: ManuscriptPartKind.notApproved),
          ManuscriptPart(
              chapter: ChapterId.chapterIII,
              kind: ManuscriptPartKind.notPdf,
              version: v(1, path: 'x.docx', mime: 'application/msword')),
        ],
        onOpenFile: (version) => opened = version,
      ),
      image: await page(tester),
    );

    expect(find.byKey(const Key('chapterHeader-chapterI')), findsOneWidget);
    expect(find.byKey(const Key('drawSurface-chapterI-0')), findsNothing,
        reason: 'no drawing surface unless the tool is on');
    expect(find.text('Ch. I · p. 1'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('chapterNotPdf-chapterIII')), 300,
        scrollable: find.descendant(
            of: find.byKey(const Key('manuscriptPages')),
            matching: find.byType(Scrollable)));
    expect(find.text('Chapter II is not approved yet.'), findsOneWidget);
    expect(
        find.text(
            "Chapter III was uploaded as a Word file and can't be shown here."),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('openChapterFile-chapterIII')));
    expect(opened?.storagePath, 'x.docx');
  });

  testWidgets('a missing chapter says so', (tester) async {
    await pumpView(
      tester,
      const ManuscriptView(parts: [
        ManuscriptPart(
            chapter: ChapterId.chapterIV, kind: ManuscriptPartKind.missing),
      ]),
      image: await page(tester),
    );
    expect(find.text('Chapter IV has not been uploaded.'), findsOneWidget);
  });

  testWidgets('a chapter that fails to load says so and the rest still show',
      (tester) async {
    await pumpView(
      tester,
      ManuscriptView(parts: [
        pdfPart,
        const ManuscriptPart(
            chapter: ChapterId.chapterII,
            kind: ManuscriptPartKind.notApproved),
      ]),
      image: await page(tester),
      loader: (path) async =>
          throw const StorageFailure('Could not download this chapter.',
              code: 'storage-download'),
    );
    expect(find.byKey(const Key('chapterFailed-chapterI')), findsOneWidget);
    expect(find.textContaining('Could not download this chapter.'),
        findsOneWidget);
    expect(find.text('Chapter II is not approved yet.'), findsOneWidget);
  });

  testWidgets('draws a box only on its own page and version', (tester) async {
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        annotations: [note('current'), note('old', version: 1)],
        numbers: const {'current': 1, 'old': 2},
      ),
      image: await page(tester),
    );
    expect(find.byKey(const Key('highlightBox-current')), findsOneWidget);
    expect(find.byKey(const Key('highlightBox-old')), findsNothing);
  });

  testWidgets('the tool is hidden when closed, with the reason',
      (tester) async {
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        highlightClosedReason: 'Highlighting opens when the defence starts.',
      ),
      image: await page(tester),
    );
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.text('Highlighting opens when the defence starts.'),
        findsOneWidget);
  });

  testWidgets('dragging with the tool on reports the box, then turns it off',
      (tester) async {
    DrawnHighlight? drawn;
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        canHighlight: true,
        onHighlightDrawn: (d) => drawn = d,
      ),
      image: await page(tester),
    );
    await tester.tap(find.byKey(const Key('highlightTool')));
    await tester.pump();

    final surface = find.byKey(const Key('drawSurface-chapterI-0'));
    final origin = tester.getTopLeft(surface);
    await tester.dragFrom(origin + const Offset(40, 50), const Offset(200, 30));
    await tester.pump();

    expect(drawn, isNotNull);
    expect(drawn!.chapter, ChapterId.chapterI);
    expect(drawn!.version, 2);
    expect(drawn!.page, 0);
    // The page is 376 wide (400 less the list's 12 + 12 padding), and the
    // drag starts where the finger went down: x 40/376, w 200/376.
    expect(drawn!.rect.x, closeTo(40 / 376, 0.01));
    expect(drawn!.rect.w, closeTo(200 / 376, 0.01));
    expect(find.byKey(const Key('drawSurface-chapterI-0')), findsNothing);
  });

  testWidgets('a tap with the tool on draws nothing', (tester) async {
    DrawnHighlight? drawn;
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        canHighlight: true,
        onHighlightDrawn: (d) => drawn = d,
      ),
      image: await page(tester),
    );
    await tester.tap(find.byKey(const Key('highlightTool')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('drawSurface-chapterI-0')));
    await tester.pump();
    expect(drawn, isNull);
  });

  testWidgets('zoom widens the pages', (tester) async {
    await pumpView(tester, ManuscriptView(parts: [pdfPart]),
        image: await page(tester));
    final before =
        tester.getSize(find.byKey(const Key('pageTile-chapterI-2-0'))).width;
    await tester.tap(find.byKey(const Key('manuscriptZoomIn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('150%'), findsOneWidget);
    final after =
        tester.getSize(find.byKey(const Key('pageTile-chapterI-2-0'))).width;
    expect(after, closeTo(before * 1.5, 1));
  });

  testWidgets('reveal scrolls to a highlight and marks it', (tester) async {
    final controller = ManuscriptController();
    addTearDown(controller.dispose);
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        annotations: [note('far', page: 5, y: 0.5)],
        numbers: const {'far': 1},
        controller: controller,
      ),
      image: await page(tester),
      pages: 6,
    );
    controller.reveal(note('far', page: 5, y: 0.5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('manuscriptPages')),
        matching: find.byType(Scrollable)));
    expect(scrollable.position.pixels, greaterThan(2000));
    final box = tester.widget<DecoratedBox>(
        find.byKey(const Key('highlightBox-far')));
    expect((box.decoration as BoxDecoration).border!.top.width, 3);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/defence/manuscript/manuscript_view_test.dart`
Expected: FAIL to compile: `manuscript_view.dart` not found.

- [ ] **Step 3: Write the view**

Create `lib/features/defence/manuscript/manuscript_view.dart`:

```dart
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';

/// A box the reader has just drawn, before it has a comment.
class DrawnHighlight {
  const DrawnHighlight({
    required this.chapter,
    required this.version,
    required this.page,
    required this.rect,
  });

  final ChapterId chapter;
  final int version;
  final int page;
  final NormRect rect;
}

/// Lets a screen scroll the manuscript to a highlight.
class ManuscriptController extends ChangeNotifier {
  DefenceAnnotation? _target;

  DefenceAnnotation? get target => _target;

  void reveal(DefenceAnnotation a) {
    _target = a;
    notifyListeners();
  }
}

/// The defence manuscript: each chapter's pages one after another, drawn a
/// page at a time as they scroll into view and released when far away, so a
/// long thesis is never held in a phone's memory whole.
class ManuscriptView extends ConsumerStatefulWidget {
  const ManuscriptView({
    super.key,
    required this.parts,
    this.annotations = const [],
    this.colours = const {},
    this.numbers = const {},
    this.canHighlight = false,
    this.highlightClosedReason,
    this.onHighlightDrawn,
    this.onOpenFile,
    this.controller,
  });

  final List<ManuscriptPart> parts;
  final List<DefenceAnnotation> annotations;

  /// By author uid; see [highlightColours].
  final Map<String, Color> colours;

  /// By annotation id; see [highlightNumbers].
  final Map<String, int> numbers;

  /// Whether the Highlight tool is offered at all.
  final bool canHighlight;

  /// Shown where the tool would be, when it is not offered yet.
  final String? highlightClosedReason;
  final void Function(DrawnHighlight)? onHighlightDrawn;
  final void Function(ChapterVersion)? onOpenFile;
  final ManuscriptController? controller;

  static const double headerExtent = 44;
  static const double noteExtent = 168;
  static const double loadingExtent = 240;
  static const double pageGap = 12;
  static const zoomSteps = [1.0, 1.5, 2.0, 3.0];

  @override
  ConsumerState<ManuscriptView> createState() => _ManuscriptViewState();
}

sealed class _Item {
  const _Item(this.part);
  final ManuscriptPart part;
}

class _Header extends _Item {
  const _Header(super.part);
}

class _Page extends _Item {
  const _Page(super.part, this.pdf, this.index);
  final ChapterPdf pdf;
  final int index;
}

enum _NoteKind { loading, failed, notApproved, notPdf, missing }

class _Note extends _Item {
  const _Note(super.part, this.kind, [this.error]);
  final _NoteKind kind;
  final Object? error;
}

class _ManuscriptViewState extends ConsumerState<ManuscriptView> {
  final _scroll = ScrollController();
  int _zoomIndex = 0;
  bool _tool = false;
  String? _pulseId;
  Timer? _pulseTimer;
  List<_Item> _items = const [];
  double _width = 0;

  double get _zoom => ManuscriptView.zoomSteps[_zoomIndex];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onReveal);
  }

  @override
  void didUpdateWidget(covariant ManuscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onReveal);
      widget.controller?.addListener(_onReveal);
    }
    if (!widget.canHighlight) _tool = false;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onReveal);
    _pulseTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<_Item> _buildItems() {
    final items = <_Item>[];
    for (final part in widget.parts) {
      items.add(_Header(part));
      switch (part.kind) {
        case ManuscriptPartKind.pdf:
          ref.watch(chapterPdfProvider(part.version!.storagePath)).when(
                data: (pdf) {
                  for (var i = 0; i < pdf.pageSizes.length; i++) {
                    items.add(_Page(part, pdf, i));
                  }
                },
                loading: () => items.add(_Note(part, _NoteKind.loading)),
                error: (e, _) => items.add(_Note(part, _NoteKind.failed, e)),
              );
        case ManuscriptPartKind.notApproved:
          items.add(_Note(part, _NoteKind.notApproved));
        case ManuscriptPartKind.notPdf:
          items.add(_Note(part, _NoteKind.notPdf));
        case ManuscriptPartKind.missing:
          items.add(_Note(part, _NoteKind.missing));
      }
    }
    return items;
  }

  double _extentOf(_Item item, double width) => switch (item) {
        _Header() => ManuscriptView.headerExtent,
        _Page(:final pdf, :final index) => width *
                pdf.pageSizes[index].height /
                pdf.pageSizes[index].width +
            ManuscriptView.pageGap,
        _Note(kind: _NoteKind.loading) => ManuscriptView.loadingExtent,
        _Note() => ManuscriptView.noteExtent,
      };

  void _onReveal() {
    final a = widget.controller?.target;
    if (a == null || !_scroll.hasClients) return;
    var offset = 0.0;
    for (final item in _items) {
      if (item is _Page &&
          item.part.chapter == a.chapter &&
          item.part.version?.version == a.version &&
          item.index == a.page) {
        final pageHeight = _extentOf(item, _width) - ManuscriptView.pageGap;
        final to = (offset + a.rect.y * pageHeight - 48)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.animateTo(to,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
        setState(() => _pulseId = a.id);
        _pulseTimer?.cancel();
        _pulseTimer = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _pulseId = null);
        });
        return;
      }
      offset += _extentOf(item, _width);
    }
  }

  void _setZoom(int index) {
    final old = _zoom;
    final at = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() => _zoomIndex = index);
    final ratio = _zoom / old;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
          (at * ratio).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  void _drawn(DrawnHighlight d) {
    setState(() => _tool = false);
    widget.onHighlightDrawn?.call(d);
  }

  @override
  Widget build(BuildContext context) {
    _items = _buildItems();
    final text = Theme.of(context).textTheme;

    final toolbar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (widget.canHighlight)
            _tool
                ? FilledButton.icon(
                    key: const Key('highlightTool'),
                    onPressed: () => setState(() => _tool = false),
                    icon: const Icon(Icons.highlight_alt, size: 18),
                    label: const Text('Drag over a passage'),
                  )
                : OutlinedButton.icon(
                    key: const Key('highlightTool'),
                    onPressed: () => setState(() => _tool = true),
                    icon: const Icon(Icons.highlight_alt, size: 18),
                    label: const Text('Highlight'),
                  )
          else if (widget.highlightClosedReason != null)
            Flexible(
              child: Text(
                widget.highlightClosedReason!,
                key: const Key('highlightClosed'),
                style: text.bodySmall,
              ),
            ),
          const Spacer(),
          IconButton(
            key: const Key('manuscriptZoomOut'),
            tooltip: 'Zoom out',
            onPressed: _zoomIndex > 0 ? () => _setZoom(_zoomIndex - 1) : null,
            icon: const Icon(Icons.zoom_out),
          ),
          Text('${(_zoom * 100).round()}%',
              key: const Key('manuscriptZoomLevel'), style: text.labelMedium),
          IconButton(
            key: const Key('manuscriptZoomIn'),
            tooltip: 'Zoom in',
            onPressed: _zoomIndex < ManuscriptView.zoomSteps.length - 1
                ? () => _setZoom(_zoomIndex + 1)
                : null,
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF3A3F47),
            child: LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 24) * _zoom;
              _width = width;
              final locked = _tool;
              final list = SizedBox(
                width: width + 24,
                child: ListView.builder(
                  key: const Key('manuscriptPages'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  physics:
                      locked ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _items.length,
                  itemExtentBuilder: (i, _) =>
                      i < _items.length ? _extentOf(_items[i], width) : null,
                  itemBuilder: (context, i) => _buildItem(_items[i], width),
                ),
              );
              if (_zoomIndex == 0) return list;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                child: list,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(_Item item, double width) {
    final part = item.part;
    final numeral = chapterNumeral(part.chapter);
    final id = part.chapter.name;
    switch (item) {
      case _Header():
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              part.chapter.label.toUpperCase(),
              key: Key('chapterHeader-$id'),
              style: const TextStyle(
                  color: Color(0xFFB8C4CF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6),
            ),
          ),
        );
      case _Page(:final pdf, :final index):
        return _PageTile(
          key: Key('pageTile-$id-${part.version!.version}-$index'),
          part: part,
          pdf: pdf,
          index: index,
          width: width,
          annotations: [
            for (final a in widget.annotations)
              if (a.chapter == part.chapter &&
                  a.version == part.version!.version &&
                  a.page == index)
                a,
          ],
          colours: widget.colours,
          numbers: widget.numbers,
          pulseId: _pulseId,
          drawing: _tool,
          onDrawn: _drawn,
        );
      case _Note(:final kind, :final error):
        return _NoteTile(
          key: Key(switch (kind) {
            _NoteKind.loading => 'chapterLoading-$id',
            _NoteKind.failed => 'chapterFailed-$id',
            _NoteKind.notApproved => 'chapterNotApproved-$id',
            _NoteKind.notPdf => 'chapterNotPdf-$id',
            _NoteKind.missing => 'chapterMissing-$id',
          }),
          loading: kind == _NoteKind.loading,
          message: switch (kind) {
            _NoteKind.loading => 'Loading Chapter $numeral…',
            _NoteKind.failed => 'Chapter $numeral could not be loaded.'
                '${error is StorageFailure ? ' ${error.message}' : ''}',
            _NoteKind.notApproved => 'Chapter $numeral is not approved yet.',
            _NoteKind.notPdf => 'Chapter $numeral was uploaded as a Word '
                "file and can't be shown here.",
            _NoteKind.missing => 'Chapter $numeral has not been uploaded.',
          },
          action: kind == _NoteKind.notPdf && widget.onOpenFile != null
              ? OutlinedButton.icon(
                  key: Key('openChapterFile-$id'),
                  onPressed: () => widget.onOpenFile!(part.version!),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open file'),
                )
              : null,
        );
    }
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    super.key,
    required this.message,
    this.loading = false,
    this.action,
  });

  final String message;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ManuscriptView.pageGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 12),
                ],
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87)),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTile extends ConsumerStatefulWidget {
  const _PageTile({
    super.key,
    required this.part,
    required this.pdf,
    required this.index,
    required this.width,
    required this.annotations,
    required this.colours,
    required this.numbers,
    required this.pulseId,
    required this.drawing,
    required this.onDrawn,
  });

  final ManuscriptPart part;
  final ChapterPdf pdf;
  final int index;
  final double width;
  final List<DefenceAnnotation> annotations;
  final Map<String, Color> colours;
  final Map<String, int> numbers;
  final String? pulseId;
  final bool drawing;
  final void Function(DrawnHighlight) onDrawn;

  @override
  ConsumerState<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends ConsumerState<_PageTile> {
  ui.Image? _image;
  Object? _error;
  Offset? _start;
  Offset? _end;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    try {
      final image = await ref
          .read(manuscriptRasterizerProvider)
          .renderPage(widget.pdf.bytes, widget.index);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Widget _box(DefenceAnnotation a, Size page) {
    final colour = widget.colours[a.authorUid] ?? kHighlightPalette.last;
    final number = widget.numbers[a.id];
    return Positioned.fromRect(
      rect: a.rect.toRect(page),
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                key: Key('highlightBox-${a.id}'),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.28),
                  border: Border.all(
                      color: colour, width: widget.pulseId == a.id ? 3 : 1.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (number != null)
              Positioned(
                top: -10,
                right: -10,
                child: HighlightTag(number: number, colour: colour),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.pdf.pageSizes[widget.index];
    final height = widget.width * shape.height / shape.width;
    final pageSize = Size(widget.width, height);
    final chapterId = widget.part.chapter.name;

    Widget page = Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
              ],
            ),
            child: _image != null
                ? RawImage(image: _image, fit: BoxFit.fill)
                : Center(
                    child: _error != null
                        ? const Text('This page could not be drawn.',
                            style: TextStyle(color: Colors.black54))
                        : const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
          ),
        ),
        for (final a in widget.annotations) _box(a, pageSize),
        if (_start != null && _end != null)
          Positioned.fromRect(
            rect: Rect.fromPoints(_start!, _end!),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.blue, width: 1.5),
                ),
              ),
            ),
          ),
        Positioned(
          right: 6,
          bottom: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Ch. ${chapterNumeral(widget.part.chapter)} · '
                'p. ${widget.index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.drawing) {
      page = GestureDetector(
        key: Key('drawSurface-$chapterId-${widget.index}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => setState(() {
          _start = d.localPosition;
          _end = d.localPosition;
        }),
        onPanUpdate: (d) => setState(() => _end = d.localPosition),
        onPanEnd: (_) {
          final start = _start;
          final end = _end;
          setState(() {
            _start = null;
            _end = null;
          });
          if (start == null || end == null) return;
          final rect = NormRect.fromDrag(start, end, pageSize);
          if (!rect.isBigEnough) return;
          widget.onDrawn(DrawnHighlight(
            chapter: widget.part.chapter,
            version: widget.part.version!.version,
            page: widget.index,
            rect: rect,
          ));
        },
        onPanCancel: () => setState(() {
          _start = null;
          _end = null;
        }),
        child: page,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: ManuscriptView.pageGap),
      child: SizedBox(width: widget.width, height: height, child: page),
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/defence/manuscript/manuscript_view_test.dart`
Expected: PASS. If "a tap with the tool on draws nothing" reports a `DrawnHighlight`, it is because a tap arrives as a zero-length pan and passes `isBigEnough`. Check `NormRect.minSide` is applied (`rect.isBigEnough`) before `onDrawn`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/defence/manuscript/manuscript_view.dart test/features/defence/manuscript/manuscript_view_test.dart
git commit -m "feat(defence): the manuscript view, drawn a page at a time, with highlights

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The highlight list, the Highlights tab and the comment dialog

**Files:**
- Create: `lib/features/defence/manuscript/highlights_panel.dart`
- Test: `test/features/defence/manuscript/highlights_panel_test.dart`

**Interfaces:**
- Consumes:
  - `highlightColours`, `highlightNumbers`, `inPageOrder`, `highlightLegend`, `HighlightTag`
  - `isOnCurrentVersion`, `chapterNumeral`, `manuscriptPartsProvider`, `ManuscriptPart`
  - `TypingLine`, `defenceAnnotationsProvider`, `defenceComposingProvider`, `kAnnotationMaxLength`
- Produces:
  - `class HighlightsList extends StatelessWidget { const HighlightsList({super.key, required List<DefenceAnnotation> annotations, List<ManuscriptPart>? parts, required Map<String, Color> colours, required Map<String, int> numbers, String? myUid, bool canDelete = false, void Function(DefenceAnnotation)? onSelect, void Function(DefenceAnnotation)? onDelete}); }`
  - `class HighlightsTab extends ConsumerWidget { const HighlightsTab({super.key, required Defence defence, String? myUid, void Function(DefenceAnnotation)? onSelect, void Function(DefenceAnnotation)? onDelete}); }`
  - `Future<String?> showHighlightComposer(BuildContext context, {void Function(bool typing)? onTyping})`
  - Keys: `highlightsEmpty`, `highlightLegend`, `highlightRow-<id>`, `highlightStale-<id>`, `deleteHighlight-<id>`, `highlightBody`, `saveHighlight`, `cancelHighlight`

- [ ] **Step 1: Write the failing test**

Create `test/features/defence/manuscript/highlights_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/highlights_panel.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';

DefenceAnnotation note(String id, String uid,
        {int page = 0, int version = 2, String body = 'b'}) =>
    DefenceAnnotation(
      id: id,
      authorUid: uid,
      authorName: uid == 'p1' ? 'Dr. Panel' : 'Dr. Adviser',
      authorPosition: uid == 'p1' ? 'Panel Member' : 'Adviser',
      chapter: ChapterId.chapterI,
      version: version,
      page: page,
      rect: const NormRect(x: 0, y: 0, w: 0.5, h: 0.1),
      body: body,
    );

final parts = [
  ManuscriptPart(
    chapter: ChapterId.chapterI,
    kind: ManuscriptPartKind.pdf,
    version: const ChapterVersion(
        version: 2,
        storagePath: 'a.pdf',
        fileUrl: '',
        uploadedBy: 'l1',
        mimeType: 'application/pdf',
        sizeBytes: 4),
  ),
];

Future<void> pumpList(WidgetTester tester, List<DefenceAnnotation> list,
    {bool canDelete = true,
    void Function(DefenceAnnotation)? onSelect,
    void Function(DefenceAnnotation)? onDelete}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HighlightsList(
          annotations: list,
          parts: parts,
          colours: const {'a1': Color(0xFFE69F00), 'p1': Color(0xFF56B4E9)},
          numbers: highlightNumbers(list),
          myUid: 'p1',
          canDelete: canDelete,
          onSelect: onSelect,
          onDelete: onDelete,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('nothing yet', (tester) async {
    await pumpList(tester, []);
    expect(find.byKey(const Key('highlightsEmpty')), findsOneWidget);
  });

  testWidgets('lists in page order, numbered by creation, with a legend',
      (tester) async {
    await pumpList(tester, [
      note('h1', 'a1', page: 4, body: 'later page'),
      note('h2', 'p1', page: 1, body: 'earlier page'),
    ]);
    final rows = tester
        .widgetList<InkWell>(find.byWidgetPredicate((w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('highlightRow-')))
        .map((w) => (w.key! as ValueKey<String>).value)
        .toList();
    expect(rows, ['highlightRow-h2', 'highlightRow-h1']);
    expect(find.text('Dr. Panel, Panel Member · Ch. I p. 2'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('highlightLegend')),
            matching: find.text('Dr. Adviser')),
        findsOneWidget);
  });

  testWidgets('marks a highlight on an earlier version', (tester) async {
    await pumpList(tester, [note('old', 'p1', version: 1)]);
    expect(find.text('On an earlier version of Chapter I'), findsOneWidget);
  });

  testWidgets('delete is offered only on your own, and only when allowed',
      (tester) async {
    DefenceAnnotation? deleted;
    await pumpList(tester, [note('mine', 'p1'), note('theirs', 'a1')],
        onDelete: (a) => deleted = a);
    expect(find.byKey(const Key('deleteHighlight-theirs')), findsNothing);
    await tester.tap(find.byKey(const Key('deleteHighlight-mine')));
    expect(deleted?.id, 'mine');

    await pumpList(tester, [note('mine', 'p1')], canDelete: false);
    expect(find.byKey(const Key('deleteHighlight-mine')), findsNothing);
  });

  testWidgets('tapping a row selects it', (tester) async {
    DefenceAnnotation? selected;
    await pumpList(tester, [note('h1', 'p1')], onSelect: (a) => selected = a);
    await tester.tap(find.byKey(const Key('highlightRow-h1')));
    expect(selected?.id, 'h1');
  });

  testWidgets('the comment dialog returns the text and reports typing',
      (tester) async {
    final typing = <bool>[];
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showHighlightComposer(context,
                  onTyping: typing.add);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('saveHighlight'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('highlightBody')), '  Cite the data.  ');
    await tester.pump();
    expect(typing, [true]);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, 'Cite the data.');
    expect(typing, [true, false]);
  });

  testWidgets('cancelling the dialog returns nothing', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showHighlightComposer(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelHighlight')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/defence/manuscript/highlights_panel_test.dart`
Expected: FAIL to compile: `highlights_panel.dart` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/features/defence/manuscript/highlights_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/features/defence/manuscript/defence_typing.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Every highlight in page order, with a legend of who is which colour.
class HighlightsList extends StatelessWidget {
  const HighlightsList({
    super.key,
    required this.annotations,
    this.parts,
    required this.colours,
    required this.numbers,
    this.myUid,
    this.canDelete = false,
    this.onSelect,
    this.onDelete,
  });

  /// Oldest first.
  final List<DefenceAnnotation> annotations;

  /// The manuscript as shown now, to mark highlights on an earlier version.
  /// Null while it is still loading: nothing is marked until it is known.
  final List<ManuscriptPart>? parts;
  final Map<String, Color> colours;
  final Map<String, int> numbers;
  final String? myUid;
  final bool canDelete;
  final void Function(DefenceAnnotation)? onSelect;
  final void Function(DefenceAnnotation)? onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (annotations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
        child: Text(
          'No highlights yet. Boxes drawn on the manuscript appear here.',
          key: const Key('highlightsEmpty'),
          style: text.bodySmall,
        ),
      );
    }
    final legend = highlightLegend(annotations, colours);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: const Key('highlightLegend'),
          spacing: AppTokens.md,
          runSpacing: AppTokens.xs,
          children: [
            for (final a in legend)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: a.colour, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(a.name, style: text.labelMedium),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppTokens.sm),
        for (final a in inPageOrder(annotations)) _row(context, a),
      ],
    );
  }

  Widget _row(BuildContext context, DefenceAnnotation a) {
    final text = Theme.of(context).textTheme;
    final numeral = chapterNumeral(a.chapter);
    final current = parts == null || isOnCurrentVersion(a, parts!);
    final colour = colours[a.authorUid] ?? kHighlightPalette.last;
    return InkWell(
      key: Key('highlightRow-${a.id}'),
      onTap: current && onSelect != null ? () => onSelect!(a) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HighlightTag(number: numbers[a.id] ?? 0, colour: colour),
            const SizedBox(width: AppTokens.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.authorName}, ${a.authorPosition} · '
                    'Ch. $numeral p. ${a.page + 1}',
                    style: text.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(a.body, style: text.bodyMedium),
                  if (!current)
                    Text(
                      'On an earlier version of Chapter $numeral',
                      key: Key('highlightStale-${a.id}'),
                      style: text.bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
            ),
            if (canDelete && a.authorUid == myUid && onDelete != null)
              IconButton(
                key: Key('deleteHighlight-${a.id}'),
                tooltip: 'Remove highlight',
                onPressed: () => onDelete!(a),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}

/// The room's Highlights tab: who is writing a highlight comment, then the
/// list.
class HighlightsTab extends ConsumerWidget {
  const HighlightsTab({
    super.key,
    required this.defence,
    this.myUid,
    this.onSelect,
    this.onDelete,
  });

  final Defence defence;
  final String? myUid;
  final void Function(DefenceAnnotation)? onSelect;
  final void Function(DefenceAnnotation)? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationsAsync = ref.watch(defenceAnnotationsProvider(defence.id));
    final composing =
        ref.watch(defenceComposingProvider(defence.id)).valueOrNull ??
            const <DefenceComposing>[];
    final parts = ref
        .watch(manuscriptPartsProvider(
            (thesisId: defence.thesisId, type: defence.type)))
        .valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTokens.md, AppTokens.sm, AppTokens.md, AppTokens.md),
      child: annotationsAsync.when(
        loading: () => const LoadingState(label: 'Loading highlights…'),
        error: (e, _) =>
            ErrorState(error: e, message: 'Could not load the highlights.'),
        data: (list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TypingLine(
              markers: composing,
              target: ComposingTarget.manuscript,
              myUid: myUid,
            ),
            HighlightsList(
              annotations: list,
              parts: parts,
              colours: highlightColours(defence: defence, annotations: list),
              numbers: highlightNumbers(list),
              myUid: myUid,
              canDelete: defence.status == DefenceStatus.inProgress,
              onSelect: onSelect,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the comment on a box just drawn. The trimmed text, or null if
/// cancelled. [onTyping] is told when the box gains and loses text, for the
/// typing indicator.
Future<String?> showHighlightComposer(
  BuildContext context, {
  void Function(bool typing)? onTyping,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _HighlightComposer(onTyping: onTyping),
  );
}

class _HighlightComposer extends StatefulWidget {
  const _HighlightComposer({this.onTyping});

  final void Function(bool typing)? onTyping;

  @override
  State<_HighlightComposer> createState() => _HighlightComposerState();
}

class _HighlightComposerState extends State<_HighlightComposer> {
  final _body = TextEditingController();
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _body.addListener(_changed);
  }

  void _changed() {
    final now = _body.text.trim().isNotEmpty;
    if (now != _typing) {
      _typing = now;
      widget.onTyping?.call(now);
    }
    setState(() {});
  }

  @override
  void dispose() {
    if (_typing) widget.onTyping?.call(false);
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _body.text.trim();
    return AlertDialog(
      title: const Text('Comment on this passage'),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('highlightBody'),
          controller: _body,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          maxLength: kAnnotationMaxLength,
          decoration: const InputDecoration(
              hintText: 'What should the group look at here?'),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelHighlight'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('saveHighlight'),
          onPressed: text.isEmpty ? null : () => Navigator.of(context).pop(text),
          child: const Text('Save highlight'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the test**

Run: `flutter test test/features/defence/manuscript/highlights_panel_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/defence/manuscript/highlights_panel.dart test/features/defence/manuscript/highlights_panel_test.dart
git commit -m "feat(defence): the highlight list, Highlights tab and comment dialog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: The room, the read-only manuscript route, and the leader's button

**Files:**
- Create: `lib/features/defence/manuscript/manuscript_pane.dart`
- Create: `lib/features/defence/manuscript/defence_manuscript_screen.dart`
- Modify: `lib/features/defence/defence_room_screen.dart`
- Modify: `lib/core/routing/app_router.dart`: add a route after `/defence/room/:defenceId/consolidated` (line ~690)
- Modify: `lib/core/widgets/app_shell_host.dart:60-64`
- Test: `test/features/defence/defence_room_manuscript_test.dart`
- Modify test: `test/core/routing/m3_routes_test.dart`: add a route test after "the consolidated view is reachable"

**Interfaces:**
- Consumes: everything from Tasks 3–8
- Produces:
  - `class DefenceManuscriptPane extends ConsumerWidget { const DefenceManuscriptPane({super.key, required Defence defence, bool canHighlight = false, String? highlightClosedReason, void Function(DrawnHighlight)? onHighlightDrawn, ManuscriptController? controller}); }` (key `manuscriptPane`)
  - `Future<void> openChapterFile(BuildContext context, WidgetRef ref, ChapterVersion v)`
  - `class DefenceManuscriptScreen extends ConsumerStatefulWidget { const DefenceManuscriptScreen({super.key, required String defenceId}); }` (key `defenceManuscript`)
  - route `/defence/room/:defenceId/manuscript`
  - room keys:
    - `tabRoom`, `tabHighlights`
    - `roomSideColumn` (wide), `roomSheet` (phone)
    - `goToManuscript` (leader)
    - `confirmDeleteHighlight`

Layout ruling (spec §7.1):
- Expanded width (≥ 1200): manuscript left, side column right.
- Phone (< 720): the manuscript fills the screen, and a draggable sheet holds, in order, the tabs panel, then the session controls, then the records.
- Medium (720–1199): the existing stacked room, with the manuscript as a tall panel below it. The existing room tests run at medium width and keep passing unchanged.

Task 10 records this in the spec.

- [ ] **Step 1: Write the failing room test**

Create `test/features/defence/defence_room_manuscript_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/defence/defence_room_screen.dart';
import 'package:ethesishub/features/defence/manuscript/defence_manuscript_screen.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class FakeRasterizer implements ManuscriptRasterizer {
  FakeRasterizer(this.image);
  final ui.Image image;
  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async =>
      [const Size(210, 297), const Size(210, 297)];
  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) async => image.clone();
}

Future<FakeFirebaseFirestore> seed({
  String status = 'inProgress',
  bool released = false,
  List<Map<String, dynamic>> highlights = const [],
  Map<String, Map<String, dynamic>> composing = const {},
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'status': 'titleApproved',
    'panelistUids': ['p1', 'p2'],
    'workingTitle': 'Mangrove Carbon Stocks',
  });
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'preOral',
    'scheduledAt':
        Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
    'venue': 'AVR',
    'panelUids': ['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    if (released) 'consolidatedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
  });
  for (final (uid, name, role) in [
    ('a1', 'Dr. Adviser', 'faculty'),
    ('p1', 'Dr. Panel', 'faculty'),
    ('l1', 'Leader', 'student'),
  ]) {
    await db.collection('users').doc(uid).set({
      'fullName': name,
      'email': '$uid@isufst.edu.ph',
      'role': role,
      'active': true,
    });
  }
  final docs = db.collection('theses/t1/documents');
  await docs
      .doc('chapterI')
      .set({'type': 'chapterI', 'currentVersion': 1, 'status': 'approved'});
  await docs.doc('chapterI').collection('versions').doc('1').set({
    'version': 1,
    'storagePath': 'theses/t1/chapterI/a.pdf',
    'fileUrl': '',
    'uploadedBy': 'l1',
    'mimeType': 'application/pdf',
    'sizeBytes': 4,
  });
  await docs
      .doc('chapterII')
      .set({'type': 'chapterII', 'currentVersion': 1, 'status': 'revise'});
  for (var i = 0; i < highlights.length; i++) {
    await db.collection('defenses/d1/annotations').doc('h$i').set({
      'authorName': 'Someone',
      'authorPosition': 'Panel Member',
      'chapter': 'chapterI',
      'version': 1,
      'page': 0,
      'rect': {'x': 0.1, 'y': 0.1, 'w': 0.5, 'h': 0.05},
      'body': 'Highlight $i',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 26, 9, i)),
      ...highlights[i],
    });
  }
  for (final e in composing.entries) {
    await db.doc('defenses/d1/composing/${e.key}').set(e.value);
  }
  return db;
}

Future<void> pumpScreen(
  WidgetTester tester,
  FakeFirebaseFirestore db,
  String uid,
  Widget screen, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final image =
      (await tester.runAsync(() => createTestImage(width: 210, height: 297)))!;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
      chapterFileLoaderProvider.overrideWithValue((path) async => Uint8List(4)),
      manuscriptRasterizerProvider.overrideWithValue(FakeRasterizer(image)),
    ],
    child: MaterialApp(home: Scaffold(body: screen)),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

const room = DefenceRoomScreen(defenceId: 'd1');

void main() {
  testWidgets('a wide room puts the manuscript beside the side column',
      (tester) async {
    await pumpScreen(tester, await seed(), 'p1', room);
    expect(find.byKey(const Key('manuscriptPane')), findsOneWidget);
    expect(find.byKey(const Key('roomSideColumn')), findsOneWidget);
    expect(find.byKey(const Key('pageTile-chapterI-1-0')), findsOneWidget);
    expect(find.text('Chapter II is not approved yet.'), findsOneWidget);
  });

  testWidgets('before the defence opens, highlighting is closed',
      (tester) async {
    await pumpScreen(tester, await seed(status: 'scheduled'), 'p1', room);
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.text('Highlighting opens when the defence starts.'),
        findsOneWidget);
  });

  testWidgets('after it closes, the tool is gone without a reason',
      (tester) async {
    await pumpScreen(tester, await seed(status: 'completed'), 'p1', room);
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.byKey(const Key('highlightClosed')), findsNothing);
  });

  testWidgets('a panel member draws a highlight and writes its comment',
      (tester) async {
    final db = await seed();
    await pumpScreen(tester, db, 'p1', room);

    await tester.tap(find.byKey(const Key('highlightTool')));
    await tester.pump();
    final surface = find.byKey(const Key('drawSurface-chapterI-0'));
    await tester.dragFrom(
        tester.getTopLeft(surface) + const Offset(40, 60),
        const Offset(220, 30));
    await settle(tester);

    await tester.enterText(
        find.byKey(const Key('highlightBody')), 'Cite the 2024 data.');
    await tester.pump();
    expect((await db.doc('defenses/d1/composing/p1').get()).data()!['target'],
        'manuscript');
    await tester.tap(find.byKey(const Key('saveHighlight')));
    await settle(tester);

    final saved = (await db.collection('defenses/d1/annotations').get()).docs;
    expect(saved, hasLength(1));
    expect(saved.single.data()['authorUid'], 'p1');
    expect(saved.single.data()['authorPosition'], 'Panel Member');
    expect(saved.single.data()['chapter'], 'chapterI');
    expect(saved.single.data()['version'], 1);
    expect(saved.single.data()['page'], 0);
    expect(find.text('Highlights (1)'), findsOneWidget);
    expect((await db.doc('defenses/d1/composing/p1').get()).exists, isFalse);
  });

  testWidgets('you delete your own highlight after confirming',
      (tester) async {
    final db = await seed(highlights: [
      {'authorUid': 'p1'},
      {'authorUid': 'a1'},
    ]);
    await pumpScreen(tester, db, 'p1', room);
    await tester.ensureVisible(find.byKey(const Key('tabHighlights')));
    await tester.tap(find.byKey(const Key('tabHighlights')));
    await settle(tester);

    expect(find.byKey(const Key('deleteHighlight-h1')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('deleteHighlight-h0')));
    await tester.tap(find.byKey(const Key('deleteHighlight-h0')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirmDeleteHighlight')));
    await settle(tester);
    expect((await db.doc('defenses/d1/annotations/h0').get()).exists, isFalse);
    expect((await db.doc('defenses/d1/annotations/h1').get()).exists, isTrue);
  });

  testWidgets('typing in the room box shows up for others, and clears',
      (tester) async {
    final db = await seed(composing: {
      'a1': {
        'name': 'Dr. Adviser',
        'position': 'Adviser',
        'target': 'room',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      },
    });
    await pumpScreen(tester, db, 'p1', room);
    expect(find.text('Dr. Adviser is typing…'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('commentBody')));
    await tester.enterText(find.byKey(const Key('commentBody')), 'Why?');
    await tester.pump();
    expect((await db.doc('defenses/d1/composing/p1').get()).data()!['target'],
        'room');
    await tester.enterText(find.byKey(const Key('commentBody')), '');
    await tester.pump();
    expect((await db.doc('defenses/d1/composing/p1').get()).exists, isFalse);
  });

  testWidgets('on a phone the tabs sit in a sheet over the manuscript',
      (tester) async {
    await pumpScreen(tester, await seed(), 'p1', room,
        size: const Size(400, 860));
    expect(find.byKey(const Key('roomSheet')), findsOneWidget);
    expect(find.byKey(const Key('manuscriptPane')), findsOneWidget);
    expect(find.byKey(const Key('tabHighlights')), findsOneWidget);
  });

  testWidgets('the leader has no View manuscript before release',
      (tester) async {
    await pumpScreen(tester, await seed(status: 'completed'), 'l1', room);
    expect(find.byKey(const Key('goToManuscript')), findsNothing);
  });

  testWidgets('the leader gets View manuscript once released',
      (tester) async {
    await pumpScreen(
        tester, await seed(status: 'completed', released: true), 'l1', room);
    expect(find.byKey(const Key('goToManuscript')), findsOneWidget);
  });

  testWidgets('the leader sees nothing before release', (tester) async {
    await pumpScreen(tester, await seed(status: 'completed'), 'l1',
        const DefenceManuscriptScreen(defenceId: 'd1'));
    expect(find.text('Available once your adviser releases the comments.'),
        findsOneWidget);
    expect(find.byKey(const Key('manuscriptPane')), findsNothing);
  });

  testWidgets('after release the leader reads pages and highlights only',
      (tester) async {
    await pumpScreen(
        tester,
        await seed(
            status: 'completed',
            released: true,
            highlights: [
              {'authorUid': 'p1'},
            ]),
        'l1',
        const DefenceManuscriptScreen(defenceId: 'd1'));
    expect(find.byKey(const Key('manuscriptPane')), findsOneWidget);
    expect(find.byKey(const Key('highlightBox-h0')), findsOneWidget);
    expect(find.text('Highlight 0'), findsOneWidget);
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.byKey(const Key('deleteHighlight-h0')), findsNothing);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/defence/defence_room_manuscript_test.dart`
Expected: FAIL to compile: `defence_manuscript_screen.dart` not found.

- [ ] **Step 3: Write the pane**

Create `lib/features/defence/manuscript/manuscript_pane.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// Opens a chapter file the manuscript cannot draw (an old Word upload) in
/// the device's own viewer, through a fresh signed URL.
Future<void> openChapterFile(
    BuildContext context, WidgetRef ref, ChapterVersion v) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final url = await ref.read(storageServiceProvider).signedUrl(v.storagePath);
    final uri = Uri.tryParse(url);
    final opened = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger?.showSnackBar(
          const SnackBar(content: Text('Could not open that file.')));
    }
  } on StorageFailure catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// The defence manuscript, framed and bound to one defence: its chapters,
/// its highlights and their colours.
class DefenceManuscriptPane extends ConsumerWidget {
  const DefenceManuscriptPane({
    super.key = const Key('manuscriptPane'),
    required this.defence,
    this.canHighlight = false,
    this.highlightClosedReason,
    this.onHighlightDrawn,
    this.controller,
  });

  final Defence defence;
  final bool canHighlight;
  final String? highlightClosedReason;
  final void Function(DrawnHighlight)? onHighlightDrawn;
  final ManuscriptController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    final partsAsync = ref.watch(manuscriptPartsProvider(
        (thesisId: defence.thesisId, type: defence.type)));
    final annotations =
        ref.watch(defenceAnnotationsProvider(defence.id)).valueOrNull ??
            const <DefenceAnnotation>[];
    final range = defence.type == DefenceType.preOral ? 'I–III' : 'I–V';

    final body = partsAsync.when(
      loading: () => const LoadingState(label: 'Loading the manuscript…'),
      error: (e, _) =>
          ErrorState(error: e, message: 'Could not load the chapters.'),
      data: (parts) => ManuscriptView(
        parts: parts,
        annotations: annotations,
        colours: highlightColours(defence: defence, annotations: annotations),
        numbers: highlightNumbers(annotations),
        canHighlight: canHighlight,
        highlightClosedReason: highlightClosedReason,
        onHighlightDrawn: onHighlightDrawn,
        onOpenFile: (v) => openChapterFile(context, ref, v),
        controller: controller,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        border: Border.all(color: p.rule),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.md, AppTokens.sm, AppTokens.md, AppTokens.sm),
              child: Row(
                children: [
                  Icon(Icons.menu_book_outlined, size: 18, color: p.muted),
                  const SizedBox(width: AppTokens.sm),
                  Text('Manuscript', style: text.titleSmall),
                  const SizedBox(width: AppTokens.sm),
                  Expanded(
                    child: Text('Chapters $range · approved versions',
                        style: text.bodySmall,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Write the read-only screen**

Create `lib/features/defence/manuscript/defence_manuscript_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/highlights_panel.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_pane.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// The manuscript and its highlights, read-only: how the group reads what
/// the panel marked, once the adviser has released the comments.
class DefenceManuscriptScreen extends ConsumerStatefulWidget {
  const DefenceManuscriptScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<DefenceManuscriptScreen> createState() =>
      _DefenceManuscriptScreenState();
}

class _DefenceManuscriptScreenState
    extends ConsumerState<DefenceManuscriptScreen> {
  final _controller = ManuscriptController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('defenceManuscript'),
        child: PageShell(children: children),
      );

  @override
  Widget build(BuildContext context) {
    final defenceAsync = ref.watch(defenceProvider(widget.defenceId));
    final uid = ref.watch(signedInUidProvider);

    if (defenceAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading defence…')]);
    }
    if (defenceAsync.hasError) {
      return _framed([
        ErrorState(
            error: defenceAsync.error,
            message: 'Could not load this defence.'),
      ]);
    }
    final defence = defenceAsync.valueOrNull;
    if (defence == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defence not found',
          message: 'This defence no longer exists.',
        ),
      ]);
    }

    // Decided from the defence alone, before any highlight is read: the
    // rules refuse the group until release, and nothing here may try.
    if (uid == defence.leaderUid && !defence.isReleased) {
      return _framed(const [
        EmptyState(
          icon: Icons.lock_clock_outlined,
          title: 'Not released yet',
          message: 'Available once your adviser releases the comments.',
        ),
      ]);
    }

    final annotationsAsync =
        ref.watch(defenceAnnotationsProvider(widget.defenceId));
    final annotations =
        annotationsAsync.valueOrNull ?? const <DefenceAnnotation>[];
    final parts = ref
        .watch(manuscriptPartsProvider(
            (thesisId: defence.thesisId, type: defence.type)))
        .valueOrNull;

    final list = annotationsAsync.hasError
        ? ErrorState(
            error: annotationsAsync.error,
            message: 'Could not load the highlights.')
        : SingleChildScrollView(
            child: HighlightsList(
              annotations: annotations,
              parts: parts,
              colours: highlightColours(
                  defence: defence, annotations: annotations),
              numbers: highlightNumbers(annotations),
              onSelect: _controller.reveal,
            ),
          );

    final pane =
        DefenceManuscriptPane(defence: defence, controller: _controller);

    return KeyedSubtree(
      key: const Key('defenceManuscript'),
      child: PageShell(
        scrollable: false,
        maxWidth: AppTokens.measureWide,
        kicker: defence.label,
        title: 'Manuscript',
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: pane),
                        const SizedBox(width: AppTokens.lg),
                        SizedBox(width: 360, child: list),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: pane),
                        const SizedBox(height: AppTokens.md),
                        Expanded(flex: 2, child: list),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Wire the room**

In `lib/features/defence/defence_room_screen.dart`:

(a) Add imports:

```dart
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/features/defence/manuscript/defence_typing.dart';
import 'package:ethesishub/features/defence/manuscript/highlights_panel.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_pane.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';
```

(b) Above `class DefenceRoomScreen`, add:

```dart
enum _RoomTab { room, highlights }
```

(c) Replace the state fields and `dispose` (lines 42–52) with:

```dart
  final _bodyController = TextEditingController();
  final _commentFocus = FocusNode();
  final _manuscript = ManuscriptController();
  DefenceTyping? _typing;
  _RoomTab _tab = _RoomTab.room;
  bool _posting = false;
  bool _statusBusy = false;
  String? _commentError;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _bodyController.addListener(_onCommentChanged);
    _commentFocus.addListener(_onCommentChanged);
  }

  /// The room comment box's half of the typing indicator: a marker while it
  /// has focus and text, none otherwise.
  void _onCommentChanged() {
    _typing?.typing(ComposingTarget.room,
        active: _commentFocus.hasFocus &&
            _bodyController.text.trim().isNotEmpty);
  }

  @override
  void dispose() {
    _typing?.dispose();
    _bodyController.removeListener(_onCommentChanged);
    _commentFocus.removeListener(_onCommentChanged);
    _bodyController.dispose();
    _commentFocus.dispose();
    _manuscript.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _composeHighlight(
    DrawnHighlight drawn, {
    required String uid,
    required String authorName,
    required String authorPosition,
  }) async {
    final body = await showHighlightComposer(
      context,
      onTyping: (on) =>
          _typing?.typing(ComposingTarget.manuscript, active: on),
    );
    _typing?.typing(ComposingTarget.manuscript, active: false);
    if (body == null || !mounted) return;
    try {
      await ref.read(defenceRepositoryProvider).addAnnotation(
            defenceId: widget.defenceId,
            authorUid: uid,
            authorName: authorName,
            authorPosition: authorPosition,
            chapter: drawn.chapter,
            version: drawn.version,
            page: drawn.page,
            rect: drawn.rect,
            body: body,
          );
    } on ArgumentError catch (e) {
      if (mounted) _say(e.message.toString());
    } on StateError catch (e) {
      if (mounted) _say(e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        _say(e.code == 'permission-denied'
            ? 'You do not have permission to highlight here '
                '[permission-denied].'
            : 'Could not save the highlight. Please try again.');
      }
    }
  }

  Future<void> _deleteHighlight(DefenceAnnotation a, String uid) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this highlight?'),
        content: Text('"${a.body}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('confirmDeleteHighlight'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await ref.read(defenceRepositoryProvider).deleteAnnotation(
          defenceId: widget.defenceId, annotationId: a.id, uid: uid);
    } on StateError catch (e) {
      if (mounted) _say(e.message);
    } on FirebaseException catch (_) {
      if (mounted) _say('Could not remove the highlight. Please try again.');
    }
  }
```

(d) In the leader branch (currently lines 395–404), replace the `Align(... FilledButton.icon(key: const Key('goToConsolidated') ...))` with:

```dart
              Wrap(
                spacing: AppTokens.sm,
                runSpacing: AppTokens.sm,
                children: [
                  FilledButton.icon(
                    key: const Key('goToConsolidated'),
                    onPressed: () => context
                        .go('/defence/room/${widget.defenceId}/consolidated'),
                    icon: const Icon(Icons.summarize_outlined, size: 18),
                    label: const Text('View consolidated comments'),
                  ),
                  // The panel's highlights reach the group with the
                  // comments, on the adviser's release (spec §7.2).
                  if (defence.isReleased)
                    OutlinedButton.icon(
                      key: const Key('goToManuscript'),
                      onPressed: () => context
                          .go('/defence/room/${widget.defenceId}/manuscript'),
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('View manuscript'),
                    ),
                ],
              ),
```

(e) After `final isAdviser = …;` (line 465), add:

```dart
    final showManuscript = defence.status != DefenceStatus.cancelled;
    final canHighlight = defence.status == DefenceStatus.inProgress &&
        uid != null &&
        authorPosition != null;
    if (canComment && uid != null && authorPosition != null) {
      _typing ??= DefenceTyping(
        repo: ref.read(defenceRepositoryProvider),
        defenceId: widget.defenceId,
        uid: uid,
        name: me?.fullName ?? '',
        position: authorPosition,
      );
    }
    final highlightCount =
        ref.watch(defenceAnnotationsProvider(widget.defenceId)).valueOrNull
                ?.length ??
            0;
    final composing =
        ref.watch(defenceComposingProvider(widget.defenceId)).valueOrNull ??
            const <DefenceComposing>[];
```

Add `import 'package:ethesishub/providers/defence_providers.dart';` if it is not already imported; it is, at line 17.

(f) Turn `log` into the tabs panel:
- Rename `final log = Panel(` to `final roomLog = Column(` and keep only the panel's `child:` column's `crossAxisAlignment` and `children`. So `roomLog` is the `Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ …comment rows…, Padding(…composer…) ])` that used to be `log`'s child.
- In that composer `Padding`, give the `TextField` `focusNode: _commentFocus,`.
- Immediately before the composer `Padding`, insert:

```dart
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.md, AppTokens.sm, AppTokens.md, 0),
            child: TypingLine(
              markers: composing,
              target: ComposingTarget.room,
              myUid: uid,
            ),
          ),
```

Then, after `roomLog`, add:

```dart
    final live = defence.status == DefenceStatus.inProgress
        ? const ToneBadge(
            label: 'Live',
            tone: Tone.endorsed,
            icon: Icons.sensors_rounded,
            dense: true,
          )
        : null;
    final onHighlights = showManuscript && _tab == _RoomTab.highlights;
    final tabsPanel = Panel(
      title: onHighlights ? 'Highlights' : 'Session log',
      subtitle: onHighlights
          ? 'Boxes drawn on the manuscript, in page order'
          : defence.status == DefenceStatus.inProgress
              ? 'Live. Remarks appear as they are posted'
              : 'Remarks made during the defence',
      icon: onHighlights ? Icons.highlight_alt : Icons.forum_outlined,
      flush: true,
      trailing: live,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showManuscript)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.md, AppTokens.sm, AppTokens.md, AppTokens.sm),
              child: SegmentedButton<_RoomTab>(
                showSelectedIcon: false,
                segments: [
                  const ButtonSegment(
                    value: _RoomTab.room,
                    label: Text('Room comments', key: Key('tabRoom')),
                  ),
                  ButtonSegment(
                    value: _RoomTab.highlights,
                    label: Text('Highlights ($highlightCount)',
                        key: const Key('tabHighlights')),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
            ),
          if (onHighlights)
            HighlightsTab(
              defence: defence,
              myUid: uid,
              onSelect: _manuscript.reveal,
              onDelete: uid == null ? null : (a) => _deleteHighlight(a, uid),
            )
          else
            roomLog,
        ],
      ),
    );

    final pane = DefenceManuscriptPane(
      defence: defence,
      controller: _manuscript,
      canHighlight: canHighlight,
      highlightClosedReason: defence.status == DefenceStatus.scheduled
          ? 'Highlighting opens when the defence starts.'
          : null,
      // Spelled out rather than `canHighlight ? …`: the null checks here are
      // what promote `uid` and `authorPosition` inside the closure.
      onHighlightDrawn: defence.status == DefenceStatus.inProgress &&
              uid != null &&
              authorPosition != null
          ? (d) => _composeHighlight(d,
              uid: uid,
              authorName: me?.fullName ?? '',
              authorPosition: authorPosition)
          : null,
    );
```

(g) Replace the final `return KeyedSubtree(...)` (lines 729–757) with:

```dart
    final redefenceLink = [
      if (defence.isRedefence) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('redefenceOfLink'),
            onPressed: () =>
                context.push('/defence/room/${defence.redefenceOf}'),
            icon: const Icon(Icons.history, size: 18),
            label: Text('Re-defence of an earlier '
                '${defence.type.label.toLowerCase()}. Open the original'),
          ),
        ),
        const Gap.sm(),
      ],
    ];

    final stacked = SplitColumns(
      secondaryFirstWhenStacked: true,
      primary: [tabsPanel],
      secondary: [session, after],
    );

    if (!showManuscript) {
      return KeyedSubtree(
        key: const Key('defenceRoom'),
        child: PageShell(
          maxWidth: AppTokens.measureWide,
          kicker: defence.label,
          title: thesisTitle ?? defence.label,
          children: [...redefenceLink, stacked],
        ),
      );
    }

    switch (Breakpoint.of(context)) {
      case Breakpoint.expanded:
        // Spec §7.1 Option A: the manuscript left, the room on the right.
        return KeyedSubtree(
          key: const Key('defenceRoom'),
          child: PageShell(
            scrollable: false,
            maxWidth: AppTokens.measureWide,
            kicker: defence.label,
            title: thesisTitle ?? defence.label,
            children: [
              ...redefenceLink,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pane),
                    const SizedBox(width: AppTokens.lg),
                    SizedBox(
                      width: 420,
                      child: ListView(
                        key: const Key('roomSideColumn'),
                        children: [
                          session,
                          const Gap.lg(),
                          tabsPanel,
                          const Gap.lg(),
                          after,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case Breakpoint.compact:
        // A phone: the pages fill the screen, the room slides up over them.
        return KeyedSubtree(
          key: const Key('defenceRoom'),
          child: PageShell(
            scrollable: false,
            kicker: defence.label,
            title: thesisTitle ?? defence.label,
            children: [
              ...redefenceLink,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: box.maxHeight * 0.12,
                        child: pane,
                      ),
                      DraggableScrollableSheet(
                        key: const Key('roomSheet'),
                        initialChildSize: 0.35,
                        minChildSize: 0.12,
                        maxChildSize: 0.95,
                        builder: (context, scroll) => Material(
                          color: p.canvas,
                          elevation: 8,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                          child: ListView(
                            controller: scroll,
                            padding: const EdgeInsets.all(AppTokens.sm),
                            children: [
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(
                                      bottom: AppTokens.sm),
                                  decoration: BoxDecoration(
                                    color: p.rule,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              tabsPanel,
                              const Gap.md(),
                              session,
                              const Gap.md(),
                              after,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case Breakpoint.medium:
        return KeyedSubtree(
          key: const Key('defenceRoom'),
          child: PageShell(
            maxWidth: AppTokens.measureWide,
            kicker: defence.label,
            title: thesisTitle ?? defence.label,
            children: [
              ...redefenceLink,
              stacked,
              const Gap.lg(),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.8)
                    .clamp(480.0, 1100.0),
                child: pane,
              ),
            ],
          ),
        );
    }
```

`Breakpoint` comes from `core/design/layout.dart`, which is already imported. `p` is the existing `Palette.of(context)` local.

(h) Where `_postComment` clears the box after a successful post (`if (mounted) _bodyController.clear();`), add `_typing?.stop();` on the next line.

- [ ] **Step 6: Route and bar title**

In `lib/core/routing/app_router.dart`, add the import:

```dart
import 'package:ethesishub/features/defence/manuscript/defence_manuscript_screen.dart';
```

After the `/defence/room/:defenceId/consolidated` `GoRoute`, add:

```dart
      // Three segments like 'consolidated', so ':defenceId' at position 2
      // can never swallow it.
      GoRoute(
        path: '/defence/room/:defenceId/manuscript',
        builder: (context, state) => DefenceManuscriptScreen(
            defenceId: state.pathParameters['defenceId']!),
      ),
```

In `lib/core/widgets/app_shell_host.dart`, replace:

```dart
  if (location.startsWith('/defence/room/')) {
    return location.endsWith('/consolidated')
        ? 'Consolidated comments'
        : 'Defence room';
  }
```

with:

```dart
  if (location.startsWith('/defence/room/')) {
    if (location.endsWith('/consolidated')) return 'Consolidated comments';
    if (location.endsWith('/manuscript')) return 'Manuscript';
    return 'Defence room';
  }
```

In `test/core/routing/m3_routes_test.dart`, after the test `'the consolidated view is reachable'`, add:

```dart
  testWidgets('the manuscript view is reachable', (tester) async {
    final c = await setUpFixture(tester, role: 'faculty', uid: 'a1');

    c.read(goRouterProvider).go('/defence/room/df1/manuscript');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceManuscript')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('shellTitle'))).data,
        'Manuscript');
  });
```

- [ ] **Step 7: Run the new and existing tests**

Run: `flutter test test/features/defence/ test/core/routing/m3_routes_test.dart`
Expected: PASS.

If an existing `defence_room_screen_test.dart` test fails because a tap lands off-screen, add `await tester.ensureVisible(find.byKey(...));` before that tap. The room log now has the tab strip above it, and the manuscript sits below at medium width. Assertions must not change.

- [ ] **Step 8: Run the whole suite**

Run: `flutter test`
Expected: PASS (1396 existing tests plus the new ones).

- [ ] **Step 9: Commit**

```bash
git add lib/features/defence/manuscript/manuscript_pane.dart lib/features/defence/manuscript/defence_manuscript_screen.dart lib/features/defence/defence_room_screen.dart lib/core/routing/app_router.dart lib/core/widgets/app_shell_host.dart test/features/defence/defence_room_manuscript_test.dart test/core/routing/m3_routes_test.dart
git commit -m "feat(defence): the manuscript in the defence room, with highlights and typing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Also `git add test/features/defence/defence_room_screen_test.dart`, if Step 7 needed `ensureVisible` there.

---

### Task 10: PDF-only chapter uploads, and the spec amendments

**Files:**
- Modify: `lib/features/titles/file_upload.dart:63-65`
- Modify: `lib/features/documents/chapter_detail_screen.dart:269-285` (`_uploadControl`)
- Modify test: `test/features/documents/upload_version_test.dart`: add two tests
- Modify: `docs/superpowers/specs/2026-09-26-defence-manuscript-and-annotations-design.md` (§5 Zoom, §6 Adding and numbering, §7.1 Phone)

**Interfaces:**
- Consumes: `kChapterTypes`, `validateDocument`, `ChapterDetailScreen(pickDocument:)`
- Produces: `kChapterTypes == {'pdf'}`; key `chapterPdfHint`

- [ ] **Step 1: Write the failing tests**

In `test/features/documents/upload_version_test.dart`, inside `main()`, add:

```dart
  testWidgets('chapters are PDF only: a Word file is refused with a reason',
      (tester) async {
    final db = await seed();
    final storage = _FakeStorage();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        storageServiceProvider.overrideWithValue(storage),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'l1', email: 'l@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ChapterDetailScreen(
            thesisId: 't1',
            chapter: ChapterId.chapterI,
            pickDocument: ({required Set<String> allowed}) async {
              expect(allowed, {'pdf'});
              return PickedDocument(
                name: 'chapter1.docx',
                bytes: Uint8List.fromList([0x50, 0x4B, 3, 4]),
                extension: 'docx',
                contentType: 'application/vnd.openxmlformats-'
                    'officedocument.wordprocessingml.document',
              );
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(find.text('Choose a PDF file.'), findsOneWidget);
    expect(
        (await db.collection('theses/t1/documents').get()).docs, isEmpty);
  });

  testWidgets('the upload area says to save as PDF', (tester) async {
    final db = await seed();
    await tester.pumpWidget(_wrap(db, _FakeStorage()));
    await tester.pumpAndSettle();
    expect(find.text('Upload chapters as PDF. From Word: File → Save As → PDF.'),
        findsOneWidget);
  });
```

`_wrap`, `seed` and `_FakeStorage` already exist in this file. Adjust the `_wrap` call to its actual signature, as used by the file's first test (`_wrap(db, storage)`). Add any missing imports (`dart:typed_data`, `file_upload.dart` for `PickedDocument`) at the top.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/documents/upload_version_test.dart`
Expected: FAIL.
- The first new test fails `expect(allowed, {'pdf'})`, because `allowed` is still `{pdf, doc, docx}`.
- The second fails to find the hint text.

- [ ] **Step 3: Make chapters PDF-only and add the hint**

In `lib/features/titles/file_upload.dart`, replace:

```dart
/// A chapter carries figures and tables, so the cap is above M1b's 10 MB
/// justification limit and below the bucket's 50 MB ceiling.
const kChapterTypes = {'pdf', 'doc', 'docx'};
```

with:

```dart
/// PDF only (spec 2026-09-26): the defence room draws each approved chapter
/// as pages, and a Word file cannot be drawn in the app. A chapter carries
/// figures and tables, so the size cap is above M1b's 10 MB justification
/// limit and below the bucket's 50 MB ceiling.
const kChapterTypes = {'pdf'};
```

In `lib/features/documents/chapter_detail_screen.dart`, in `_uploadControl`, directly after the `FilledButton.icon(key: const Key('uploadVersion'), …)`, insert:

```dart
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Upload chapters as PDF. From Word: File → Save As → PDF.',
            key: const Key('chapterPdfHint'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
```

- [ ] **Step 4: Run the documents tests**

Run: `flutter test test/features/documents/`
Expected: PASS. If an existing test picks a `.doc`/`.docx` chapter and expects success, change its fixture to a PDF. The requirement changed; do not weaken the new test.

- [ ] **Step 5: Record the rulings in the spec**

In `docs/superpowers/specs/2026-09-26-defence-manuscript-and-annotations-design.md`:
- In §5, replace the **Zoom** bullet with:

```markdown
- **Zoom:** buttons, 100 / 150 / 200 / 300 %, scrolling sideways when the
  pages are wider than the view. No pinch: the page list is built lazily for
  memory's sake, and pinch-zoom needs the whole document built at once.
```

- In §6, replace the first sentence of **Adding** so that it reads:

```markdown
- **Adding** (only while the defence is in progress, for the adviser,
  panel, Coordinator and Dean): turn on the **Highlight** tool, drag a box
  over the page, then a small dialog asks for the comment. The tool turns
  itself off after each box, so a drag scrolls the pages again. Cancel
  discards the box.
```

- In §6 **Showing**, after "numbered tag;", add: "numbers follow the order highlights were made, so a number keeps meaning the same box;".
- In §7.1, replace the **Phone** bullet with:

```markdown
- **Phone:** the manuscript fills the screen; a sheet dragged up from the
  bottom holds the tabbed panel, then the session controls, then the
  records. Medium widths (tablets) keep the stacked room with the
  manuscript as a tall panel below it.
```

- [ ] **Step 6: Run everything**

Run: `flutter analyze` and then `flutter test`
Expected: analyze reports no new issues in the changed files; all tests PASS.

Run: `cd rules-test && npm test`
Expected: PASS.

Run: `deno test supabase/functions/document-url/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/features/titles/file_upload.dart lib/features/documents/chapter_detail_screen.dart test/features/documents/upload_version_test.dart docs/superpowers/specs/2026-09-26-defence-manuscript-and-annotations-design.md
git commit -m "feat(chapters): chapters upload as PDF only, so the defence can show them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## After the plan (for the user, not the executor)

These deploys belong to the user. Nothing in this plan runs them:
- `firebase deploy --only firestore:rules --project ethesishub-43a04`
- `supabase functions deploy document-url`
- Rebuild the APK.
