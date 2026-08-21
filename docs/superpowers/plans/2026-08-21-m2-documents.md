# M2 Documents and Revisions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A group whose title is approved uploads Chapters I–V as versions; the adviser leaves feedback per version and marks each chapter `revise` or `approved`; the dean and coordinator watch progress without reading the work.

**Architecture:** Three nested collections under `theses/{thesisId}` — `documents/{chapterId}` holds status and version count, `versions/{versionNo}` holds each uploaded file, `feedback/{feedbackId}` holds each remark. The version number is the document id, so ordering is structural. Status is written by two disjoint rule arms: the student reaches `submitted` by uploading, the adviser writes `revise`/`approved`. Defence readiness is computed from chapter statuses, never stored.

**Tech Stack:** Flutter 3.44 / Dart 3.12 (Android + Web only — `dart:io` is forbidden in `lib/`), Riverpod 2.6.1 (2.x API only), Cloud Firestore, Supabase Storage, `file_picker`, `url_launcher`.

**Spec:** `docs/superpowers/specs/2026-08-21-m2-documents-design.md`

## Global Constraints

- **`firestore.rules` is the only authorization boundary.** Firebase Spark plan — no Cloud Functions, no server-side triggers, no admin-side validation.
- **`fake_cloud_firestore` does not enforce rules.** A rules violation passes every Dart test and fails for every real user. Every permission claim is tested in `rules-test/rules.test.js` against the emulator.
- **`fake_cloud_firestore` returns documents in insertion order.** An ordering test that only ever sees correctly-ordered data proves nothing. Seed against the intended order.
- **Every deny test needs a control** — the same write by a permitted caller, proving the deny is not passing for an unrelated reason.
- **`ctx.firestore()` may be called ONCE per `withSecurityRulesDisabled` context.** A second call throws, and `assertFails` swallows it, so the test passes for the wrong reason. Bind it to a variable.
- **Batch writes are evaluated against the PRE-batch state.** Probe this, never assume it.
- **Every test must be falsified** — revert the code under it and confirm it fails.
- **Riverpod 2.6.1 only.** No `@riverpod` codegen, no Notifier 3.x API.
- **No `dart:io` anywhere in `lib/`.** Web is a target; use `Uint8List` bytes.
- **Every stream whose permission depends on the caller must `ref.watch(signedInUidProvider)`.** A plain `StreamProvider` is built once for the life of the container; a listener refused under one account stays in `AsyncError` until the page reloads.
- **Every state a screen can render — loading, error, empty, denied — must sit inside a `Scaffold` with an `AppBar`.** A bare `PageShell` has no navigation and strands the user.
- **Accepted upload types:** PDF, DOC, DOCX. **Cap 15 MB per version.**
- **Chapter ids are exactly** `chapterI`, `chapterII`, `chapterIII`, `chapterIV`, `chapterV`.

---

### Task 1: Chapter models

**Files:**
- Create: `lib/data/models/chapter.dart`
- Test: `test/data/models/chapter_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces: `enum ChapterId { chapterI, chapterII, chapterIII, chapterIV, chapterV }` with `String get value`, `String get label`, `static ChapterId? fromString(String?)`, `static const proposalChapters`, `static const finalChapters`; `enum ChapterStatus { submitted, revise, approved }` with `String get value`, `static ChapterStatus fromString(String?)`; `class ThesisChapter { ChapterId id; int currentVersion; ChapterStatus status; DateTime? updatedAt; }` with `factory ThesisChapter.fromMap(String id, Map<String, dynamic>)`; `class ChapterVersion { int version; String storagePath; String fileUrl; String uploadedBy; DateTime? uploadedAt; String mimeType; int sizeBytes; }` with `fromMap`; `class ChapterFeedback { String id; int version; String reviewerUid; String reviewerName; String reviewerRole; String body; DateTime? createdAt; }` with `fromMap`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/chapter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';

void main() {
  test('there are exactly five chapters, in order', () {
    expect(ChapterId.values.map((c) => c.value), [
      'chapterI', 'chapterII', 'chapterIII', 'chapterIV', 'chapterV',
    ]);
  });

  test('the proposal gate is I-III and the final gate is all five', () {
    // Pre-oral covers the proposal; the final defence adds Results and
    // Conclusions. Two readiness signals from the same five documents.
    expect(ChapterId.proposalChapters,
        [ChapterId.chapterI, ChapterId.chapterII, ChapterId.chapterIII]);
    expect(ChapterId.finalChapters, ChapterId.values);
  });

  test('an unknown chapter id is null, not a silent default', () {
    // fromString must NOT fall back to chapterI: a typo would then write
    // Chapter III's file over Chapter I's record.
    expect(ChapterId.fromString('chapterVI'), isNull);
    expect(ChapterId.fromString(null), isNull);
    expect(ChapterId.fromString('chapterIII'), ChapterId.chapterIII);
  });

  test('a chapter parses its stored shape', () {
    final c = ThesisChapter.fromMap('chapterII', {
      'type': 'chapterII',
      'currentVersion': 3,
      'status': 'revise',
      'updatedAt': DateTime.utc(2026, 8, 21),
    });
    expect(c.id, ChapterId.chapterII);
    expect(c.currentVersion, 3);
    expect(c.status, ChapterStatus.revise);
    expect(c.updatedAt, DateTime.utc(2026, 8, 21));
  });

  test('an unknown status reads as submitted, never as approved', () {
    // The safe default is the one that grants nothing. Defaulting to
    // approved would let corrupt data unlock a defence.
    expect(ChapterStatus.fromString('nonsense'), ChapterStatus.submitted);
    expect(ChapterStatus.fromString(null), ChapterStatus.submitted);
  });

  test('a version and a piece of feedback parse their stored shapes', () {
    final v = ChapterVersion.fromMap({
      'version': 2,
      'storagePath': 'theses/t1/chapterI/uuid.pdf',
      'fileUrl': 'https://example.test/uuid.pdf',
      'uploadedBy': 'leader-uid',
      'uploadedAt': DateTime.utc(2026, 8, 21),
      'mimeType': 'application/pdf',
      'sizeBytes': 1024,
    });
    expect(v.version, 2);
    expect(v.sizeBytes, 1024);

    final f = ChapterFeedback.fromMap('fb1', {
      'version': 2,
      'reviewerUid': 'adviser-uid',
      'reviewerName': 'Dr. Armada',
      'reviewerRole': 'Adviser',
      'body': 'Tighten the problem statement.',
      'createdAt': DateTime.utc(2026, 8, 21),
    });
    expect(f.id, 'fb1');
    expect(f.version, 2);
    expect(f.body, 'Tighten the problem statement.');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/chapter_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'ethesishub/data/models/chapter.dart'`

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/models/chapter.dart

/// The five chapters, fixed. A group cannot invent a sixth, and the rules
/// hardcode these ids so nothing outside this list can be written.
enum ChapterId {
  chapterI,
  chapterII,
  chapterIII,
  chapterIV,
  chapterV;

  String get value => name;

  String get label => switch (this) {
        ChapterId.chapterI => 'Chapter I — Introduction',
        ChapterId.chapterII => 'Chapter II — Related Literature',
        ChapterId.chapterIII => 'Chapter III — Methodology',
        ChapterId.chapterIV => 'Chapter IV — Results and Discussion',
        ChapterId.chapterV => 'Chapter V — Conclusions',
      };

  /// Null rather than a default, deliberately. Falling back to chapterI
  /// would let a typo write one chapter's record over another's.
  static ChapterId? fromString(String? raw) {
    for (final c in ChapterId.values) {
      if (c.name == raw) return c;
    }
    return null;
  }

  /// Approved in full, the pre-oral defence may be scheduled.
  static const proposalChapters = [chapterI, chapterII, chapterIII];

  /// Approved in full, the final defence may be scheduled.
  static const finalChapters = ChapterId.values;
}

enum ChapterStatus {
  submitted,
  revise,
  approved;

  String get value => name;

  /// Defaults to `submitted` — the status that grants nothing. Defaulting
  /// to `approved` would let corrupt data unlock a defence.
  static ChapterStatus fromString(String? raw) {
    for (final s in ChapterStatus.values) {
      if (s.name == raw) return s;
    }
    return ChapterStatus.submitted;
  }
}

/// One chapter of one thesis: what state it is in and how many versions
/// have been uploaded. The files themselves live in `versions`.
class ThesisChapter {
  const ThesisChapter({
    required this.id,
    required this.currentVersion,
    required this.status,
    this.updatedAt,
  });

  final ChapterId id;
  final int currentVersion;
  final ChapterStatus status;
  final DateTime? updatedAt;

