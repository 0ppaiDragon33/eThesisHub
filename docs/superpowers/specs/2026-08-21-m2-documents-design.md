# M2 — Documents and revisions

**Date:** 2026-08-21
**Status:** approved for planning
**Parent:** `2026-08-12-ethesishub-design.md` §9.2 (M2), §5.2, §4
**Depends on:** M1a (nomination), M1b (title defence)

Objective 4. Part of the minimum defensible build (skeleton + M1 + M2 + M3),
so it is not a candidate for being dropped under schedule pressure — only for
depth reduction.

## 1. What this milestone delivers

A group whose title has been approved uploads Chapters I–V. Each upload is a
version; nothing is ever overwritten. The adviser reads a version, leaves
feedback on it, and marks the chapter `revise` or `approved`. The group
uploads again. The dean and coordinator watch progress without reading the
work.

Stopping here still tells a complete story: registration, nomination,
approval, upload, feedback, revision — end to end.

## 2. Decisions taken

| # | Decision | Rationale |
|---|---|---|
| M2-1 | A version and a piece of feedback are **separate records** | One version has many reviewers. The manuscript's `revisions` shape bundles a file with one reviewer's remark, which duplicates the file across rows and leaves nothing identifying the authoritative copy. Creates one item of documentation debt (§11) |
| M2-2 | Status is written by **two disjoint actors**: the student reaches `submitted` by uploading; the adviser writes `revise` and `approved` | Enforceable as two separate rule arms. A student can never write `approved`; an adviser can never fabricate a submission |
| M2-3 | Chapters unlock at `titleApproved`; **all five approved does not advance the thesis** | M3 scheduling stays a deliberate act. No status fires without someone pressing something |
| M2-4 | Chapter documents are **created on first upload** with fixed ids `chapterI`…`chapterV` | The rules can hardcode the five valid ids. "Not started" is derived from absence, so no stored state can drift from reality |
| M2-5 | An `approved` chapter is **locked to the student**; only the adviser can reopen it to `revise` | Prevents a group swapping an approved chapter unseen, and keeps one person accountable for the state. Same reasoning as M1b's immutable candidate titles |
| M2-6 | Feedback is **append-only** | A record of what was said is only a record if it cannot be rewritten. §6.4 of the parent spec; matches M1b defence comments |
| M2-7 | The **panel does not read chapters in M2** | The panel meets the document at the pre-oral defence, which is M3. Widening access later is one line; narrowing it after people rely on it is not |
| M2-8 | The **dean reads chapter status but not contents or feedback** | §3.1 gives the dean college-wide progress visibility, not chapter review. The split falls on a collection boundary, so it needs no field-level filtering |
| M2-9 | Defence readiness is **computed, never stored** | See §5. A stored flag cannot be validated in the rules, so it could be forged |
| M2-10 | Coordinator administration is a **separate slice after M2** | No dependency on documents. Keeps each spec coherent and each week demonstrable |

## 3. Data model

```
theses/{thesisId}/
  documents/{chapterId}            chapterId ∈ chapterI…chapterV, and no others
    type            'chapterI' | … | 'chapterV'
    currentVersion  int, starts at 1
    status          'submitted' | 'revise' | 'approved'
    updatedAt

    versions/{versionNo}           the document id IS the version number
      storagePath, fileUrl, uploadedBy, uploadedAt, mimeType, sizeBytes

    feedback/{feedbackId}
      version, reviewerUid, reviewerName, reviewerRole, body, createdAt
```

**The version number is the document id.** "One document per version" becomes a
structural guarantee rather than a rule to enforce, and ordering is free — no
repeat of the candidate-titles defect, where a collection with no explicit
order came back sorted by random auto-generated id.

**A chapter that has never been uploaded has no document.** The screen renders
all five rows and derives "not started" from absence.

Storage reuses `StoragePaths.thesisDocument`, so a file lands at
`theses/{thesisId}/{chapterId}/{uuid}.{ext}` — unguessable, because the bucket
is public (§7.2, D7).

**Accepted types:** PDF, DOC, DOCX. **Cap: 15 MB per version** — above M1b's
10 MB justification cap, because a chapter carries figures and tables, and
below the bucket's 50 MB ceiling. The bucket's MIME allow-list must include
`application/msword` and the OpenXML wordprocessing type, or every upload is
refused with a 415 that no client-side check can predict.

## 4. Status transitions

```
(no document)  --student uploads-->  submitted
submitted      --adviser-->          revise | approved
revise         --student uploads-->  submitted     (currentVersion + 1)
approved       --adviser-->          revise        (reopen)
approved       --student-->          DENIED
```

**A group may upload again while still `submitted`**, before the adviser has
responded. That adds a version and leaves the status where it is. Refusing it
would mean a group who spotted their own error had to wait for feedback on a
draft both sides know is wrong. The adviser always reviews against
`currentVersion`, and every superseded version stays in the history.

## 5. Defence readiness

```
Chapters I, II, III approved   →  ready for PRE-ORAL
Chapters I … V     approved    →  ready for FINAL
```

Computed by the monitoring screen from the chapter documents themselves. It
lists theses at `titleApproved` — a query the dean and coordinator already
hold — and reads each thesis's chapter documents.