  factory ThesisChapter.fromMap(String id, Map<String, dynamic> map) {
    return ThesisChapter(
      id: ChapterId.fromString(id) ?? ChapterId.chapterI,
      currentVersion: (map['currentVersion'] as num?)?.toInt() ?? 1,
      status: ChapterStatus.fromString(map['status'] as String?),
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}

/// One uploaded file. Immutable: nothing is ever overwritten, so the
/// revision history is a record rather than a snapshot.
class ChapterVersion {
  const ChapterVersion({
    required this.version,
    required this.storagePath,
    required this.fileUrl,
    required this.uploadedBy,
    required this.mimeType,
    required this.sizeBytes,
    this.uploadedAt,
  });

  final int version;
  final String storagePath;
  final String fileUrl;
  final String uploadedBy;
  final String mimeType;
  final int sizeBytes;
  final DateTime? uploadedAt;

  factory ChapterVersion.fromMap(Map<String, dynamic> map) {
    return ChapterVersion(
      version: (map['version'] as num?)?.toInt() ?? 0,
      storagePath: map['storagePath'] as String? ?? '',
      fileUrl: map['fileUrl'] as String? ?? '',
      uploadedBy: map['uploadedBy'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: map['uploadedAt'] as DateTime?,
    );
  }
}

/// One remark on one version. Append-only: a record of what was said is
/// only a record if it cannot be rewritten afterwards.
class ChapterFeedback {
  const ChapterFeedback({
    required this.id,
    required this.version,
    required this.reviewerUid,
    required this.reviewerName,
    required this.reviewerRole,
    required this.body,
    this.createdAt,
  });

  final String id;
  final int version;
  final String reviewerUid;
  final String reviewerName;
  final String reviewerRole;
  final String body;
  final DateTime? createdAt;

  factory ChapterFeedback.fromMap(String id, Map<String, dynamic> map) {
    return ChapterFeedback(
      id: id,
      version: (map['version'] as num?)?.toInt() ?? 0,
      reviewerUid: map['reviewerUid'] as String? ?? '',
      reviewerName: map['reviewerName'] as String? ?? '',
      reviewerRole: map['reviewerRole'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/chapter_test.dart`
Expected: PASS, 6 tests

- [ ] **Step 5: Falsify**

Change `ChapterId.fromString` to `return ChapterId.chapterI;` instead of `null`. Run the test. Expected: FAIL on `expect(ChapterId.fromString('chapterVI'), isNull)`. Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/chapter.dart test/data/models/chapter_test.dart
git commit -m "feat: chapter, version and feedback models"
```

---

### Task 2: Security rules for documents, versions and feedback

**Files:**
- Modify: `firestore.rules` (inside `match /theses/{thesisId}`, after the `titleComposing` block)
- Modify: `rules-test/rules.test.js` (append a new section)

**Interfaces:**
- Consumes: existing helpers `signedIn()`, `verified()`, `isCoordinator()`, `isDean()`, `thesisData(thesisId)`, `isThesisLeader(thesisId)`
- Produces: rules helper `isAdviser(thesisId)`; the three collections' permissions relied on by Tasks 4–10

- [ ] **Step 1: Write the failing rules tests**

Append to `rules-test/rules.test.js`, before the final closing lines. Note `ctx.firestore()` is bound ONCE per context.

```javascript
// ---------- M2: documents, versions and feedback ----------

function docThesis(status = "titleApproved", extra = {}) {
  return {
    leaderUid: "leader-uid", adviserUid: "adviser-uid",
    panelistUids: ["pan-uid"], memberNames: [], workingTitle: "T",
    college: "CICT", program: "BSIT", semester: "First",
    academicYear: "2026-2027", status, ...extra,
  };
}

function asDocUser(uid, email) {
  return env.authenticatedContext(uid, { email, email_verified: true })
    .firestore();
}

async function seedChapters(db) {
  await setDoc(doc(db, "theses/m2"), docThesis());
  await setDoc(doc(db, "theses/m2/documents/chapterI"), {
    type: "chapterI", currentVersion: 1, status: "submitted",
    updatedAt: Timestamp.now(),
  });
  await setDoc(doc(db, "theses/m2/documents/chapterI/versions/1"), {
    version: 1, storagePath: "p", fileUrl: "u", uploadedBy: "leader-uid",
    uploadedAt: Timestamp.now(), mimeType: "application/pdf",
    sizeBytes: 100,
  });
}

test("M2: the leader, adviser, coordinator and dean read a chapter", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedChapters(db);
    await setDoc(doc(db, "users/coord-uid"),
      { role: "coordinator", active: true });
    await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
  });
  for (const uid of ["leader-uid", "adviser-uid", "coord-uid", "dean-uid"]) {
    await assertSucceeds(
      getDoc(doc(asDocUser(uid, `${uid}@isufst.edu.ph`),
        "theses/m2/documents/chapterI")));
  }
});

test("M2: a panelist may NOT read a chapter, its versions or its feedback",
  async () => {
    // The panel meets the document at the pre-oral defence, which is M3.
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const pan = asDocUser("pan-uid", "pan@isufst.edu.ph");
    await assertFails(getDoc(doc(pan, "theses/m2/documents/chapterI")));
    await assertFails(
      getDoc(doc(pan, "theses/m2/documents/chapterI/versions/1")));
    // Control: the adviser, same paths.
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
    await assertSucceeds(getDoc(doc(adv, "theses/m2/documents/chapterI")));
    await assertSucceeds(
      getDoc(doc(adv, "theses/m2/documents/chapterI/versions/1")));
  });

test("M2: the dean reads chapter STATUS but NOT its versions or feedback",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await seedChapters(db);
      await setDoc(doc(db, "users/dean-uid"), { role: "dean", active: true });
    });
    const dean = asDocUser("dean-uid", "dean@isufst.edu.ph");
    await assertSucceeds(getDoc(doc(dean, "theses/m2/documents/chapterI")));
    await assertFails(
      getDoc(doc(dean, "theses/m2/documents/chapterI/versions/1")));
  });

test("M2: chapters may NOT be created before the title is approved",
  async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      setDoc(doc(ctx.firestore(), "theses/m2b"),
        docThesis("titlePendingDefence")));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    await assertFails(setDoc(doc(leader, "theses/m2b/documents/chapterI"), {
      type: "chapterI", currentVersion: 1, status: "submitted",
      updatedAt: serverTimestamp(),
    }));
  });

test("M2: only the five chapter ids exist", async () => {
  await env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), "theses/m2c"), docThesis()));
  const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(setDoc(doc(leader, "theses/m2c/documents/chapterVI"), {
    type: "chapterVI", currentVersion: 1, status: "submitted",
    updatedAt: serverTimestamp(),
  }));
  // Control: a real chapter id, same payload shape.
  await assertSucceeds(setDoc(doc(leader, "theses/m2c/documents/chapterV"), {
    type: "chapterV", currentVersion: 1, status: "submitted",
    updatedAt: serverTimestamp(),
  }));
});

test("M2: a student may NOT write approved, and an adviser may NOT fake a submission",
  async () => {
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");

    // The student cannot approve their own chapter.
    await assertFails(updateDoc(doc(leader, "theses/m2/documents/chapterI"),
      { status: "approved", updatedAt: serverTimestamp() }));

    // The adviser cannot bump the version to fabricate a submission.
    await assertFails(updateDoc(doc(adv, "theses/m2/documents/chapterI"),
      { status: "submitted", currentVersion: 2,
        updatedAt: serverTimestamp() }));

    // Controls: each doing their own half.
    await assertSucceeds(updateDoc(doc(adv, "theses/m2/documents/chapterI"),
      { status: "revise", updatedAt: serverTimestamp() }));
  });

test("M2: an approved chapter is locked to the student and reopenable by the adviser",
  async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/m2d"), docThesis());
      await setDoc(doc(db, "theses/m2d/documents/chapterI"), {
        type: "chapterI", currentVersion: 1, status: "approved",
        updatedAt: Timestamp.now(),
      });
    });
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");

    await assertFails(updateDoc(doc(leader, "theses/m2d/documents/chapterI"),
      { currentVersion: 2, status: "submitted",
        updatedAt: serverTimestamp() }));
    // Control: the adviser reopens it, and then the student may upload.
    await assertSucceeds(updateDoc(doc(adv, "theses/m2d/documents/chapterI"),
      { status: "revise", updatedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(doc(leader, "theses/m2d/documents/chapterI"),
      { currentVersion: 2, status: "submitted",
        updatedAt: serverTimestamp() }));
  });

test("M2 batch evaluation: a version and its parent bump are judged PRE-batch",
  async () => {
    // Two-sided. The batched form must be ALLOWED and the identical writes
    // issued SEQUENTIALLY must be DENIED -- by then the parent has already
    // moved and the version number no longer matches. This is a probe of
    // Firestore's behaviour, not an assumption about it.
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");

    const batch = writeBatch(leader);
    batch.set(doc(leader, "theses/m2/documents/chapterI/versions/2"), {
      version: 2, storagePath: "p2", fileUrl: "u2",
      uploadedBy: "leader-uid", uploadedAt: serverTimestamp(),
      mimeType: "application/pdf", sizeBytes: 200,
    });
    batch.update(doc(leader, "theses/m2/documents/chapterI"),
      { currentVersion: 2, status: "submitted",
        updatedAt: serverTimestamp() });
    await assertSucceeds(batch.commit());

    // Sequentially: the parent is now at 2, so writing version 2 again is
    // no longer currentVersion + 1.
    await assertFails(
      setDoc(doc(leader, "theses/m2/documents/chapterI/versions/2"), {
        version: 2, storagePath: "p2", fileUrl: "u2",
        uploadedBy: "leader-uid", uploadedAt: serverTimestamp(),
        mimeType: "application/pdf", sizeBytes: 200,
      }));
  });

test("M2: a version is immutable once written", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
  const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
  await assertFails(
    updateDoc(doc(leader, "theses/m2/documents/chapterI/versions/1"),
      { fileUrl: "swapped" }));
  await assertFails(
    deleteDoc(doc(leader, "theses/m2/documents/chapterI/versions/1")));
});

test("M2: only the adviser writes feedback, in their own name, append-only",
  async () => {
    await env.withSecurityRulesDisabled((ctx) => seedChapters(ctx.firestore()));
    const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");

    // A student may not write feedback at all.
    await assertFails(
      setDoc(doc(leader, "theses/m2/documents/chapterI/feedback/f1"), {
        version: 1, reviewerUid: "leader-uid", reviewerName: "Me",
        reviewerRole: "Adviser", body: "Looks great",
        createdAt: serverTimestamp(),
      }));

    // The adviser may not file feedback under someone else's uid.
    await assertFails(
      setDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f2"), {
        version: 1, reviewerUid: "dean-uid", reviewerName: "Dean",
        reviewerRole: "Dean", body: "Not mine",
        createdAt: serverTimestamp(),
      }));

    // A version that does not exist yet cannot be commented on.
    await assertFails(
      setDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f3"), {
        version: 9, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "On a future version",
        createdAt: serverTimestamp(),
      }));

    // Control: the adviser, own uid, an existing version.
    await assertSucceeds(
      setDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f4"), {
        version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
        reviewerRole: "Adviser", body: "Tighten the problem statement.",
        createdAt: serverTimestamp(),
      }));

    // Append-only.
    await assertFails(
      updateDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f4"),
        { body: "Actually it is fine" }));
    await assertFails(
      deleteDoc(doc(adv, "theses/m2/documents/chapterI/feedback/f4")));
  });

test("M2: the student reads their feedback immediately", async () => {
  // Unlike M1b defence comments, this feedback exists to be acted on.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await seedChapters(db);
    await setDoc(doc(db, "theses/m2/documents/chapterI/feedback/f1"), {
      version: 1, reviewerUid: "adviser-uid", reviewerName: "Dr. A",
      reviewerRole: "Adviser", body: "Tighten it.",
      createdAt: Timestamp.now(),
    });
  });
  const leader = asDocUser("leader-uid", "leader@isufst.edu.ph");
  await assertSucceeds(
    getDoc(doc(leader, "theses/m2/documents/chapterI/feedback/f1")));
});
```

Ensure `writeBatch` and `deleteDoc` are in the file's imports from `firebase/firestore`; add them if absent.

- [ ] **Step 2: Run to verify they fail**

Run: `cd rules-test && npm test`
Expected: the new M2 tests FAIL — with no rules for these paths, the catch-all denies everything, so the `assertSucceeds` controls fail.

- [ ] **Step 3: Write the rules**

Insert inside `match /theses/{thesisId} { ... }`, immediately after the `titleComposing` block.

```
      function isAdviser(thesisId) {
        return signedIn() && thesisData(thesisId).adviserUid == request.auth.uid;
      }

      function chapterIds() {
        return ['chapterI', 'chapterII', 'chapterIII', 'chapterIV',
                'chapterV'];
      }

      match /documents/{chapterId} {
        // The dean reads STATUS here and nothing below it: §3.1 gives them
        // college-wide progress visibility, not chapter review. The split
        // falls on the collection boundary, so no field filtering is needed.
        allow get, list: if isThesisLeader(thesisId) || isAdviser(thesisId)
                         || isCoordinator() || isDean();

        allow create: if verified()
                      && isThesisLeader(thesisId)
                      && thesisData(thesisId).status == 'titleApproved'
                      && chapterId in chapterIds()
                      && request.resource.data.keys().hasOnly(
                           ['type', 'currentVersion', 'status', 'updatedAt'])
                      && request.resource.data.type == chapterId
                      && request.resource.data.currentVersion == 1
                      && request.resource.data.status == 'submitted'
                      && request.resource.data.updatedAt == request.time;

        // Two disjoint arms, OR'd. The student reaches `submitted` only by
        // adding a version; the adviser writes only a decision. Neither can
        // perform the other's half, which is what makes the status
        // trustworthy without a server.

        // Student: a new version. Blocked once approved -- only the adviser
        // reopens, so a group cannot swap an approved chapter unseen.
        allow update: if verified()
                      && isThesisLeader(thesisId)
                      && resource.data.status in ['submitted', 'revise']
                      && request.resource.data.currentVersion
                         == resource.data.currentVersion + 1
                      && request.resource.data.status == 'submitted'
                      && request.resource.data.type == resource.data.type
                      && request.resource.data.updatedAt == request.time;

        // Adviser: a decision, never a version bump.
        allow update: if verified()
                      && isAdviser(thesisId)
                      && request.resource.data.status in ['revise', 'approved']
                      && request.resource.data.currentVersion
                         == resource.data.currentVersion
                      && request.resource.data.type == resource.data.type
                      && request.resource.data.updatedAt == request.time;

        allow delete: if false;

        match /versions/{versionNo} {
          // No dean: they see that a chapter is approved, never its files.
          allow get, list: if isThesisLeader(thesisId) || isAdviser(thesisId)
                           || isCoordinator();

          // Written in the SAME batch as the parent's version bump, and a
          // batch is evaluated against the state BEFORE it -- so the parent
          // still reads its old currentVersion here. The rule is therefore
          // written as "+ 1", never "==". Probed in rules.test.js with a
          // two-sided test, not assumed.
          allow create: if verified()
                        && isThesisLeader(thesisId)
                        && request.resource.data.keys().hasOnly(
                             ['version', 'storagePath', 'fileUrl',
                              'uploadedBy', 'uploadedAt', 'mimeType',
                              'sizeBytes'])
                        && request.resource.data.uploadedBy == request.auth.uid
                        && request.resource.data.uploadedAt == request.time
                        && request.resource.data.version is int
                        && string(request.resource.data.version) == versionNo
                        && request.resource.data.version
                           == get(/databases/$(database)/documents/theses/
                                  $(thesisId)/documents/$(chapterId))
                                .data.currentVersion + 1;

          // Nothing is ever overwritten: the history is a record, not a
          // snapshot.
          allow update, delete: if false;
        }

        match /feedback/{feedbackId} {
          allow get, list: if isThesisLeader(thesisId) || isAdviser(thesisId)
                           || isCoordinator();

          allow create: if verified()
                        && isAdviser(thesisId)
                        && request.resource.data.keys().hasOnly(
                             ['version', 'reviewerUid', 'reviewerName',
                              'reviewerRole', 'body', 'createdAt'])
                        && request.resource.data.reviewerUid
                           == request.auth.uid
                        && request.resource.data.body is string
                        && request.resource.data.body.size() > 0
                        && request.resource.data.createdAt == request.time
                        && request.resource.data.version is int
                        && request.resource.data.version >= 1
                        && request.resource.data.version
                           <= get(/databases/$(database)/documents/theses/
                                  $(thesisId)/documents/$(chapterId))
                                .data.currentVersion;

          // Append-only, per parent design §6.4. The student may already
          // have acted on the original wording.
          allow update, delete: if false;
        }
      }
```

Write each `get(...)` path on ONE line — the line breaks above are for
readability only and are a syntax error in `firestore.rules`.

- [ ] **Step 4: Run to verify they pass**

Run: `cd rules-test && npm test`
Expected: all tests pass, count increased by 11.

- [ ] **Step 5: Falsify — the version rule**

Change `== ... .currentVersion + 1` to `== ... .currentVersion`. Run.
Expected: `M2 batch evaluation` FAILS on its `assertSucceeds`. Restore.

- [ ] **Step 6: Falsify — the two status arms**

Delete the adviser `allow update` arm. Run.
Expected: `a student may NOT write approved...` FAILS on its control. Restore.

- [ ] **Step 7: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: rules for chapters, versions and feedback"
```

---

### Task 3: Let an adviser list the theses they advise

**Files:**
- Modify: `firestore.rules` — the `allow list` on `match /theses/{thesisId}`
- Modify: `rules-test/rules.test.js`

**Interfaces:**
- Consumes: nothing
- Produces: an adviser-scoped `list` on `theses`, relied on by Task 8

- [ ] **Step 1: Write the failing test**

```javascript
test("M2: an adviser lists the theses they advise, and only those",
  async () => {
    // Until now `allow list` on theses was coordinator/dean/own-leader only,
    // which is why the faculty dashboard's "My advisees" was a placeholder.
    // M2 breaks on it: an adviser has no way to find the chapters waiting.
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "theses/adv1"), docThesis());
      await setDoc(doc(db, "theses/adv2"),
        docThesis("titleApproved", { adviserUid: "someone-else" }));
    });
    const adv = asDocUser("adviser-uid", "adviser@isufst.edu.ph");
    await assertSucceeds(getDocs(query(collection(adv, "theses"),
      where("adviserUid", "==", "adviser-uid"))));
    // Control: the same adviser may NOT list the whole collection.
    await assertFails(getDocs(collection(adv, "theses")));
  });
```

Ensure `getDocs`, `query`, `where`, `collection` are imported.

- [ ] **Step 2: Run to verify it fails**

Run: `cd rules-test && npm test`
Expected: FAIL on the `assertSucceeds` — the adviser has no list permission.

- [ ] **Step 3: Add the rule arm**

In `match /theses/{thesisId}`, extend the existing `allow list`:

```
      // Finding (b) gave the leader arm. M2 adds the adviser arm: an
      // adviser must be able to find the theses whose chapters they review.
      // Narrow by construction -- the arm is evaluated per returned
      // document, so it can only ever return theses naming this adviser.
      allow list: if (signedIn() && resource.data.leaderUid == request.auth.uid)
                  || (signedIn() && resource.data.adviserUid == request.auth.uid)
                  || isCoordinator() || isDean();
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd rules-test && npm test`
Expected: PASS.

- [ ] **Step 5: Falsify**

Remove the new arm. Run. Expected: the new test FAILS. Restore.

- [ ] **Step 6: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: let an adviser list the theses they advise"
```

---

### Task 4: DocumentRepository and providers

**Files:**
- Create: `lib/data/repositories/document_repository.dart`
- Create: `lib/providers/document_providers.dart`
- Test: `test/data/repositories/document_repository_test.dart`

**Interfaces:**
- Consumes: `ChapterId`, `ChapterStatus`, `ThesisChapter`, `ChapterVersion`, `ChapterFeedback` (Task 1); `signedInUidProvider` from `lib/providers/auth_providers.dart`; `firestoreProvider` from the same file
- Produces:
  - `class DocumentRepository { Stream<List<ThesisChapter>> watchChapters(String thesisId); Stream<List<ChapterVersion>> watchVersions(String thesisId, ChapterId chapter); Stream<List<ChapterFeedback>> watchFeedback(String thesisId, ChapterId chapter); Future<void> addVersion({required String thesisId, required ChapterId chapter, required String storagePath, required String fileUrl, required String mimeType, required int sizeBytes, required String uploadedBy}); Future<void> setChapterStatus({required String thesisId, required ChapterId chapter, required ChapterStatus status}); Future<void> addFeedback({required String thesisId, required ChapterId chapter, required int version, required String reviewerUid, required String reviewerName, required String reviewerRole, required String body}); }`
  - `documentRepositoryProvider`, `chaptersProvider` (family on thesisId), `chapterVersionsProvider` (family on a `({String thesisId, ChapterId chapter})` record), `chapterFeedbackProvider` (same family shape)

- [ ] **Step 1: Write the failing test**

```dart
// test/data/repositories/document_repository_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';

Future<FakeFirebaseFirestore> seed({String status = 'titleApproved'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': status,
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  return db;
}

void main() {
  test('the first upload creates the chapter at version 1', () async {
    final db = await seed();
    final repo = DocumentRepository(db);

    await repo.addVersion(
      thesisId: 't1', chapter: ChapterId.chapterI,
      storagePath: 'p', fileUrl: 'u', mimeType: 'application/pdf',
      sizeBytes: 10, uploadedBy: 'l1',
    );

    final chapters = await repo.watchChapters('t1').first;
    expect(chapters.single.id, ChapterId.chapterI);
    expect(chapters.single.currentVersion, 1);
    expect(chapters.single.status, ChapterStatus.submitted);

    final versions =
        await repo.watchVersions('t1', ChapterId.chapterI).first;
    expect(versions.single.version, 1);
  });

  test('a second upload increments the version and keeps the first',
      () async {
    final db = await seed();
    final repo = DocumentRepository(db);
    for (var i = 0; i < 2; i++) {
      await repo.addVersion(
        thesisId: 't1', chapter: ChapterId.chapterI,
        storagePath: 'p$i', fileUrl: 'u$i', mimeType: 'application/pdf',
        sizeBytes: 10, uploadedBy: 'l1',
      );
    }
    final chapters = await repo.watchChapters('t1').first;
    expect(chapters.single.currentVersion, 2);

    final versions =
        await repo.watchVersions('t1', ChapterId.chapterI).first;
    expect(versions.map((v) => v.version), [2, 1]); // newest first
    expect(versions.map((v) => v.storagePath), ['p1', 'p0']);
  });

  test('uploading onto an approved chapter is refused before any write',
      () async {
    // The rules deny it too, but fake_cloud_firestore does not enforce
    // rules -- without this check the app would report success and write
    // nothing anyone could see.
    final db = await seed();
    final repo = DocumentRepository(db);
    await repo.addVersion(
      thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p',
      fileUrl: 'u', mimeType: 'application/pdf', sizeBytes: 10,
      uploadedBy: 'l1',
    );
    await repo.setChapterStatus(
      thesisId: 't1', chapter: ChapterId.chapterI,
      status: ChapterStatus.approved,
    );

    await expectLater(
      repo.addVersion(
        thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p2',
        fileUrl: 'u2', mimeType: 'application/pdf', sizeBytes: 10,
        uploadedBy: 'l1',
      ),
      throwsStateError,
    );
    final versions =
        await repo.watchVersions('t1', ChapterId.chapterI).first;
    expect(versions.length, 1, reason: 'nothing was written');
  });

  test('uploading before the title is approved is refused', () async {
    final db = await seed(status: 'titlePendingDefence');
    final repo = DocumentRepository(db);
    await expectLater(
      repo.addVersion(
        thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p',
        fileUrl: 'u', mimeType: 'application/pdf', sizeBytes: 10,
        uploadedBy: 'l1',
      ),
      throwsStateError,
    );
  });

  test('chapters come back in I-V order regardless of upload order',
      () async {
    // Seeded deliberately against the intended order: Firestore returns a
    // collection sorted by document id, and 'chapterI' < 'chapterII' <
    // 'chapterIII' < 'chapterIV' < 'chapterV' is NOT the reading order --
    // chapterIV sorts before chapterV but after chapterIII only by luck.
    final db = await seed();
    final repo = DocumentRepository(db);
    for (final c in [ChapterId.chapterV, ChapterId.chapterII,
                     ChapterId.chapterIV]) {
      await repo.addVersion(
        thesisId: 't1', chapter: c, storagePath: 'p', fileUrl: 'u',
        mimeType: 'application/pdf', sizeBytes: 10, uploadedBy: 'l1',
      );
    }
    final chapters = await repo.watchChapters('t1').first;
    expect(chapters.map((c) => c.id),
        [ChapterId.chapterII, ChapterId.chapterIV, ChapterId.chapterV]);
  });

  test('feedback is listed oldest first and carries its version', () async {
    final db = await seed();
    final repo = DocumentRepository(db);
    await repo.addVersion(
      thesisId: 't1', chapter: ChapterId.chapterI, storagePath: 'p',
      fileUrl: 'u', mimeType: 'application/pdf', sizeBytes: 10,
      uploadedBy: 'l1',
    );
    await repo.addFeedback(
      thesisId: 't1', chapter: ChapterId.chapterI, version: 1,
      reviewerUid: 'a1', reviewerName: 'Dr. A', reviewerRole: 'Adviser',
      body: 'First point.',
    );
    await repo.addFeedback(
      thesisId: 't1', chapter: ChapterId.chapterI, version: 1,
      reviewerUid: 'a1', reviewerName: 'Dr. A', reviewerRole: 'Adviser',
      body: 'Second point.',
    );
    final feedback =
        await repo.watchFeedback('t1', ChapterId.chapterI).first;
    expect(feedback.map((f) => f.body), ['First point.', 'Second point.']);
    expect(feedback.every((f) => f.version == 1), isTrue);
  });

  test('empty feedback is refused', () async {
    final db = await seed();
    final repo = DocumentRepository(db);
    await expectLater(
      repo.addFeedback(
        thesisId: 't1', chapter: ChapterId.chapterI, version: 1,
        reviewerUid: 'a1', reviewerName: 'Dr. A', reviewerRole: 'Adviser',
        body: '   ',
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/data/repositories/document_repository_test.dart`
Expected: FAIL — `document_repository.dart` does not exist.

- [ ] **Step 3: Write the repository**

```dart
// lib/data/repositories/document_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

class DocumentRepository {
  DocumentRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _thesis(String id) =>
      _db.collection('theses').doc(id);

  CollectionReference<Map<String, dynamic>> _documents(String thesisId) =>
      _thesis(thesisId).collection('documents');

  DocumentReference<Map<String, dynamic>> _chapter(
          String thesisId, ChapterId chapter) =>
      _documents(thesisId).doc(chapter.value);

  /// The chapters that exist, in reading order.
  ///
  /// Sorted in Dart on the enum's index, not by document id: `chapterII`
  /// sorts before `chapterIII` lexically but `chapterIV` and `chapterV` do
  /// not reliably follow, and the set is five documents so ordering it
  /// costs nothing and needs no index.
  Stream<List<ThesisChapter>> watchChapters(String thesisId) {
    return _documents(thesisId).snapshots().map((s) {
      final chapters = s.docs
          .where((d) => ChapterId.fromString(d.id) != null)
          .map((d) => ThesisChapter.fromMap(d.id, {
                ...d.data(),
                'updatedAt': (d.data()['updatedAt'] as Timestamp?)?.toDate(),
              }))
          .toList();
      chapters.sort((a, b) => a.id.index.compareTo(b.id.index));
      return chapters;
    });
  }

  /// Newest version first — what a reviewer opens is the current draft.
  Stream<List<ChapterVersion>> watchVersions(
      String thesisId, ChapterId chapter) {
    return _chapter(thesisId, chapter).collection('versions').snapshots().map(
      (s) {
        final versions = s.docs
            .map((d) => ChapterVersion.fromMap({
                  ...d.data(),
                  'uploadedAt':
                      (d.data()['uploadedAt'] as Timestamp?)?.toDate(),
                }))
            .toList();
        versions.sort((a, b) => b.version.compareTo(a.version));
        return versions;
      },
    );
  }

  /// Oldest first — feedback reads as a conversation.
  Stream<List<ChapterFeedback>> watchFeedback(
      String thesisId, ChapterId chapter) {
    return _chapter(thesisId, chapter).collection('feedback').snapshots().map(
      (s) {
        final items = s.docs
            .map((d) => ChapterFeedback.fromMap(d.id, {
                  ...d.data(),
                  'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate(),
                }))
            .toList();
        items.sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null || bt == null) return a.id.compareTo(b.id);
          final byTime = at.compareTo(bt);
          return byTime != 0 ? byTime : a.id.compareTo(b.id);
        });
        return items;
      },
    );
  }

  /// Adds a version and bumps the chapter, in one batch.
  ///
  /// Batched because the two must not be separable: a version without the
  /// bump is invisible, and a bump without the version points at nothing.
  /// The rules judge each write against the PRE-batch state, which is why
  /// the version rule reads `currentVersion + 1`.
  Future<void> addVersion({
    required String thesisId,
    required ChapterId chapter,
    required String storagePath,
    required String fileUrl,
    required String mimeType,
    required int sizeBytes,
    required String uploadedBy,
  }) async {
    final thesisSnap = await _thesis(thesisId).get();
    if (!thesisSnap.exists) throw StateError('That thesis no longer exists.');
    final status =
        ThesisStatus.fromString(thesisSnap.data()!['status'] as String?);
    if (status != ThesisStatus.titleApproved) {
      throw StateError(
          'Chapters can be uploaded once the title has been approved.');
    }

    final chapterRef = _chapter(thesisId, chapter);
    final chapterSnap = await chapterRef.get();
    final batch = _db.batch();

    final int version;
    if (!chapterSnap.exists) {
      version = 1;
      batch.set(chapterRef, {
        'type': chapter.value,
        'currentVersion': 1,
        'status': ChapterStatus.submitted.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final current = ThesisChapter.fromMap(chapterSnap.id, chapterSnap.data()!);
      if (current.status == ChapterStatus.approved) {
        throw StateError(
            'This chapter is approved. Ask your adviser to reopen it before '
            'uploading again.');
      }
      version = current.currentVersion + 1;
      batch.update(chapterRef, {
        'currentVersion': version,
        'status': ChapterStatus.submitted.value,
        'type': chapter.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.set(chapterRef.collection('versions').doc('$version'), {
      'version': version,
      'storagePath': storagePath,
      'fileUrl': fileUrl,
      'uploadedBy': uploadedBy,
      'uploadedAt': FieldValue.serverTimestamp(),
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    });

    await batch.commit();
  }

  /// The adviser's half of the status: `revise` or `approved` only.
  Future<void> setChapterStatus({
    required String thesisId,
    required ChapterId chapter,
    required ChapterStatus status,
  }) async {
    if (status == ChapterStatus.submitted) {
      throw ArgumentError(
          'Only uploading a version can mark a chapter submitted.');
    }
    await _chapter(thesisId, chapter).update({
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addFeedback({
    required String thesisId,
    required ChapterId chapter,
    required int version,
    required String reviewerUid,
    required String reviewerName,
    required String reviewerRole,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Write something first.');
    await _chapter(thesisId, chapter).collection('feedback').add({
      'version': version,
      'reviewerUid': reviewerUid,
      'reviewerName': reviewerName,
      'reviewerRole': reviewerRole,
      'body': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
```

- [ ] **Step 4: Write the providers**

```dart
// lib/providers/document_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

typedef ChapterRef = ({String thesisId, ChapterId chapter});

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(firestoreProvider)),
);

final chaptersProvider =
    StreamProvider.family<List<ThesisChapter>, String>((ref, thesisId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(documentRepositoryProvider).watchChapters(thesisId);
});

final chapterVersionsProvider =
    StreamProvider.family<List<ChapterVersion>, ChapterRef>((ref, r) {
  ref.watch(signedInUidProvider);
  return ref
      .watch(documentRepositoryProvider)
      .watchVersions(r.thesisId, r.chapter);
});

final chapterFeedbackProvider =
    StreamProvider.family<List<ChapterFeedback>, ChapterRef>((ref, r) {
  ref.watch(signedInUidProvider);
  return ref
      .watch(documentRepositoryProvider)
      .watchFeedback(r.thesisId, r.chapter);
});
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/data/repositories/document_repository_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 6: Falsify the ordering test**

In `watchChapters`, delete the `chapters.sort(...)` line. Run.
Expected: `chapters come back in I-V order` FAILS. Restore.

- [ ] **Step 7: Falsify the approved lock**

Delete the `if (current.status == ChapterStatus.approved) throw ...` block. Run.
Expected: `uploading onto an approved chapter is refused` FAILS. Restore.

- [ ] **Step 8: Commit**

```bash
git add lib/data/repositories/document_repository.dart \
        lib/providers/document_providers.dart \
        test/data/repositories/document_repository_test.dart
git commit -m "feat: document repository and providers"
```

---

### Task 5: Chapter list screen

**Files:**
- Create: `lib/features/documents/chapters_screen.dart`
- Modify: `lib/core/widgets/status_chip.dart` — add `chapterLabelFor` / `chapterColorFor`
- Test: `test/features/documents/chapters_screen_test.dart`

**Interfaces:**
- Consumes: `chaptersProvider`, `thesisByIdProvider`, `ChapterId`, `ChapterStatus`
- Produces: `class ChaptersScreen extends ConsumerWidget { const ChaptersScreen({super.key, required this.thesisId}); final String thesisId; }`; key `Key('chaptersScreen')`; per-row keys `Key('chapterRow-chapterI')` … ; key `Key('notUnlocked')`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/documents/chapters_screen_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/documents/chapters_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({
  String status = 'titleApproved',
  Map<String, dynamic>? chapter,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': status,
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  if (chapter != null) {
    await db.collection('theses').doc('t1')
        .collection('documents').doc('chapterI').set(chapter);
  }
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(db)],
      child: const MaterialApp(home: ChaptersScreen(thesisId: 't1')),
    );

void main() {
  testWidgets('all five chapters are listed even when none are uploaded',
      (tester) async {
    // "Not started" is derived from absence: no document is written until
    // the first upload, so the screen must render the full set itself.
    await tester.pumpWidget(wrap(await seed()));
    await tester.pumpAndSettle();

    for (final id in ['chapterI', 'chapterII', 'chapterIII', 'chapterIV',
                      'chapterV']) {
      expect(find.byKey(Key('chapterRow-$id')), findsOneWidget);
    }
    expect(find.textContaining('Not started'), findsNWidgets(5));
  });

  testWidgets('an uploaded chapter shows its status and version',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(chapter: {
      'type': 'chapterI', 'currentVersion': 3, 'status': 'revise',
    })));
    await tester.pumpAndSettle();

    expect(find.textContaining('Needs revision'), findsOneWidget);
    expect(find.textContaining('Version 3'), findsOneWidget);
  });

  testWidgets('chapters are refused before the title is approved, with a way out',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(status: 'titlePendingDefence')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notUnlocked')), findsOneWidget);
    expect(find.byKey(const Key('chapterRow-chapterI')), findsNothing);
    // A refusal with no app bar strands the user: they must reload the app.
    expect(find.byType(AppBar), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/documents/chapters_screen_test.dart`
Expected: FAIL — `chapters_screen.dart` does not exist.

- [ ] **Step 3: Add the chapter status vocabulary**

Append to `lib/core/widgets/status_chip.dart`:

```dart
/// The single vocabulary for chapter states, alongside [StatusChip]'s
/// thesis vocabulary. Kept here so the words a student reads are decided
/// in one place rather than per screen.
class ChapterStatusWords {
  static String labelFor(ChapterStatus status) => switch (status) {
        ChapterStatus.submitted => 'With your adviser',
        ChapterStatus.revise => 'Needs revision',
        ChapterStatus.approved => 'Approved',
      };

  static String detailFor(ChapterStatus status) => switch (status) {
        ChapterStatus.submitted =>
          'Your adviser has this version and has not responded yet.',
        ChapterStatus.revise =>
          'Read the feedback, then upload the next version.',
        ChapterStatus.approved =>
          'Locked. Only your adviser can reopen it.',
      };
}
```

Add `import 'package:ethesishub/data/models/chapter.dart';` at the top of that file.

- [ ] **Step 4: Write the screen**

```dart
// lib/features/documents/chapters_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Chapters I–V for one thesis, whether or not any have been uploaded.
class ChaptersScreen extends ConsumerWidget {
  const ChaptersScreen({super.key, required this.thesisId});

  final String thesisId;

  /// Every state renders inside this frame. A bare [PageShell] has no
  /// Scaffold, so a refusal had no app bar and no way back at all.
  Widget _framed(List<Widget> children) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chapters')),
      body: PageShell(children: children),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(thesisByIdProvider(thesisId));
    final chaptersAsync = ref.watch(chaptersProvider(thesisId));

    if (thesisAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading your thesis…')]);
    }
    if (thesisAsync.hasError) {
      return _framed([
        ErrorState(
          error: thesisAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }
    final thesis = thesisAsync.valueOrNull;
    if (thesis == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Thesis not found',
          message: 'This thesis no longer exists, or it belongs to another '
              'group.',
        ),
      ]);
    }
    if (thesis.status != ThesisStatus.titleApproved) {
      return _framed(const [
        EmptyState(
          key: Key('notUnlocked'),
          icon: Icons.lock_outline,
          title: 'Chapters are not open yet',
          message: 'Chapters can be uploaded once the Dean has approved '
              'your title.',
        ),
      ]);
    }

    final uploaded = {
      for (final c in chaptersAsync.valueOrNull ?? const <ThesisChapter>[])
        c.id: c,
    };

    return Scaffold(
      key: const Key('chaptersScreen'),
      appBar: AppBar(title: const Text('Chapters')),
      body: PageShell(
        title: 'Chapters',
        subtitle: 'Upload each chapter for your adviser to review. Every '
            'upload is kept, so nothing is ever overwritten.',
        children: [
          if (chaptersAsync.hasError)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ErrorState(
                error: chaptersAsync.error,
                message: 'Could not load your chapters.',
              ),
            ),
          for (final id in ChapterId.values)
            Card(
              key: Key('chapterRow-${id.value}'),
              child: ListTile(
                title: Text(id.label),
                subtitle: Text(uploaded[id] == null
                    ? 'Not started'
                    : '${ChapterStatusWords.labelFor(uploaded[id]!.status)}'
                        ' · Version ${uploaded[id]!.currentVersion}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go(
                    '/thesis/chapters/${id.value}?id=$thesisId'),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/documents/chapters_screen_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 6: Falsify**

Change the `notUnlocked` branch to return `PageShell(children: [...])` without the Scaffold. Run.
Expected: FAIL — `Found 0 widgets with type "AppBar"`. Restore.

- [ ] **Step 7: Commit**

```bash
git add lib/features/documents/chapters_screen.dart \
        lib/core/widgets/status_chip.dart \
        test/features/documents/chapters_screen_test.dart
git commit -m "feat: chapter list screen"
```

---

### Task 6: Chapter detail — versions and feedback

**Files:**
- Create: `lib/features/documents/chapter_detail_screen.dart`
- Test: `test/features/documents/chapter_detail_screen_test.dart`

**Interfaces:**
- Consumes: `chaptersProvider`, `chapterVersionsProvider`, `chapterFeedbackProvider`, `ChapterRef`, `currentUserProvider`
- Produces: `class ChapterDetailScreen extends ConsumerStatefulWidget { const ChapterDetailScreen({super.key, required this.thesisId, required this.chapter, this.pickDocument}); final String thesisId; final ChapterId chapter; final DocumentPicker? pickDocument; }`; keys `Key('versionRow-1')`, `Key('feedbackRow-<id>')`, `Key('uploadVersion')`, `Key('notStarted')`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/documents/chapter_detail_screen_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({int versions = 2}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  final chapter = db.collection('theses').doc('t1')
      .collection('documents').doc('chapterI');
  await chapter.set({
    'type': 'chapterI', 'currentVersion': versions, 'status': 'revise',
  });
  for (var v = 1; v <= versions; v++) {
    await chapter.collection('versions').doc('$v').set({
      'version': v, 'storagePath': 'p$v', 'fileUrl': 'https://x/$v.pdf',
      'uploadedBy': 'l1', 'mimeType': 'application/pdf', 'sizeBytes': 10,
    });
  }
  await chapter.collection('feedback').doc('f1').set({
    'version': 1, 'reviewerUid': 'a1', 'reviewerName': 'Dr. Armada',
    'reviewerRole': 'Adviser', 'body': 'Tighten the problem statement.',
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: ChapterDetailScreen(
          thesisId: 't1', chapter: ChapterId.chapterI),
      ),
    );

void main() {
  testWidgets('every version is listed, newest first', (tester) async {
    await tester.pumpWidget(wrap(await seed()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('versionRow-1')), findsOneWidget);
    expect(find.byKey(const Key('versionRow-2')), findsOneWidget);

    final rows = tester.widgetList(find.byType(ListTile)).length;
    expect(rows, greaterThanOrEqualTo(2));

    final first = tester.getTopLeft(find.byKey(const Key('versionRow-2')));
    final second = tester.getTopLeft(find.byKey(const Key('versionRow-1')));
    expect(first.dy, lessThan(second.dy),
        reason: 'the newest version is what a reviewer opens');
  });

  testWidgets('feedback is shown against the version it addresses',
      (tester) async {
    await tester.pumpWidget(wrap(await seed()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feedbackRow-f1')), findsOneWidget);
    expect(find.textContaining('Tighten the problem statement.'),
        findsOneWidget);
    expect(find.textContaining('Version 1'), findsWidgets);
  });

  testWidgets('a chapter with no uploads says so, inside a frame',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'memberNames': <String>[],
      'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
      'semester': 'First', 'academicYear': '2026-2027',
    });
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notStarted')), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/documents/chapter_detail_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/features/documents/chapter_detail_screen.dart` with a
`ConsumerStatefulWidget` that:

- takes `thesisId`, `chapter`, and an injectable `DocumentPicker?`
  (reuse the typedef from `lib/features/titles/submit_titles_screen.dart`;
  move it to `lib/features/titles/file_upload.dart` and import it in both
  places so there is one definition)
- watches `chaptersProvider(thesisId)`,
  `chapterVersionsProvider((thesisId: thesisId, chapter: chapter))`, and
  `chapterFeedbackProvider((thesisId: thesisId, chapter: chapter))`
- renders every state inside `Scaffold(appBar: AppBar(title: Text(chapter.label)))`
- when no chapter document exists, renders
  `EmptyState(key: Key('notStarted'), icon: Icons.upload_file, title: 'Not started', message: 'Upload your first version to begin.')`
  followed by the upload button
- for each version, a `Card(key: Key('versionRow-${v.version}'))` with a
  `ListTile` titled `'Version ${v.version}'`, a subtitle carrying the
  upload date, and a trailing `TextButton` labelled `'Open'` that calls
  `launchUrl(Uri.parse(v.fileUrl))` from `package:url_launcher`
- beneath the versions, each feedback item as
  `Card(key: Key('feedbackRow-${f.id}'))` showing
  `'${f.reviewerName} — ${f.reviewerRole} · Version ${f.version}'` and the
  body
- an upload control keyed `Key('uploadVersion')`, disabled with an
  explanatory line when `status == ChapterStatus.approved`

Upload behaviour is Task 7; in this task the button may be present and
call an empty handler.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/documents/chapter_detail_screen_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Falsify**

In the versions list, remove the newest-first sort in the repository
(`versions.sort(...)`). Run.
Expected: `every version is listed, newest first` FAILS on the position
assertion. Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/chapter_detail_screen.dart \
        lib/features/titles/file_upload.dart \
        lib/features/titles/submit_titles_screen.dart \
        test/features/documents/chapter_detail_screen_test.dart
git commit -m "feat: chapter detail with version history and feedback"
```

---

### Task 7: Uploading a version, with orphan cleanup

**Files:**
- Modify: `lib/features/documents/chapter_detail_screen.dart`
- Modify: `lib/features/titles/file_upload.dart` — add `kChapterTypes`, `kChapterMaxBytes`
- Test: `test/features/documents/upload_version_test.dart`

**Interfaces:**
- Consumes: `uploadDocument`, `validateDocument`, `StorageFailure`, `classifyStorageError`, `storageServiceProvider`, `documentRepositoryProvider`
- Produces: `const kChapterTypes = {'pdf', 'doc', 'docx'}`; `const kChapterMaxBytes = 15 * 1024 * 1024`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/documents/upload_version_test.dart
import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

class _FakeStorage implements StorageService {
  _FakeStorage({this.failWith});
  final Object? failWith;
  final deleted = <String>[];
  int uploads = 0;

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    uploads++;
    if (failWith != null) throw failWith!;
    return StoredFile(path: path, url: 'https://example.test/$path');
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

PickedDocument doc() => PickedDocument(
      name: 'chapter1.pdf',
      bytes: Uint8List.fromList(List.filled(32, 0)),
      extension: 'pdf',
      contentType: 'application/pdf',
    );

Future<FakeFirebaseFirestore> seed({String status = 'titleApproved'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': status,
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db, _FakeStorage storage) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: MaterialApp(
        home: ChapterDetailScreen(
          thesisId: 't1',
          chapter: ChapterId.chapterI,
          pickDocument: ({required Set<String> allowed}) async => doc(),
        ),
      ),
    );

void main() {
  testWidgets('an upload creates version 1 and shows it', (tester) async {
    final db = await seed();
    final storage = _FakeStorage();
    await tester.pumpWidget(wrap(db, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(storage.uploads, 1);
    expect(find.byKey(const Key('versionRow-1')), findsOneWidget);
  });

  testWidgets('a storage outage says so instead of "try again"',
      (tester) async {
    final db = await seed();
    final storage = _FakeStorage(
      failWith: const StorageFailure('Storage is unreachable.',
          code: 'storage-unreachable'),
    );
    await tester.pumpWidget(wrap(db, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(find.textContaining('storage-unreachable'), findsOneWidget);
  });

  testWidgets('a failed batch deletes the file it had already uploaded',
      (tester) async {
    // Otherwise the object is orphaned in a public bucket: unreferenced,
    // unguessable, harmless, and still real.
    final db = await seed(status: 'titlePendingDefence');
    final storage = _FakeStorage();
    await tester.pumpWidget(wrap(db, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(storage.uploads, 1);
    expect(storage.deleted, hasLength(1),
        reason: 'the uploaded object must not be left behind');
    expect(find.textContaining('approved'), findsWidgets,
        reason: 'the original failure is reported, not the cleanup');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/documents/upload_version_test.dart`
Expected: FAIL — no upload handler.

- [ ] **Step 3: Add the constants**

Append to `lib/features/titles/file_upload.dart`:

```dart
/// A chapter carries figures and tables, so the cap is above M1b's 10 MB
/// justification limit and below the bucket's 50 MB ceiling.
const kChapterTypes = {'pdf', 'doc', 'docx'};
const kChapterMaxBytes = 15 * 1024 * 1024;
```

- [ ] **Step 4: Implement the handler**

In `ChapterDetailScreen`, add:

```dart
  Future<void> _upload() async {
    if (_busy) return;
    final pick = widget.pickDocument ?? realPicker;
    final file = await pick(allowed: kChapterTypes);
    if (file == null) return;

    final invalid = validateDocument(file,
        allowed: kChapterTypes, maxBytes: kChapterMaxBytes);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final storage = ref.read(storageServiceProvider);
    StoredFile? stored;
    try {
      stored = await uploadDocument(
        storage: storage,
        file: file,
        thesisId: widget.thesisId,
        documentId: widget.chapter.value,
      );
      await ref.read(documentRepositoryProvider).addVersion(
            thesisId: widget.thesisId,
            chapter: widget.chapter,
            storagePath: stored.path,
            fileUrl: stored.url,
            mimeType: file.contentType,
            sizeBytes: file.bytes.length,
            uploadedBy: uid,
          );
    } on StorageFailure catch (e) {
      if (mounted) setState(() => _error = '${e.message} [${e.code}]');
    } catch (e) {
      // The file is already in a public bucket but the record that would
      // reference it was never written. Remove the orphan, best-effort:
      // a failed cleanup must never replace the real failure.
      if (stored != null) {
        try {
          await storage.delete(stored.path);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _error =
            e is StateError ? e.message : 'Could not upload this version.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

Rename `_realPicker` in `submit_titles_screen.dart` to `realPicker`, move it
into `file_upload.dart`, and import it in both screens.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/documents/upload_version_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 6: Falsify the cleanup**

Delete the `await storage.delete(stored.path);` line. Run.
Expected: `a failed batch deletes the file it had already uploaded` FAILS
with `Expected: an object with length of <1>`. Restore.

- [ ] **Step 7: Commit**

```bash
git add lib/features/documents/chapter_detail_screen.dart \
        lib/features/titles/file_upload.dart \
        test/features/documents/upload_version_test.dart
git commit -m "feat: upload a chapter version, cleaning up an orphaned file"
```

---

### Task 8: Adviser review actions

**Files:**
- Modify: `lib/features/documents/chapter_detail_screen.dart`
- Test: `test/features/documents/adviser_review_test.dart`

**Interfaces:**
- Consumes: `currentUserProvider`, `thesisByIdProvider`, `documentRepositoryProvider`
- Produces: keys `Key('feedbackBody')`, `Key('postFeedback')`, `Key('markRevise')`, `Key('markApproved')`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/documents/adviser_review_test.dart
// Seeds a thesis with adviserUid 'a1', signs in as 'a1' via a MockUser and
// a users/a1 profile with role 'faculty', and asserts:
//
//  1. 'the adviser sees the review controls' -- markRevise, markApproved
//     and feedbackBody are all present.
//  2. 'a student does NOT see the review controls' -- signed in as 'l1',
//     find.byKey(Key('markApproved')) is findsNothing. The rules deny it
//     too, but a button that is visible and always fails is worse than no
//     button.
//  3. 'posting feedback writes it against the current version' -- enter
//     text, tap postFeedback, and assert the feedback document carries
//     version == the chapter's currentVersion and reviewerUid == 'a1'.
//  4. 'empty feedback is refused without writing' -- tap postFeedback with
//     a blank field, assert an error is shown and the feedback collection
//     is still empty.
//  5. 'marking approved locks the upload control' -- tap markApproved,
//     pumpAndSettle, assert the uploadVersion button's onPressed is null
//     and an explanatory line names the adviser as the one who reopens.
//
// Follow the seeding and MockUser pattern in
// test/features/titles/title_defence_screen_test.dart.
```

Write these five tests in full, following the referenced file's setup.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/documents/adviser_review_test.dart`
Expected: FAIL — no review controls exist.

- [ ] **Step 3: Implement**

Add to `ChapterDetailScreen`, shown only when
`thesis.adviserUid == signed-in uid`:

- a `TextField(key: Key('feedbackBody'))`
- `FilledButton(key: Key('postFeedback'))` calling
  `documentRepositoryProvider.addFeedback(...)` with the chapter's
  `currentVersion`, the signed-in uid, and the profile's `fullName` and a
  `reviewerRole` of `'Adviser'`
- `OutlinedButton(key: Key('markRevise'))` and
  `FilledButton(key: Key('markApproved'))` calling `setChapterStatus`
- when `status == ChapterStatus.approved`, disable `uploadVersion` and show
  `ChapterStatusWords.detailFor(ChapterStatus.approved)`

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/features/documents/adviser_review_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Falsify**

Remove the `thesis.adviserUid == uid` guard so the controls always render.
Run. Expected: `a student does NOT see the review controls` FAILS. Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/chapter_detail_screen.dart \
        test/features/documents/adviser_review_test.dart
git commit -m "feat: adviser feedback and chapter decisions"
```

---

### Task 9: My advisees

**Files:**
- Modify: `lib/providers/thesis_providers.dart` — add `myAdviseesProvider`
- Modify: `lib/data/repositories/thesis_repository.dart` — add `watchAdvisedTheses(String uid)`
- Modify: `lib/features/dashboard/faculty_dashboard.dart` — replace the placeholder
- Test: `test/features/dashboard/my_advisees_test.dart`

**Interfaces:**
- Consumes: the adviser `list` arm from Task 3; `chaptersProvider`
- Produces: `Stream<List<Thesis>> watchAdvisedTheses(String uid)`; `myAdviseesProvider` (a `StreamProvider<List<Thesis>>`)

- [ ] **Step 1: Write the failing test**

```dart
// test/features/dashboard/my_advisees_test.dart
// 1. 'an adviser sees only the theses they advise' -- seed two theses, one
//    with adviserUid 'a1' and one with 'other', sign in as 'a1', assert the
//    first appears and the second does not.
// 2. 'the placeholder copy is gone' -- assert
//    find.textContaining('Coming with the documents module') is findsNothing.
//    That sentence shipped for two milestones; a test is what stops it
//    outliving the feature.
// 3. 'an adviser with no advisees sees an empty state, not an error'.
```

Write these three tests in full.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/features/dashboard/my_advisees_test.dart`
Expected: FAIL — the placeholder text is still present.

- [ ] **Step 3: Implement**

```dart
// lib/data/repositories/thesis_repository.dart
  /// Theses this faculty member advises.
  ///
  /// Needs the adviser arm on `allow list` added in M2 — before it, this
  /// query was denied outright, which is why the faculty dashboard carried
  /// a placeholder for two milestones.
  Stream<List<Thesis>> watchAdvisedTheses(String uid) {
    return _theses
        .where('adviserUid', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs.map((d) => _toThesis(d.id, d.data())).toList());
  }
```

```dart
// lib/providers/thesis_providers.dart
/// The theses the signed-in faculty member advises.
final myAdviseesProvider = StreamProvider<List<Thesis>>((ref) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(thesisRepositoryProvider).watchAdvisedTheses(uid);
});
```

In `faculty_dashboard.dart`, replace the `subtitle:` placeholder and the
`EmptyState` body of destination 0 with a list of advisee cards, each
linking to `/thesis/chapters?id=<thesisId>`.

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/features/dashboard/my_advisees_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Falsify**

Restore the placeholder subtitle. Run. Expected: `the placeholder copy is
gone` FAILS. Remove it again.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/thesis_repository.dart \
        lib/providers/thesis_providers.dart \
        lib/features/dashboard/faculty_dashboard.dart \
        test/features/dashboard/my_advisees_test.dart
git commit -m "feat: make the faculty My advisees list real"
```

---

### Task 10: Defence readiness for the dean and coordinator

**Files:**
- Create: `lib/features/documents/defence_readiness.dart`
- Modify: `lib/features/dashboard/dean_dashboard.dart`, `lib/features/dashboard/coordinator_dashboard.dart`
- Test: `test/features/documents/defence_readiness_test.dart`

**Interfaces:**
- Consumes: `thesesByStatusProvider(ThesisStatus.titleApproved)`, `chaptersProvider`
- Produces: `DefenceReadiness readinessOf(List<ThesisChapter>)` returning `enum DefenceReadiness { notReady, proposalReady, finalReady }`; `class DefenceReadinessList extends ConsumerWidget`

- [ ] **Step 1: Write the failing test**

```dart
// test/features/documents/defence_readiness_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';

ThesisChapter ch(ChapterId id, ChapterStatus s) =>
    ThesisChapter(id: id, currentVersion: 1, status: s);

void main() {
  test('nothing approved is not ready', () {
    expect(readinessOf([ch(ChapterId.chapterI, ChapterStatus.submitted)]),
        DefenceReadiness.notReady);
  });

  test('chapters I-III approved is ready for the pre-oral', () {
    expect(
      readinessOf([
        ch(ChapterId.chapterI, ChapterStatus.approved),
        ch(ChapterId.chapterII, ChapterStatus.approved),
        ch(ChapterId.chapterIII, ChapterStatus.approved),
      ]),
      DefenceReadiness.proposalReady,
    );
  });

  test('two of the three is NOT ready', () {
    // The gate is all three. A partial set that read as ready would put a
    // group in front of a panel with a chapter nobody had approved.
    expect(
      readinessOf([
        ch(ChapterId.chapterI, ChapterStatus.approved),
        ch(ChapterId.chapterII, ChapterStatus.approved),
        ch(ChapterId.chapterIII, ChapterStatus.revise),
      ]),
      DefenceReadiness.notReady,
    );
  });

  test('all five approved is ready for the final', () {
    expect(
      readinessOf([
        for (final id in ChapterId.values) ch(id, ChapterStatus.approved),
      ]),
      DefenceReadiness.finalReady,
    );
  });

  test('a missing chapter counts as not approved', () {
    // Absence is how "not started" is represented, so an empty list must
    // never satisfy a gate by vacuous truth.
    expect(readinessOf(const []), DefenceReadiness.notReady);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/documents/defence_readiness_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

```dart
// lib/features/documents/defence_readiness.dart
import 'package:ethesishub/data/models/chapter.dart';

enum DefenceReadiness { notReady, proposalReady, finalReady }

/// Computed from the chapters themselves, never stored.
///
/// A stored `proposalReady` flag would have to be written by the adviser's
/// approval, and the rules cannot verify it: validating it means reading
/// the chapter documents, and in a batch those still evaluate against
/// their PRE-batch state, so the very chapter being approved still reads
/// as unapproved. The flag would be forgeable. This cannot be, because it
/// IS the source of truth.
DefenceReadiness readinessOf(List<ThesisChapter> chapters) {
  final approved = {
    for (final c in chapters)
      if (c.status == ChapterStatus.approved) c.id,
  };
  if (ChapterId.finalChapters.every(approved.contains)) {
    return DefenceReadiness.finalReady;
  }
  if (ChapterId.proposalChapters.every(approved.contains)) {
    return DefenceReadiness.proposalReady;
  }
  return DefenceReadiness.notReady;
}
```

Then add `DefenceReadinessList`, a `ConsumerWidget` that watches
`thesesByStatusProvider(ThesisStatus.titleApproved)` and, per thesis,
watches `chaptersProvider(thesis.id)` in a child widget (one family
instance per id cannot be looped inside a single build — follow the
`_DefencesList` pattern in `faculty_dashboard.dart`). Each row shows the
working title, the count of approved chapters out of five, and a label from
`readinessOf`. Add it as a section on both the dean and coordinator
dashboards.

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/documents/defence_readiness_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Falsify**

Change `every` to `any` in the proposal check. Run.
Expected: `two of the three is NOT ready` FAILS. Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/features/documents/defence_readiness.dart \
        lib/features/dashboard/dean_dashboard.dart \
        lib/features/dashboard/coordinator_dashboard.dart \
        test/features/documents/defence_readiness_test.dart
git commit -m "feat: defence readiness for the dean and coordinator"
```

---

### Task 11: Routing and navigation

**Files:**
- Modify: `lib/core/routing/app_router.dart`
- Modify: `lib/features/thesis/thesis_status_screen.dart` — add the entry point
- Test: `test/core/routing/m2_routes_test.dart`

**Interfaces:**
- Consumes: `ChaptersScreen`, `ChapterDetailScreen`
- Produces: routes `/thesis/chapters?id=<thesisId>` and `/thesis/chapters/:chapterId?id=<thesisId>`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/routing/m2_routes_test.dart
// Following the pattern in test/core/routing/m1b_routes_test.dart:
//
// 1. 'a student reaches the chapters screen' -- go to
//    '/thesis/chapters?id=t1', assert Key('chaptersScreen').
// 2. 'a chapter id in the path reaches the detail screen' -- go to
//    '/thesis/chapters/chapterIII?id=t1', assert the app bar reads
//    'Chapter III — Methodology'.
// 3. 'an unknown chapter id does not open a blank screen' -- go to
//    '/thesis/chapters/chapterIX?id=t1' and assert a not-found state with
//    an AppBar. ChapterId.fromString returns null by design, and a route
//    that force-unwrapped it would throw into a white screen.
// 4. 'a missing id query parameter is refused with a way back'.
```

Write these four tests in full.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/core/routing/m2_routes_test.dart`
Expected: FAIL — the routes do not exist.

- [ ] **Step 3: Add the routes**

```dart
      GoRoute(
        path: '/thesis/chapters',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          if (id == null || id.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Chapters')),
              body: const PageShell(children: [
                EmptyState(
                  icon: Icons.link_off,
                  title: 'No thesis given',
                  message: 'Open your chapters from your thesis status page.',
                ),
              ]),
            );
          }
          return ChaptersScreen(thesisId: id);
        },
      ),
      GoRoute(
        path: '/thesis/chapters/:chapterId',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          final chapter =
              ChapterId.fromString(state.pathParameters['chapterId']);
          if (id == null || id.isEmpty || chapter == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Chapter')),
              body: const PageShell(children: [
                EmptyState(
                  icon: Icons.search_off,
                  title: 'No such chapter',
                  message: 'There are five chapters, I through V.',
                ),
              ]),
            );
          }
          return ChapterDetailScreen(thesisId: id, chapter: chapter);
        },
      ),
```

Both refusal branches carry a real `AppBar`: a route that renders a bare
`PageShell` leaves the user on a white page with no way back.

Add `PageShell`, `EmptyState` and `ChapterId` to the router's imports.

On `thesis_status_screen.dart`, add a `FilledButton(key: Key('goToChapters'))`
shown when the status is `titleApproved`, navigating to
`/thesis/chapters?id=<thesisId>`.

- [ ] **Step 4: Run to verify they pass**

Run: `flutter test test/core/routing/m2_routes_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Falsify**

Change `ChapterId.fromString(...)` to `ChapterId.values.first`. Run.
Expected: `an unknown chapter id does not open a blank screen` FAILS.
Restore.

- [ ] **Step 6: Commit**

```bash
git add lib/core/routing/app_router.dart \
        lib/features/thesis/thesis_status_screen.dart \
        test/core/routing/m2_routes_test.dart
git commit -m "feat: chapter routes and the entry point from thesis status"
```

---

### Task 12: Final review

**Files:** none created; fixes go wherever the review finds them.

- [ ] **Step 1: Run everything**

```bash
flutter analyze
flutter test
cd rules-test && npm test && cd ..
```

Expected: analyzer clean apart from the two pre-existing
`use_super_parameters` infos; all Dart tests pass; all rules tests pass.

- [ ] **Step 2: Hunt vacuous tests**

For each new test, revert the code it covers and confirm it fails. A test
that passes against reverted code proves nothing. Pay particular attention
to:

- every ordering assertion (`fake_cloud_firestore` returns insertion order)
- every `assertFails` in the rules suite (confirm each has a control, and
  that `ctx.firestore()` is bound once per context)
- `readinessOf(const [])` — an `every` over an empty required set is
  vacuously true if the gate is written the other way round

- [ ] **Step 3: Deploy the rules**

```bash
firebase deploy --only firestore
```

The rules now require the `documents`, `versions` and `feedback` blocks.
Until this runs, every chapter upload is denied for every real user while
the whole suite passes locally.

- [ ] **Step 4: Manual walkthrough**

As a student: upload Chapter I, confirm version 1 appears. Upload again,
confirm version 2 appears above version 1 and both open. As the adviser:
leave feedback, confirm the student sees it immediately, mark `revise`,
confirm the student can upload again. Mark `approved`, confirm the student
cannot upload and the reason names the adviser. As the dean: confirm chapter
status is visible and files are not. As the coordinator: confirm the
readiness list shows the right gate after Chapters I–III are approved.

- [ ] **Step 5: Commit any fixes and finish the branch**

Use the `superpowers:finishing-a-development-branch` skill.