**Why not store a `proposalReady` flag.** It would have to be written by the
adviser's approval, and the rules cannot verify it. Validating it means
reading the three chapter documents inside the rule, and in a batch those
still evaluate against their **pre-batch** state — the very chapter being
approved would still read as unapproved. The rule would be either wrong or
unenforceable, and an adviser could set "ready for final defence" on a thesis
with nothing approved. Deriving it costs one subcollection read per thesis and
cannot be forged, because it is the source of truth.

If it proves slow against the real cohort, denormalising is a later
optimisation with a measurement behind it.

## 6. Permissions

`firestore.rules` is the only authorization boundary on this project — there
are no Cloud Functions on the Spark plan.

| Path | get / list | create | update | delete |
|---|---|---|---|---|
| `documents/{chapter}` | leader, adviser, coordinator, dean | leader; only at `titleApproved`; only the five ids; `status == 'submitted'`; `currentVersion == 1` | **leader arm:** only from `submitted`/`revise`, `currentVersion` + 1 exactly, `status == 'submitted'` · **adviser arm:** `status` ∈ `revise`/`approved` only, `currentVersion` untouched | never |
| `versions/{n}` | leader, adviser, coordinator | leader; id must equal the parent's `currentVersion` + 1 | never | never |
| `feedback/{id}` | leader, adviser, coordinator | adviser only; `reviewerUid` pinned to the caller; `version` must be an int in `1…currentVersion` | never | never |

Feedback is visible to the student immediately, unlike M1b's defence comments
which were hidden until the Dean decided. Different purpose: this feedback
exists in order to be acted on.

### 6.1 Batch evaluation — to be probed, not assumed

Uploading a version is one batch: create `versions/2`, update the parent's
`currentVersion` to 2. Batch writes are evaluated against the state **before**
the batch, so the rule guarding `versions/2` sees a parent still reading
`currentVersion: 1`.

The rule must therefore read *"this version equals the parent's current version
+ 1"*, never *"equals currentVersion"*.

M1b established this behaviour against the emulator rather than by reasoning,
with a two-sided test showing the batched form allowed and the same writes
issued sequentially denied. M2 does the same before relying on it.

### 6.2 A rules gap M2 forces open

An adviser currently **cannot list the theses they advise**: `allow list` on
`theses` is limited to coordinators, the dean, and a leader's own. That is why
the faculty dashboard's "My advisees" is a placeholder. It did not block M1,
because nominations reached faculty through their own inbox.

M2 breaks on it — an adviser has no way to find the chapters waiting for them.

```
allow list: if signedIn() && resource.data.adviserUid == request.auth.uid
```

Narrow: it returns only theses naming you as adviser. Panelists already have a
working route through `myThesisIdsProvider`.

## 7. Screens

| Screen | Who | What |
|---|---|---|
| Chapter list | leader, adviser, coordinator | Five rows: status, current version, last activity. Reached from the thesis status screen once the title is approved |
| Chapter detail | leader, adviser, coordinator | Version history newest-first, each a download link; feedback threaded under the version it addresses; upload control when the status permits |
| Adviser review | adviser | The detail screen plus the feedback box and the `revise`/`approved` actions |
| Defence readiness | dean, coordinator | Theses at `titleApproved`, chapter progress, and whether pre-oral or final ready |
| My advisees | adviser | Becomes real via §6.2; advised theses with a count of chapters awaiting review |

Reuses `PageShell`, `StatusChip` (three new labels), `ErrorState`,
`LoadingState`, `uploadDocument`, `StoragePaths.thesisDocument`, and
`classifyStorageError`.

Every not-ready, denied and empty state renders inside a `Scaffold` with an app
bar. A bare `PageShell` has no navigation, and a student who reached one had to
reload the app to escape it.

## 8. Error handling

Storage failures arrive already classified as `StorageFailure`.

The case needing care is a **partial upload**: the file lands in Supabase, then
the Firestore batch fails, leaving an orphaned object — unreferenced,
unguessable, harmless, but real. Upload first and batch second (as M1b does);
on batch failure, delete the uploaded object and report the original error.
Cleanup is best-effort and must never mask the real failure.

Every stream whose permission depends on the caller watches
`signedInUidProvider`. A plain `StreamProvider` is built once and kept for the
life of the container, so a listener refused under one account stays in
`AsyncError` until the page is reloaded.

## 9. Testing

- **Rules tests** in the emulator for every arm, each with a **control** proving
  the deny is not passing for an unrelated reason. Includes the §6.1 batch probe
  as a two-sided test.
- **Repository tests** for version increment, each status transition, and each
  denied transition.
- **Widget tests** for every screen, including the not-yet-unlocked and
  approved-locked states.
- **Every test falsified** by reverting the code under it and confirming it
  fails. `fake_cloud_firestore` returns documents in insertion order and does
  not enforce rules — an ordering or permission test that never sees wrong data
  proves nothing.

## 10. Out of scope

Inline or anchored comments on the text; DOCX preview in-app; per-member
accounts (`memberNames` are names, not users); automatic advance when all five
are approved; notifications on new feedback (M5).

## 11. Documentation debt

One new item for the parent spec §11:

> The data dictionary's `documents/revisions` shape becomes `documents/versions`
> plus `documents/feedback`. Reason: one version has many reviewers, and the
> bundled shape duplicated the file across rows with nothing marking the
> authoritative copy.
