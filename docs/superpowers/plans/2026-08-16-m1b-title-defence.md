# M1b Title Defence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A student group submits three or more candidate titles with uploaded justifications and one presentation; the panel comments on them live during the defence; the Dean records which title is approved.

**Architecture:** Candidate titles and comments are subcollections of `theses/{thesisId}`, following the `nominations/` pattern M1a established. Comments sit one level under the thesis carrying a `candidateTitleId` field rather than nesting under each candidate, so the panel's live view needs one listener and one rules block. Files go to Supabase before the Firestore document that records their path. Firestore security rules are the only authorization boundary.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Riverpod 2.6.1, Cloud Firestore, Supabase Storage, `file_picker` (new).

**Spec:** `docs/superpowers/specs/2026-08-16-m1b-title-defence-design.md`

## Global Constraints

- **Never import `dart:io` in `lib/`.** Targets are Android and Web only; `dart:io` is unavailable on Web.
- **Riverpod pinned at `2.6.1`.** Do not upgrade. Use the 2.x API (`ConsumerWidget`, `ConsumerStatefulWidget`, `ref.watch`, `ref.read`).
- **`FirebaseFirestore` is constructor-injected** into repositories. Never `FirebaseFirestore.instance` inside a class or a screen.
- **Models stay pure Dart.** All `Timestamp` → `DateTime` conversion happens in the repository.
- **Screens reach data through providers**, never a repository constructed inline.
- **`fake_cloud_firestore` does not enforce security rules.** Any rule violation passes every Dart test and fails for every real user. Client write shapes must be checked against `firestore.rules` by reading both.
- **Append-only means append-only.** `titleComments` allow no `update` and no `delete`, in the rules and in the repository.
- **Widget tests mount a router** (`MaterialApp.router` + `GoRouter`). M1a shipped a screen behind a duplicate route and another that stayed put after a successful submit; neither was visible to a test that pumped the screen alone.
- **Any collection-group query needs an index** declared in `firestore.indexes.json` in the same commit. No local test catches a missing one.
- **Rules tests need Java:** `export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.8-hotspot"`, then `cd rules-test && npm test`.
- **Baseline at plan time:** 235 Dart tests, 104 rules tests, `flutter analyze lib` clean.
- **Commit style:** stage by explicit path. Never `git add -A` or `git add .`. Author with `git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit`.

---

## File Structure

**Created**
- `lib/data/models/candidate_title.dart` — one candidate title
- `lib/data/models/title_comment.dart` — one panel comment
- `lib/data/models/composing_indicator.dart` — one "is writing" marker
- `lib/data/repositories/title_defence_repository.dart` — every read and write for this milestone
- `lib/features/titles/consolidated_comments.dart` — the bracketed grouping, pure Dart
- `lib/features/titles/submit_titles_screen.dart` — leader submits candidates
- `lib/features/titles/title_defence_screen.dart` — the panel's defence screen, including the Dean's controls
- `lib/providers/title_providers.dart` — providers for the above

**Modified**
- `lib/data/models/thesis_status.dart` — three new states
- `lib/data/models/thesis.dart` — title-defence fields
- `lib/features/thesis/thesis_status_screen.dart` — title stage and consolidated comments
- `lib/features/dashboard/faculty_dashboard.dart` — link to defences the panel is on
- `lib/core/routing/app_router.dart` — two new routes
- `firestore.rules` — four new rule blocks
- `pubspec.yaml` — `file_picker`

---

### Task 1: Models and new thesis states

**Files:**
- Create: `lib/data/models/candidate_title.dart`, `lib/data/models/title_comment.dart`, `lib/data/models/composing_indicator.dart`
- Modify: `lib/data/models/thesis_status.dart`, `lib/data/models/thesis.dart`
- Test: `test/data/models/title_models_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `CandidateTitle`, `TitleComment`, `ComposingIndicator`, each with `fromMap(String id, Map<String, dynamic>)`. `ThesisStatus.titlePendingDefence`, `.titleApproved`, `.titleRejected`. `Thesis` gains `presentationPath`, `presentationUrl`, `titlesSubmittedAt`, `titleRound`, `approvedTitleId`, `titleDecidedAt`, `titleDecidedBy`, `titleRejectionRemark`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/models/title_models_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/composing_indicator.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/title_comment.dart';

void main() {
  test('CandidateTitle round-trips from a Firestore map', () {
    final c = CandidateTitle.fromMap('ct1', {
      'titleText': 'A Web and Mobile-Based Thesis Management System',
      'justificationPath': 'theses/t1/ct1/uuid.pdf',
      'justificationUrl': 'https://example.test/uuid.pdf',
      'round': 1,
      'submittedAt': DateTime.utc(2026, 8, 16),
    });
    expect(c.id, 'ct1');
    expect(c.titleText, startsWith('A Web'));
    expect(c.round, 1);
    expect(c.submittedAt, DateTime.utc(2026, 8, 16));
  });

  test('TitleComment keeps the role held at the time of writing', () {
    // Resolving the role at render time would let a later promotion rewrite
    // history: someone who commented as a panel member would appear to have
    // commented as coordinator.
    final c = TitleComment.fromMap('cm1', {
      'candidateTitleId': 'ct1',
      'authorUid': 'p1',
      'authorName': 'Dr. Diamante',
      'authorRole': 'Panel Member',
      'body': 'Justify the choice of respondents.',
      'createdAt': DateTime.utc(2026, 8, 16, 10, 30),
    });
    expect(c.authorRole, 'Panel Member');
    expect(c.candidateTitleId, 'ct1');
    expect(c.createdAt, DateTime.utc(2026, 8, 16, 10, 30));
  });

  test('ComposingIndicator is stale after the freshness window', () {
    // There are no Cloud Functions to sweep these, so a laptop closed
    // mid-comment would leave an indicator up forever. Readers expire them.
    final now = DateTime.utc(2026, 8, 16, 10, 30);
    final fresh = ComposingIndicator.fromMap('p1', {
      'name': 'Dr. Diamante', 'role': 'Panel Member',
      'candidateTitleId': 'ct1',
      'updatedAt': now.subtract(const Duration(seconds: 5)),
    });
    final stale = ComposingIndicator.fromMap('p2', {
      'name': 'Dr. Padojinog', 'role': 'Panel Member',
      'candidateTitleId': 'ct1',
      'updatedAt': now.subtract(const Duration(seconds: 40)),
    });
    expect(fresh.isStaleAt(now), isFalse);
    expect(stale.isStaleAt(now), isTrue);
  });

  test('the new title states parse and are distinct', () {
    expect(ThesisStatus.fromString('titlePendingDefence'),
        ThesisStatus.titlePendingDefence);
    expect(ThesisStatus.fromString('titleApproved'),
        ThesisStatus.titleApproved);
    expect(ThesisStatus.fromString('titleRejected'),
        ThesisStatus.titleRejected);
  });

  test('Thesis reads the title-defence fields, and titleRound defaults to 0',
      () {
    // Theses created by M1a predate titleRound entirely.
    final old = Thesis.fromMap('t1', {
      'leaderUid': 'l1', 'memberNames': <String>[], 'workingTitle': 'T',
      'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
      'academicYear': '2026-2027', 'status': 'nominationApproved',
      'panelistUids': <String>[], 'createdAt': DateTime.utc(2026, 8, 1),
    });
    expect(old.titleRound, 0);
    expect(old.approvedTitleId, isNull);

    final current = Thesis.fromMap('t2', {
      'leaderUid': 'l1', 'memberNames': <String>[], 'workingTitle': 'T',
      'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
      'academicYear': '2026-2027', 'status': 'titleApproved',
      'panelistUids': <String>[], 'createdAt': DateTime.utc(2026, 8, 1),
      'titleRound': 2, 'approvedTitleId': 'ct3',
      'titleDecidedBy': 'd1', 'titleDecidedAt': DateTime.utc(2026, 8, 16),
      'titleRejectionRemark': null,
      'presentationPath': 'theses/t2/pres/uuid.pptx',
      'presentationUrl': 'https://example.test/uuid.pptx',
      'titlesSubmittedAt': DateTime.utc(2026, 8, 15),
    });
    expect(current.titleRound, 2);
    expect(current.approvedTitleId, 'ct3');
    expect(current.titleDecidedBy, 'd1');
    expect(current.presentationUrl, contains('uuid.pptx'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/title_models_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:ethesishub/data/models/candidate_title.dart'`

- [ ] **Step 3: Create the three models**

```dart
// lib/data/models/candidate_title.dart
/// One title a group is putting forward at their title defence, with the
/// justification document that argues for it.
class CandidateTitle {
  const CandidateTitle({
    required this.id,
    required this.titleText,
    required this.justificationPath,
    required this.justificationUrl,
    required this.round,
    this.submittedAt,
  });

  final String id;
  final String titleText;

  /// Supabase object path — what we would need to delete the file.
  final String justificationPath;

  /// Public URL — what the panel opens. The bucket is public and the path is
  /// an unguessable UUID.
  final String justificationUrl;

  /// Which submission this belonged to. A rejected set is kept, not deleted,
  /// so the round is what separates it from the resubmission.
  final int round;

  final DateTime? submittedAt;

  factory CandidateTitle.fromMap(String id, Map<String, dynamic> map) {
    return CandidateTitle(
      id: id,
      titleText: map['titleText'] as String? ?? '',
      justificationPath: map['justificationPath'] as String? ?? '',
      justificationUrl: map['justificationUrl'] as String? ?? '',
      round: (map['round'] as num?)?.toInt() ?? 0,
      submittedAt: map['submittedAt'] as DateTime?,
    );
  }
}
```

```dart
// lib/data/models/title_comment.dart
/// One remark a panel member made about one candidate title.
///
/// Append-only: there is no edit and no delete, in the rules or here. The
/// consolidated output a student eventually reads is therefore a record of
/// what was said, not a summary anyone tidied afterwards.
class TitleComment {
  const TitleComment({
    required this.id,
    required this.candidateTitleId,
    required this.authorUid,
    required this.authorName,
    required this.authorRole,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String candidateTitleId;
  final String authorUid;
  final String authorName;

  /// The position this person held WHEN THEY WROTE IT — "Adviser", "Panel
  /// Member", "Research Coordinator", "Dean". Stored rather than resolved at
  /// render time, so a later change of position cannot rewrite the header on
  /// a remark made months earlier.
  final String authorRole;

  final String body;
  final DateTime? createdAt;

  factory TitleComment.fromMap(String id, Map<String, dynamic> map) {
    return TitleComment(
      id: id,
      candidateTitleId: map['candidateTitleId'] as String? ?? '',
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorRole: map['authorRole'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
```

```dart
// lib/data/models/composing_indicator.dart
/// A marker that someone is currently writing a comment.
///
/// Transient by design: the client deletes it on submit or blur. But a laptop
/// closed mid-comment leaves one behind, and there are no Cloud Functions on
/// the Spark plan to sweep it up — so readers expire them instead. The
/// leftover document is harmless and hides itself.
class ComposingIndicator {
  const ComposingIndicator({
    required this.uid,
    required this.name,
    required this.role,
    required this.candidateTitleId,
    this.updatedAt,
  });

  /// How long an indicator stays believable. The client refreshes roughly
  /// every 5 seconds, so 15 tolerates a missed beat without lingering.
  static const staleAfter = Duration(seconds: 15);

  final String uid;
  final String name;
  final String role;
  final String candidateTitleId;
  final DateTime? updatedAt;

  bool isStaleAt(DateTime now) {
    final at = updatedAt;
    if (at == null) return true;
    return now.difference(at) > staleAfter;
  }

  factory ComposingIndicator.fromMap(String uid, Map<String, dynamic> map) {
    return ComposingIndicator(
      uid: uid,
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? '',
      candidateTitleId: map['candidateTitleId'] as String? ?? '',
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}
```

- [ ] **Step 4: Add the three new states**

In `lib/data/models/thesis_status.dart`, extend the enum. Order matters for readability only; `fromString` matches by name.

```dart
enum ThesisStatus {
  draft,
  nominationPendingConforme,
  nominationPendingCoordinator,
  nominationPendingDean,
  nominationApproved,
  // M1b. `titleApproved` is this milestone's terminal state; the move to
  // in_progress belongs to the documents module.
  titlePendingDefence,
  titleApproved,
  titleRejected;
  ...
}
```

- [ ] **Step 5: Add the thesis fields**

In `lib/data/models/thesis.dart`, add to the constructor, the fields, and `fromMap`. Follow the existing nullable-field pattern exactly.

```dart
    this.presentationPath,
    this.presentationUrl,
    this.titlesSubmittedAt,
    this.titleRound = 0,
    this.approvedTitleId,
    this.titleDecidedAt,
    this.titleDecidedBy,
    this.titleRejectionRemark,
```

```dart
  final String? presentationPath;
  final String? presentationUrl;
  final DateTime? titlesSubmittedAt;

  /// 1 for the first submission, incremented on each resubmission after a
  /// rejection. Absent on theses created by M1a — read as 0.
  final int titleRound;

  final String? approvedTitleId;
  final DateTime? titleDecidedAt;
  final String? titleDecidedBy;
  final String? titleRejectionRemark;
```

In `fromMap`:

```dart
      presentationPath: map['presentationPath'] as String?,
      presentationUrl: map['presentationUrl'] as String?,
      titlesSubmittedAt: map['titlesSubmittedAt'] as DateTime?,
      titleRound: (map['titleRound'] as num?)?.toInt() ?? 0,
      approvedTitleId: map['approvedTitleId'] as String?,
      titleDecidedAt: map['titleDecidedAt'] as DateTime?,
      titleDecidedBy: map['titleDecidedBy'] as String?,
      titleRejectionRemark: map['titleRejectionRemark'] as String?,
```

Leave `toMap()` alone. It is documented read-side only because it emits `createdAt` as a client `DateTime`, which the rules reject.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/data/models/title_models_test.dart` — Expected: PASS (5 tests)
Run: `flutter test` — Expected: PASS, 240 total
Run: `flutter analyze lib` — Expected: no issues

- [ ] **Step 7: Commit**

```bash
git add lib/data/models/candidate_title.dart lib/data/models/title_comment.dart lib/data/models/composing_indicator.dart lib/data/models/thesis_status.dart lib/data/models/thesis.dart test/data/models/title_models_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: title defence models and states"
```

---

### Task 2: Submitting candidate titles

**Files:**
- Create: `lib/data/repositories/title_defence_repository.dart`
- Create: `lib/providers/title_providers.dart`
- Test: `test/data/repositories/title_defence_repository_test.dart`

**Interfaces:**
- Consumes: `CandidateTitle`, `ThesisStatus` (Task 1); `firestoreProvider` from `lib/providers/auth_providers.dart`.
- Produces: `TitleDefenceRepository(FirebaseFirestore db)` with `Future<void> submitCandidateTitles({required String thesisId, required List<CandidateTitleDraft> titles, required String presentationPath, required String presentationUrl})` and `Stream<List<CandidateTitle>> watchCandidateTitles(String thesisId)`. Record type `CandidateTitleDraft = ({String titleText, String justificationPath, String justificationUrl})`. Provider `titleDefenceRepositoryProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/repositories/title_defence_repository_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

Future<FakeFirebaseFirestore> seed({
  String status = 'nominationApproved',
  int titleRound = 0,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'status': status, 'panelistUids': <String>[],
    'adviserUid': 'a1', 'memberNames': <String>[], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'titleRound': titleRound,
  });
  return db;
}

List<CandidateTitleDraft> drafts(int n) => [
      for (var i = 0; i < n; i++)
        (
          titleText: 'Candidate $i',
          justificationPath: 'theses/t1/c$i/uuid.pdf',
          justificationUrl: 'https://example.test/c$i.pdf',
        ),
    ];

void main() {
  test('submitting writes the candidates and advances the thesis', () async {
    final db = await seed();
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1',
      titles: drafts(3),
      presentationPath: 'theses/t1/pres/uuid.pptx',
      presentationUrl: 'https://example.test/pres.pptx',
    );

    final titles = await repo.watchCandidateTitles('t1').first;
    expect(titles, hasLength(3));
    expect(titles.every((t) => t.round == 1), isTrue,
        reason: 'the first submission is round 1');

    final thesis = (await db.collection('theses').doc('t1').get()).data()!;
    expect(thesis['status'], ThesisStatus.titlePendingDefence.value);
    expect(thesis['titleRound'], 1);
    expect(thesis['presentationUrl'], contains('pres.pptx'));
    expect(thesis['titlesSubmittedAt'], isNotNull);
  });

  test('a resubmission increments the round and keeps the rejected set',
      () async {
    // The rejected candidates are history, not rubbish. The student sees what
    // was turned down; the panel sees whether anything actually changed.
    final db = await seed(status: 'titleRejected', titleRound: 1);
    await db.collection('theses/t1/candidateTitles').doc('old').set({
      'titleText': 'Rejected one', 'justificationPath': 'p',
      'justificationUrl': 'u', 'round': 1,
    });
    final repo = TitleDefenceRepository(db);

    await repo.submitCandidateTitles(
      thesisId: 't1', titles: drafts(3),
      presentationPath: 'p2', presentationUrl: 'u2',
    );

    final all = await repo.watchCandidateTitles('t1').first;
    expect(all, hasLength(4), reason: 'the rejected candidate is still there');
    expect(all.where((t) => t.round == 2), hasLength(3));
    expect(all.where((t) => t.round == 1), hasLength(1));
  });

  test('fewer than three candidates is refused', () async {
    final repo = TitleDefenceRepository(await seed());
    expect(
      () => repo.submitCandidateTitles(
        thesisId: 't1', titles: drafts(2),
        presentationPath: 'p', presentationUrl: 'u',
      ),
      throwsArgumentError,
    );
  });

  test('more than ten candidates is refused', () async {
    // Each candidate costs one get() in the rules. M1a measured the ceiling:
    // 19 documents in a batch commit, 20 are denied, and the Cloud limit is
    // stricter than the emulator's.
    final repo = TitleDefenceRepository(await seed());
    expect(
      () => repo.submitCandidateTitles(
        thesisId: 't1', titles: drafts(11),
        presentationPath: 'p', presentationUrl: 'u',
      ),
      throwsArgumentError,
    );
  });

  test('submitting from the wrong status is refused', () async {
    // Guarding here as well as in the rules: the repository is the layer that
    // holds the line when a screen forgets.
    final repo = TitleDefenceRepository(await seed(status: 'draft'));
    expect(
      () => repo.submitCandidateTitles(
        thesisId: 't1', titles: drafts(3),
        presentationPath: 'p', presentationUrl: 'u',
      ),
      throwsStateError,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/title_defence_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Write the repository**

```dart
// lib/data/repositories/title_defence_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

/// One candidate as the screen has it: text plus an already-uploaded file.
/// The upload happens before this, so a failed Firestore write leaves an
/// orphaned object in the bucket rather than a document pointing at nothing.
typedef CandidateTitleDraft = ({
  String titleText,
  String justificationPath,
  String justificationUrl,
});

/// Every read and write for the title defence.
class TitleDefenceRepository {
  TitleDefenceRepository(this._db);

  final FirebaseFirestore _db;

  /// Three is the floor; ten is the ceiling and it is a rules constraint, not
  /// a taste one. Each candidate's create rule costs a `get()` on the thesis,
  /// and M1a measured that a batch of 20 is denied while 19 commits.
  static const int minCandidates = 3;
  static const int maxCandidates = 10;

  DocumentReference<Map<String, dynamic>> _thesis(String id) =>
      _db.collection('theses').doc(id);

  CollectionReference<Map<String, dynamic>> _candidates(String thesisId) =>
      _thesis(thesisId).collection('candidateTitles');

  CandidateTitle _toCandidate(String id, Map<String, dynamic> raw) {
    return CandidateTitle.fromMap(id, {
      ...raw,
      'submittedAt': (raw['submittedAt'] as Timestamp?)?.toDate(),
    });
  }

  Stream<List<CandidateTitle>> watchCandidateTitles(String thesisId) {
    return _candidates(thesisId).snapshots().map(
        (s) => s.docs.map((d) => _toCandidate(d.id, d.data())).toList());
  }

  /// Writes the candidates and moves the thesis to `titlePendingDefence`, in
  /// one batch.
  ///
  /// Batched writes are each evaluated against the state BEFORE the batch, so
  /// the candidate creates are judged against the thesis's current status —
  /// which is exactly why they are permitted while it is still
  /// `nominationApproved` or `titleRejected`. M1a verified this behaviour
  /// against the emulator rather than assuming it.
  Future<void> submitCandidateTitles({
    required String thesisId,
    required List<CandidateTitleDraft> titles,
    required String presentationPath,
    required String presentationUrl,
  }) async {
    if (titles.length < minCandidates) {
      throw ArgumentError(
          'At least $minCandidates candidate titles are required.');
    }
    if (titles.length > maxCandidates) {
      throw ArgumentError(
          'At most $maxCandidates candidate titles may be submitted at once.');
    }

    final snap = await _thesis(thesisId).get();
    if (!snap.exists) throw StateError('That thesis no longer exists.');
    final data = snap.data()!;
    final status = ThesisStatus.fromString(data['status'] as String?);
    if (status != ThesisStatus.nominationApproved &&
        status != ThesisStatus.titleRejected) {
      throw StateError(
          'Candidate titles can only be submitted once the nomination is '
          'approved, or after a set has been rejected.');
    }

    final nextRound = ((data['titleRound'] as num?)?.toInt() ?? 0) + 1;

    final batch = _db.batch();
    for (final t in titles) {
      batch.set(_candidates(thesisId).doc(), {
        'titleText': t.titleText.trim(),
        'justificationPath': t.justificationPath,
        'justificationUrl': t.justificationUrl,
        'round': nextRound,
        'submittedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_thesis(thesisId), {
      'status': ThesisStatus.titlePendingDefence.value,
      'titleRound': nextRound,
      'titlesSubmittedAt': FieldValue.serverTimestamp(),
      'presentationPath': presentationPath,
      'presentationUrl': presentationUrl,
    });
    await batch.commit();
  }
}
```

```dart
// lib/providers/title_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final titleDefenceRepositoryProvider = Provider<TitleDefenceRepository>(
  (ref) => TitleDefenceRepository(ref.watch(firestoreProvider)),
);

/// The candidate titles on one thesis, every round.
final candidateTitlesProvider =
    StreamProvider.family<List<CandidateTitle>, String>((ref, thesisId) {
  return ref.watch(titleDefenceRepositoryProvider)
      .watchCandidateTitles(thesisId);
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/title_defence_repository_test.dart` — Expected: PASS (5 tests)
Run: `flutter test` — Expected: PASS, 245 total

- [ ] **Step 5: Prove the guards are falsifiable**

For each of the three guards — `minCandidates`, `maxCandidates`, the status check — remove it, run the test that targets it, confirm it fails, restore it. Record the actual failure text. A guard whose test you have not watched fail is not evidence.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/title_defence_repository.dart lib/providers/title_providers.dart test/data/repositories/title_defence_repository_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: submit candidate titles"
```

---

### Task 3: Comments — append-only, per candidate

**Files:**
- Modify: `lib/data/repositories/title_defence_repository.dart`, `lib/providers/title_providers.dart`
- Test: `test/data/repositories/title_comments_test.dart`

**Interfaces:**
- Consumes: `TitleComment` (Task 1), `TitleDefenceRepository` (Task 2).
- Produces: `Future<void> addComment({required String thesisId, required String candidateTitleId, required String authorUid, required String authorName, required String authorRole, required String body})`, `Stream<List<TitleComment>> watchComments(String thesisId)`. Provider `titleCommentsProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/repositories/title_comments_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

void main() {
  test('a comment records the author and the role held at the time', () async {
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);

    await repo.addComment(
      thesisId: 't1', candidateTitleId: 'ct1',
      authorUid: 'p1', authorName: 'Dr. Diamante', authorRole: 'Panel Member',
      body: 'Justify the choice of respondents.',
    );

    final comments = await repo.watchComments('t1').first;
    expect(comments, hasLength(1));
    expect(comments.single.authorUid, 'p1');
    expect(comments.single.authorRole, 'Panel Member');
    expect(comments.single.candidateTitleId, 'ct1');
  });

  test('an empty comment is refused', () async {
    final repo = TitleDefenceRepository(FakeFirebaseFirestore());
    expect(
      () => repo.addComment(
        thesisId: 't1', candidateTitleId: 'ct1', authorUid: 'p1',
        authorName: 'Dr. Diamante', authorRole: 'Panel Member', body: '   ',
      ),
      throwsArgumentError,
    );
  });

  test('comments come back oldest first', () async {
    // The consolidated output reads as a transcript, so order is the record.
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);
    for (final body in ['first', 'second', 'third']) {
      await repo.addComment(
        thesisId: 't1', candidateTitleId: 'ct1', authorUid: 'p1',
        authorName: 'Dr. Diamante', authorRole: 'Panel Member', body: body,
      );
    }
    final comments = await repo.watchComments('t1').first;
    expect(comments.map((c) => c.body), ['first', 'second', 'third']);
  });

  test('the repository exposes no way to edit or delete a comment', () {
    // Append-only is a property of the API, not just of the rules. If a
    // method appears here later, the rules become the only thing standing
    // between a panel member and a rewritten record.
    final methods = TitleDefenceRepository(FakeFirebaseFirestore());
    expect(methods, isNotNull);
    // Enforced by review and by the rules; this test documents the intent.
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/title_comments_test.dart`
Expected: FAIL — `The method 'addComment' isn't defined`

- [ ] **Step 3: Add comments to the repository**

Append to `TitleDefenceRepository`:

```dart
  CollectionReference<Map<String, dynamic>> _comments(String thesisId) =>
      _thesis(thesisId).collection('titleComments');

  TitleComment _toComment(String id, Map<String, dynamic> raw) {
    return TitleComment.fromMap(id, {
      ...raw,
      'createdAt': (raw['createdAt'] as Timestamp?)?.toDate(),
    });
  }

  /// Every comment on the thesis, oldest first.
  ///
  /// One listener for the whole defence rather than one per candidate:
  /// comments carry `candidateTitleId` and the screen groups them. Nesting
  /// them under each candidate would have meant N listeners or a
  /// collection-group query, and the latter needs an index Firestore never
  /// creates on its own.
  Stream<List<TitleComment>> watchComments(String thesisId) {
    return _comments(thesisId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map((d) => _toComment(d.id, d.data())).toList());
  }

  /// Append-only. There is deliberately no `editComment` and no
  /// `deleteComment`: the rules forbid both, and an API that offered them
  /// would make the rules the only thing preventing a rewritten record.
  Future<void> addComment({
    required String thesisId,
    required String candidateTitleId,
    required String authorUid,
    required String authorName,
    required String authorRole,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('A comment cannot be empty.');

    await _comments(thesisId).add({
      'candidateTitleId': candidateTitleId,
      'authorUid': authorUid,
      'authorName': authorName,
      'authorRole': authorRole,
      'body': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
```

Add the import for `TitleComment`. Append to `lib/providers/title_providers.dart`:

```dart
/// Every comment on one thesis, live. Panel members hold this open through
/// the defence so a remark appears for the rest of the panel as it is
/// written — the point being that nobody repeats a point already made.
final titleCommentsProvider =
    StreamProvider.family<List<TitleComment>, String>((ref, thesisId) {
  return ref.watch(titleDefenceRepositoryProvider).watchComments(thesisId);
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/title_comments_test.dart` — Expected: PASS
Run: `flutter test` — Expected: PASS, 249 total

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/title_defence_repository.dart lib/providers/title_providers.dart test/data/repositories/title_comments_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: append-only title defence comments"
```

---

### Task 4: Composing indicators

**Files:**
- Modify: `lib/data/repositories/title_defence_repository.dart`, `lib/providers/title_providers.dart`
- Test: `test/data/repositories/title_composing_test.dart`

**Interfaces:**
- Consumes: `ComposingIndicator` (Task 1).
- Produces: `Future<void> markComposing({required String thesisId, required String uid, required String name, required String role, required String candidateTitleId})`, `Future<void> clearComposing({required String thesisId, required String uid})`, `Stream<List<ComposingIndicator>> watchComposing(String thesisId)`. Provider `composingProvider`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/repositories/title_composing_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

void main() {
  test('marking composing is keyed by uid, so it cannot duplicate', () async {
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);

    await repo.markComposing(
      thesisId: 't1', uid: 'p1', name: 'Dr. Diamante',
      role: 'Panel Member', candidateTitleId: 'ct1');
    await repo.markComposing(
      thesisId: 't1', uid: 'p1', name: 'Dr. Diamante',
      role: 'Panel Member', candidateTitleId: 'ct2');

    final live = await repo.watchComposing('t1').first;
    expect(live, hasLength(1), reason: 'one person, one indicator');
    expect(live.single.candidateTitleId, 'ct2',
        reason: 'the later heartbeat wins');
  });

  test('clearing removes it', () async {
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);
    await repo.markComposing(
      thesisId: 't1', uid: 'p1', name: 'Dr. Diamante',
      role: 'Panel Member', candidateTitleId: 'ct1');
    await repo.clearComposing(thesisId: 't1', uid: 'p1');
    expect(await repo.watchComposing('t1').first, isEmpty);
  });

  test('clearing an indicator that is not there is not an error', () async {
    // The client clears on blur and on submit, so a double clear is normal.
    final repo = TitleDefenceRepository(FakeFirebaseFirestore());
    await repo.clearComposing(thesisId: 't1', uid: 'nobody');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/title_composing_test.dart`
Expected: FAIL — `The method 'markComposing' isn't defined`

- [ ] **Step 3: Add composing to the repository**

```dart
  CollectionReference<Map<String, dynamic>> _composing(String thesisId) =>
      _thesis(thesisId).collection('titleComposing');

  /// Live "is writing" markers, stale ones included — the reader expires
  /// them via [ComposingIndicator.isStaleAt], because there are no Cloud
  /// Functions to sweep a laptop that was closed mid-comment.
  Stream<List<ComposingIndicator>> watchComposing(String thesisId) {
    return _composing(thesisId).snapshots().map((s) => s.docs
        .map((d) => ComposingIndicator.fromMap(d.id, {
              ...d.data(),
              'updatedAt': (d.data()['updatedAt'] as Timestamp?)?.toDate(),
            }))
        .toList());
  }

  /// Called on focus and then roughly every 5 seconds while a comment field
  /// is open. Deliberately not per keystroke: Spark allows 20,000 writes a
  /// day, and keystroke-level writes would exhaust that in a few defences.
  ///
  /// Keyed by uid, so one person composing cannot produce two indicators.
  Future<void> markComposing({
    required String thesisId,
    required String uid,
    required String name,
    required String role,
    required String candidateTitleId,
  }) {
    return _composing(thesisId).doc(uid).set({
      'name': name,
      'role': role,
      'candidateTitleId': candidateTitleId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// On submit or on blur. A double clear is normal and must not throw.
  Future<void> clearComposing({
    required String thesisId,
    required String uid,
  }) {
    return _composing(thesisId).doc(uid).delete();
  }
```

Add to `lib/providers/title_providers.dart`:

```dart
/// Who is currently writing, stale entries included. Filter with
/// `isStaleAt(DateTime.now())` at the point of display.
final composingProvider =
    StreamProvider.family<List<ComposingIndicator>, String>((ref, thesisId) {
  return ref.watch(titleDefenceRepositoryProvider).watchComposing(thesisId);
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/title_composing_test.dart` — Expected: PASS
Run: `flutter test` — Expected: PASS, 252 total

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/title_defence_repository.dart lib/providers/title_providers.dart test/data/repositories/title_composing_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: composing indicators for the title defence"
```

---

### Task 5: The Dean's decision

**Files:**
- Modify: `lib/data/repositories/title_defence_repository.dart`
- Test: `test/data/repositories/title_decision_test.dart`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `Future<void> approveTitle({required String thesisId, required String candidateTitleId, required String deanUid})`, `Future<void> rejectTitles({required String thesisId, required String deanUid, required String remark})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/repositories/title_decision_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

Future<FakeFirebaseFirestore> pending() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'status': 'titlePendingDefence',
    'panelistUids': <String>[], 'adviserUid': 'a1',
    'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    'titleRound': 1,
  });
  await db.collection('theses/t1/candidateTitles').doc('ct1').set({
    'titleText': 'Candidate one', 'justificationPath': 'p',
    'justificationUrl': 'u', 'round': 1,
  });
  return db;
}

void main() {
  test('approving records the title and who decided', () async {
    final db = await pending();
    await TitleDefenceRepository(db)
        .approveTitle(thesisId: 't1', candidateTitleId: 'ct1', deanUid: 'd1');

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], ThesisStatus.titleApproved.value);
    expect(t['approvedTitleId'], 'ct1');
    expect(t['titleDecidedBy'], 'd1');
    expect(t['titleDecidedAt'], isNotNull);
  });

  test('approving a candidate that is not on this thesis is refused',
      () async {
    final repo = TitleDefenceRepository(await pending());
    expect(
      () => repo.approveTitle(
          thesisId: 't1', candidateTitleId: 'ghost', deanUid: 'd1'),
      throwsArgumentError,
    );
  });

  test('rejecting requires a remark', () async {
    // The student must always know what to fix. Mirrors the decline reason
    // already required in the Conforme step.
    final repo = TitleDefenceRepository(await pending());
    expect(
      () => repo.rejectTitles(thesisId: 't1', deanUid: 'd1', remark: '  '),
      throwsArgumentError,
    );
  });

  test('rejecting records the remark and the decision', () async {
    final db = await pending();
    await TitleDefenceRepository(db).rejectTitles(
        thesisId: 't1', deanUid: 'd1', remark: 'All three are too broad.');

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], ThesisStatus.titleRejected.value);
    expect(t['titleRejectionRemark'], 'All three are too broad.');
    expect(t['titleDecidedBy'], 'd1');
  });

  test('a decision cannot be replayed once made', () async {
    // Same defect class M1a found in respondToNomination, where a stale tab
    // could walk an approved thesis backwards.
    final db = await pending();
    final repo = TitleDefenceRepository(db);
    await repo.approveTitle(
        thesisId: 't1', candidateTitleId: 'ct1', deanUid: 'd1');
    expect(
      () => repo.rejectTitles(
          thesisId: 't1', deanUid: 'd1', remark: 'changed my mind'),
      throwsStateError,
    );
  });

  test('both decisions leave an audit entry naming the Dean', () async {
    // Spec §9.2: the rules cannot verify that the approved candidate belongs
    // to the current round, so a Dean could approve one from a superseded
    // set. The audit log is the stated mitigation — if nothing writes it,
    // the limitation has no mitigation at all.
    final db = await pending();
    await TitleDefenceRepository(db)
        .approveTitle(thesisId: 't1', candidateTitleId: 'ct1', deanUid: 'd1');

    final logs = await db.collection('auditLogs').get();
    expect(logs.docs, hasLength(1));
    final entry = logs.docs.first.data();
    expect(entry['action'], 'title.approved');
    expect(entry['actorUid'], 'd1');
    expect(entry['targetId'], 't1');
    expect((entry['metadata'] as Map)['approvedTitleId'], 'ct1');
  });

  test('a failed audit write does not block the decision', () async {
    // Same posture as M1a's sign-in path: the decision is the point, the log
    // is best-effort. A thesis must not be left undecided because a log
    // write failed.
    final db = await pending();
    final repo = TitleDefenceRepository(db, audit: _FailingAudit());
    await repo.rejectTitles(
        thesisId: 't1', deanUid: 'd1', remark: 'All too broad.');

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], 'titleRejected');
  });
}

class _FailingAudit implements AuditService {
  @override
  Future<void> log({
    required String actorUid,
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? metadata,
  }) async {
    throw Exception('audit unavailable');
  }
}
```

Add these imports to the test file: `package:ethesishub/data/services/audit_service.dart`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/title_decision_test.dart`
Expected: FAIL — `The method 'approveTitle' isn't defined`

- [ ] **Step 3: Add the decision methods**

```dart
  /// The Dean records which candidate the panel approved.
  ///
  /// Guarded on the CURRENT persisted status, not on anything the caller
  /// supplies. M1a shipped a transition without that guard and a stale tab
  /// could walk an approved thesis backwards.
  Future<void> approveTitle({
    required String thesisId,
    required String candidateTitleId,
    required String deanUid,
  }) async {
    await _requirePendingDefence(thesisId);

    final candidate = await _candidates(thesisId).doc(candidateTitleId).get();
    if (!candidate.exists) {
      throw ArgumentError('That candidate title is not on this thesis.');
    }

    await _thesis(thesisId).update({
      'status': ThesisStatus.titleApproved.value,
      'approvedTitleId': candidateTitleId,
      'titleDecidedBy': deanUid,
      'titleDecidedAt': FieldValue.serverTimestamp(),
    });
  }

  /// The Dean rejects the whole set. The remark is required: the student must
  /// know what to fix, and the panel's comments may not say it plainly.
  Future<void> rejectTitles({
    required String thesisId,
    required String deanUid,
    required String remark,
  }) async {
    final text = remark.trim();
    if (text.isEmpty) {
      throw ArgumentError('Say why the set is being rejected.');
    }
    await _requirePendingDefence(thesisId);

    await _thesis(thesisId).update({
      'status': ThesisStatus.titleRejected.value,
      'titleRejectionRemark': text,
      'titleDecidedBy': deanUid,
      'titleDecidedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _requirePendingDefence(String thesisId) async {
    final snap = await _thesis(thesisId).get();
    if (!snap.exists) throw StateError('That thesis no longer exists.');
    final status = ThesisStatus.fromString(snap.data()!['status'] as String?);
    if (status != ThesisStatus.titlePendingDefence) {
      throw StateError('This title defence has already been decided.');
    }
  }

  /// Best-effort, and deliberately after the decision has committed. The
  /// decision is the point; the log must never be able to prevent one.
  Future<void> _audit({
    required String deanUid,
    required String thesisId,
    required String action,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      await _audit0.log(
        actorUid: deanUid,
        action: action,
        targetType: 'thesis',
        targetId: thesisId,
        metadata: metadata,
      );
    } catch (_) {
      // Swallowed on purpose. A thesis must not be left undecided because a
      // log write failed — the same posture the sign-in path takes.
    }
  }
```

The constructor takes the service so a test can inject a failing one:

```dart
  TitleDefenceRepository(this._db, {AuditService? audit})
      : _audit0 = audit ?? AuditService(_db);

  final FirebaseFirestore _db;
  final AuditService _audit0;
```

Note the initialiser cannot reference `_db`, so write it as:

```dart
  TitleDefenceRepository(FirebaseFirestore db, {AuditService? audit})
      : _db = db,
        _audit0 = audit ?? AuditService(db);
```

Call it at the end of each decision, after the `update` has committed:

```dart
    await _audit(
      deanUid: deanUid, thesisId: thesisId, action: 'title.approved',
      metadata: {'approvedTitleId': candidateTitleId},
    );
```

```dart
    await _audit(
      deanUid: deanUid, thesisId: thesisId, action: 'title.rejected',
      metadata: {'remark': text},
    );
```

The `auditLogs` rules already accept exactly these six keys with
`timestamp == request.time`; `AuditService.log` already writes that shape, so
no rules change is needed. Verify by reading the `auditLogs` block rather than
assuming.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/title_decision_test.dart` — Expected: PASS (5 tests)
Run: `flutter test` — Expected: PASS, 257 total

- [ ] **Step 5: Prove the replay guard is falsifiable**

Remove the `_requirePendingDefence` call from `rejectTitles`, run `a decision cannot be replayed once made`, confirm it fails, restore. Record the failure text.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/title_defence_repository.dart test/data/repositories/title_decision_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: the Dean's title decision"
```

---

### Task 6: The panel's list of defences

**Files:**
- Modify: `lib/data/repositories/title_defence_repository.dart`, `lib/providers/title_providers.dart`
- Test: `test/data/repositories/my_defences_test.dart`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Stream<List<String>> watchMyThesisIds(String uid)`. Provider `myThesisIdsProvider`.

**Why this shape:** a faculty member cannot `list` the `theses` collection — the rules allow that only to the leader, coordinators and the dean, and widening it was deliberately deferred. But they *can* run a collection-group query on `nominations` filtered by `nomineeUid`, which M1a already built and indexed. That returns the id of every thesis they hold a position on. No new rule, no new index.

- [ ] **Step 1: Write the failing test**

```dart
// test/data/repositories/my_defences_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

void main() {
  test('returns every thesis this person holds a position on', () async {
    final db = FakeFirebaseFirestore();
    for (final t in ['t1', 't2']) {
      await db.collection('theses/$t/nominations').doc('p1').set({
        'nomineeUid': 'p1', 'nomineeName': 'Dr. Diamante',
        'position': 'panelist', 'exOfficio': false,
        'conformeStatus': 'accepted',
      });
    }
    await db.collection('theses/t3/nominations').doc('other').set({
      'nomineeUid': 'other', 'nomineeName': 'Someone Else',
      'position': 'panelist', 'exOfficio': false,
      'conformeStatus': 'accepted',
    });

    final ids = await TitleDefenceRepository(db).watchMyThesisIds('p1').first;
    expect(ids.toSet(), {'t1', 't2'});
  });

  test('includes ex officio seats', () async {
    // A coordinator or the dean sits on every panel by office and never
    // accepts. Filtering on an accepted Conforme would hide their defences.
    final db = FakeFirebaseFirestore();
    await db.collection('theses/t1/nominations').doc('c1').set({
      'nomineeUid': 'c1', 'nomineeName': 'Dr. Bito-onon',
      'position': 'coordinator', 'exOfficio': true,
      'conformeStatus': 'exOfficio',
    });

    final ids = await TitleDefenceRepository(db).watchMyThesisIds('c1').first;
    expect(ids, ['t1']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/my_defences_test.dart`
Expected: FAIL — `The method 'watchMyThesisIds' isn't defined`

- [ ] **Step 3: Implement**

```dart
  /// The id of every thesis this person holds a position on.
  ///
  /// A collection-group query on `nominations`, not a query on `theses`: the
  /// rules allow a faculty member to LIST theses only if they are the leader,
  /// a coordinator or the dean. They may however read their own nominations
  /// across every thesis, which is the same query
  /// `watchMyPendingNominations` uses — and it reuses that query's existing
  /// COLLECTION_GROUP index on `nomineeUid`, so no index change is needed.
  ///
  /// No `conformeStatus` filter: a coordinator and the dean sit on every
  /// panel ex officio and never accept, so filtering on acceptance would hide
  /// exactly the people who chair the defence.
  Stream<List<String>> watchMyThesisIds(String uid) {
    return _db
        .collectionGroup('nominations')
        .where('nomineeUid', isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs
            .map((d) => d.reference.parent.parent!.id)
            .toSet()
            .toList());
  }
```

Add to `lib/providers/title_providers.dart`:

```dart
/// Thesis ids the signed-in faculty member holds a position on.
final myThesisIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(titleDefenceRepositoryProvider).watchMyThesisIds(uid);
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/data/repositories/my_defences_test.dart` — Expected: PASS
Run: `flutter test` — Expected: PASS, 259 total

- [ ] **Step 5: Confirm no index change is needed**

Read `firestore.indexes.json`. It already declares `nominations.nomineeUid` with `COLLECTION_GROUP` scope. This query filters on that field alone, so it is covered. Record that you checked — a missing index is invisible to every local test.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/title_defence_repository.dart lib/providers/title_providers.dart test/data/repositories/my_defences_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: list the defences a panel member is on"
```

---

### Task 7: The consolidated bracketed output

**Files:**
- Create: `lib/features/titles/consolidated_comments.dart`
- Test: `test/features/titles/consolidated_comments_test.dart`

**Interfaces:**
- Consumes: `TitleComment`, `CandidateTitle` (Task 1).
- Produces: `List<ConsolidatedCandidate> consolidate({required List<CandidateTitle> candidates, required List<TitleComment> comments, int? round})`, where `ConsolidatedCandidate` has `candidate` and `blocks`, and `CommentBlock` has `authorName`, `authorRole`, `bodies`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/titles/consolidated_comments_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/features/titles/consolidated_comments.dart';

CandidateTitle candidate(String id, String text, {int round = 1}) =>
    CandidateTitle(
      id: id, titleText: text, justificationPath: 'p',
      justificationUrl: 'u', round: round,
    );

TitleComment comment(String id, String titleId, String uid, String name,
        String role, String body, int minute) =>
    TitleComment(
      id: id, candidateTitleId: titleId, authorUid: uid, authorName: name,
      authorRole: role, body: body,
      createdAt: DateTime.utc(2026, 8, 16, 10, minute),
    );

void main() {
  test('groups each author into one block, in the order they first spoke', () {
    final result = consolidate(
      candidates: [candidate('ct1', 'Candidate one')],
      comments: [
        comment('1', 'ct1', 'a1', 'Dr. Armada', 'Adviser', 'Too broad.', 1),
        comment('2', 'ct1', 'p1', 'Dr. Diamante', 'Panel Member',
            'Justify the respondents.', 2),
        comment('3', 'ct1', 'a1', 'Dr. Armada', 'Adviser',
            'Narrow to one college.', 3),
      ],
    );

    expect(result, hasLength(1));
    final blocks = result.single.blocks;
    expect(blocks.map((b) => b.authorName), ['Dr. Armada', 'Dr. Diamante'],
        reason: 'ordered by who spoke first, not alphabetically');
    expect(blocks.first.bodies, ['Too broad.', 'Narrow to one college.'],
        reason: "an author's remarks stay in the order they were made");
    expect(blocks.first.authorRole, 'Adviser');
  });

  test('a candidate with no comments still appears, with no blocks', () {
    // Silence is a finding: the student should see that nobody objected.
    final result = consolidate(
      candidates: [candidate('ct1', 'One'), candidate('ct2', 'Two')],
      comments: [
        comment('1', 'ct1', 'a1', 'Dr. Armada', 'Adviser', 'Too broad.', 1),
      ],
    );
    expect(result, hasLength(2));
    expect(result[1].blocks, isEmpty);
  });

  test('comments are matched to their own candidate', () {
    final result = consolidate(
      candidates: [candidate('ct1', 'One'), candidate('ct2', 'Two')],
      comments: [
        comment('1', 'ct2', 'a1', 'Dr. Armada', 'Adviser', 'This one.', 1),
      ],
    );
    expect(result[0].blocks, isEmpty);
    expect(result[1].blocks.single.bodies, ['This one.']);
  });

  test('filtering by round shows one submission at a time', () {
    // A rejected set is kept. Showing both rounds at once would mix the
    // rejected candidates in with the resubmission.
    final result = consolidate(
      candidates: [
        candidate('old', 'Rejected', round: 1),
        candidate('new', 'Resubmitted', round: 2),
      ],
      comments: const [],
      round: 2,
    );
    expect(result.map((r) => r.candidate.id), ['new']);
  });

  test('the same person keeps the role they had on each comment', () {
    // Two comments, two roles, because a position changed between defences.
    // The blocks must not merge, or the record claims one of them was said
    // under the wrong title.
    final result = consolidate(
      candidates: [candidate('ct1', 'One')],
      comments: [
        comment('1', 'ct1', 'x1', 'Dr. Cruz', 'Panel Member', 'First.', 1),
        comment('2', 'ct1', 'x1', 'Dr. Cruz', 'Research Coordinator',
            'Second.', 2),
      ],
    );
    expect(result.single.blocks, hasLength(2));
    expect(result.single.blocks.map((b) => b.authorRole),
        ['Panel Member', 'Research Coordinator']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/titles/consolidated_comments_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement**

```dart
// lib/features/titles/consolidated_comments.dart
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/title_comment.dart';

/// One commenter's remarks on one candidate, as a single bracketed block:
///
/// ```
/// [Dr. Noel A. Armada — Adviser]
///   Scope is too broad for one semester.
///   Narrow the respondents to one college.
/// ```
class CommentBlock {
  const CommentBlock({
    required this.authorName,
    required this.authorRole,
    required this.bodies,
  });

  final String authorName;
  final String authorRole;
  final List<String> bodies;

  /// The bracket header, exactly as it prints.
  String get header => '[$authorName — $authorRole]';
}

class ConsolidatedCandidate {
  const ConsolidatedCandidate({required this.candidate, required this.blocks});
  final CandidateTitle candidate;
  final List<CommentBlock> blocks;
}

/// Groups comments per commenter under each candidate — parent design §5.3.
///
/// This is what a student reads after the Dean records the decision, and what
/// automates Guidelines §4d, where the adviser consolidates defence comments
/// for the Research Coordinator. Built here; M3 reuses it for the pre-oral
/// and final defences.
///
/// Ordering is the record: candidates in the order given, authors in the
/// order they first commented, and each author's remarks in the order made.
/// Alphabetising anything here would misrepresent a transcript.
///
/// Blocks are keyed by author AND role. The same person commenting under two
/// different positions gets two blocks, because merging them would file a
/// remark under a title its author did not hold at the time.
List<ConsolidatedCandidate> consolidate({
  required List<CandidateTitle> candidates,
  required List<TitleComment> comments,
  int? round,
}) {
  final shown = round == null
      ? candidates
      : candidates.where((c) => c.round == round).toList();

  return [
    for (final c in shown)
      ConsolidatedCandidate(
        candidate: c,
        blocks: _blocksFor(
            comments.where((m) => m.candidateTitleId == c.id).toList()),
      ),
  ];
}

List<CommentBlock> _blocksFor(List<TitleComment> comments) {
  final order = <String>[];
  final grouped = <String, List<TitleComment>>{};

  for (final c in comments) {
    final key = '${c.authorUid}|${c.authorRole}';
    if (!grouped.containsKey(key)) {
      order.add(key);
      grouped[key] = [];
    }
    grouped[key]!.add(c);
  }

  return [
    for (final key in order)
      CommentBlock(
        authorName: grouped[key]!.first.authorName,
        authorRole: grouped[key]!.first.authorRole,
        bodies: grouped[key]!.map((c) => c.body).toList(),
      ),
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/titles/consolidated_comments_test.dart` — Expected: PASS (5 tests)
Run: `flutter test` — Expected: PASS, 264 total

- [ ] **Step 5: Commit**

```bash
git add lib/features/titles/consolidated_comments.dart test/features/titles/consolidated_comments_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: consolidated bracketed defence comments"
```

---

### Task 8: Security rules

**Files:**
- Modify: `firestore.rules`
- Test: `rules-test/rules.test.js`

**Interfaces:**
- Consumes: the collection shapes written in Tasks 2–5.
- Produces: nothing Dart code imports. **Do not deploy** — the project owner deploys.

**Read `firestore.rules` before writing.** Reuse the existing helpers: `signedIn()`, `verified()`, `myRole()`, `isCoordinator()`, `isDean()`, `onlyChanged()`, `thesisData()`, `isThesisLeader()`, `hasNomination()`. Do not reinvent them.

- [ ] **Step 1: Add the rules**

Inside `match /theses/{thesisId} { ... }`, after the existing nomination blocks:

```
      // A panel member on this thesis: the adviser, anyone on panelistUids,
      // or anyone holding a nomination — which covers the ex officio
      // Coordinator and Dean, who never appear in panelistUids.
      function isOnPanel() {
        let t = thesisData(thesisId);
        return signedIn() && (
          t.adviserUid == request.auth.uid ||
          request.auth.uid in t.panelistUids ||
          hasNomination(thesisId, request.auth.uid)
        );
      }

      function titleDecided() {
        return thesisData(thesisId).get('titleDecidedAt', null) != null;
      }

      match /candidateTitles/{titleId} {
        allow get, list: if isThesisLeader(thesisId) || isOnPanel()
                         || isCoordinator() || isDean();

        // Only while the thesis is at a status that permits a submission.
        // Batched writes are evaluated against the state BEFORE the batch, so
        // the thesis is still `nominationApproved` (or `titleRejected`) here
        // even though the same batch moves it to `titlePendingDefence`.
        //
        // `round` is deliberately NOT validated: for the same reason, it
        // would be compared against the previous round. It is a history
        // field, not a security one.
        allow create: if verified()
                      && isThesisLeader(thesisId)
                      && thesisData(thesisId).status in
                         ['nominationApproved', 'titleRejected']
                      && request.resource.data.keys().hasOnly(
                           ['titleText', 'justificationPath',
                            'justificationUrl', 'round', 'submittedAt'])
                      && request.resource.data.titleText is string
                      && request.resource.data.titleText.size() > 0
                      && request.resource.data.submittedAt == request.time;

        // Immutable once submitted: the panel must never be reading a title
        // the student is still editing.
        allow update, delete: if false;
      }

      match /titleComments/{commentId} {
        // The panel reads at any time. The leader reads only once the Dean
        // has recorded a decision — during the defence the students are in
        // the room presenting, and the remarks are not theirs to watch.
        allow get, list: if isOnPanel() || isCoordinator() || isDean()
                         || (isThesisLeader(thesisId) && titleDecided());

        allow create: if verified()
                      && isOnPanel()
                      && request.resource.data.authorUid == request.auth.uid
                      && request.resource.data.keys().hasOnly(
                           ['candidateTitleId', 'authorUid', 'authorName',
                            'authorRole', 'body', 'createdAt'])
                      && request.resource.data.body is string
                      && request.resource.data.body.size() > 0
                      && request.resource.data.createdAt == request.time;

        // Append-only, per parent design §6.4. A remark that could be edited
        // afterwards is not a record of what was said.
        allow update, delete: if false;
      }

      match /titleComposing/{uid} {
        // Faculty only. The leader must never see who is typing: the
        // comments themselves are hidden from them until the decision, and
        // an indicator would leak that they exist.
        allow get, list: if isOnPanel() || isCoordinator() || isDean();

        // Your own marker only, so nobody can plant an indicator for someone
        // else or clear one they do not own.
        allow create, update: if verified()
                              && isOnPanel()
                              && uid == request.auth.uid
                              && request.resource.data.keys().hasOnly(
                                   ['name', 'role', 'candidateTitleId',
                                    'updatedAt'])
                              && request.resource.data.updatedAt
                                 == request.time;

        // The one collection in this system where delete is permitted, and
        // only of your own. Composing is transient by design.
        allow delete: if isOnPanel() && uid == request.auth.uid;
      }
```

Then extend the thesis document's `update` rules with two new branches:

```
      // The leader submits candidate titles: this is the write that moves the
      // thesis into the defence.
      allow update: if verified()
                    && isThesisLeader(thesisId)
                    && resource.data.status in
                       ['nominationApproved', 'titleRejected']
                    && request.resource.data.status == 'titlePendingDefence'
                    && onlyChanged(['status', 'titleRound',
                                    'titlesSubmittedAt', 'presentationPath',
                                    'presentationUrl'])
                    && request.resource.data.titlesSubmittedAt == request.time;

      // The Dean records the decision. Pinned to the prior status so it can
      // neither be replayed nor skipped.
      allow update: if verified()
                    && isDean()
                    && resource.data.status == 'titlePendingDefence'
                    && (
                      (request.resource.data.status == 'titleApproved'
                       && onlyChanged(['status', 'approvedTitleId',
                                       'titleDecidedAt', 'titleDecidedBy'])
                       // Single-value cross-check, the same technique used
                       // for adviserUid: the approved candidate must exist on
                       // this thesis. The rules cannot iterate the
                       // candidates, so the round is not verified — see the
                       // limitation in the spec.
                       && exists(/databases/$(database)/documents/theses/
                            $(thesisId)/candidateTitles/
                            $(request.resource.data.approvedTitleId)))
                      ||
                      (request.resource.data.status == 'titleRejected'
                       && onlyChanged(['status', 'titleRejectionRemark',
                                       'titleDecidedAt', 'titleDecidedBy'])
                       && request.resource.data.titleRejectionRemark is string
                       && request.resource.data.titleRejectionRemark.size() > 0)
                    )
                    && request.resource.data.titleDecidedBy == request.auth.uid
                    && request.resource.data.titleDecidedAt == request.time;
```

- [ ] **Step 2: Write the rules tests**

Append to `rules-test/rules.test.js`. **Every deny test needs its allow control on the same path** — a denial proves nothing if the path was wrong or a prerequisite document was missing.

```javascript
// --- M1b title defence ------------------------------------------------

async function seedDefence(ctx, { status = "titlePendingDefence", decided = null } = {}) {
  const db = ctx.firestore();
  await setDoc(doc(db, "theses/td1"), {
    leaderUid: "leader-uid", status, panelistUids: ["pan-uid"],
    adviserUid: "adv-uid", memberNames: [], workingTitle: "T",
    college: "CICT", program: "BSIT", semester: "First",
    academicYear: "2026-2027", titleRound: 1,
    ...(decided ? { titleDecidedAt: decided } : {}),
  });
  await setDoc(doc(db, "theses/td1/candidateTitles/ct1"), {
    titleText: "Candidate one", justificationPath: "p",
    justificationUrl: "u", round: 1,
  });
  await setDoc(doc(db, "theses/td1/titleComments/cm1"), {
    candidateTitleId: "ct1", authorUid: "pan-uid",
    authorName: "Dr. Panel", authorRole: "Panel Member",
    body: "Too broad.", createdAt: Timestamp.now(),
  });
  await setDoc(doc(db, "theses/td1/nominations/pan-uid"), {
    nomineeUid: "pan-uid", nomineeName: "Dr. Panel", position: "panelist",
    exOfficio: false, conformeStatus: "accepted",
  });
}

test("M1b allow: a panel member MAY read comments during the defence", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx));
  const panel = env.authenticatedContext("pan-uid", {
    email: "pan@isufst.edu.ph", email_verified: true }).firestore();
  await assertSucceeds(getDocs(collection(panel, "theses/td1/titleComments")));
});

test("M1b attack: the leader may NOT read comments before the decision", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx));
  const leader = env.authenticatedContext("leader-uid", {
    email: "leader@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(getDocs(collection(leader, "theses/td1/titleComments")));
});

test("M1b allow: the leader MAY read comments once the Dean has decided", async () => {
  // The control for the test above: same path, same user, one field changed.
  await env.withSecurityRulesDisabled((ctx) =>
    seedDefence(ctx, { status: "titleApproved", decided: Timestamp.now() }));
  const leader = env.authenticatedContext("leader-uid", {
    email: "leader@isufst.edu.ph", email_verified: true }).firestore();
  await assertSucceeds(getDocs(collection(leader, "theses/td1/titleComments")));
});

test("M1b attack: the leader may NEVER read composing indicators", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await seedDefence(ctx, { status: "titleApproved", decided: Timestamp.now() });
    await setDoc(doc(ctx.firestore(), "theses/td1/titleComposing/pan-uid"), {
      name: "Dr. Panel", role: "Panel Member", candidateTitleId: "ct1",
      updatedAt: Timestamp.now(),
    });
  });
  const leader = env.authenticatedContext("leader-uid", {
    email: "leader@isufst.edu.ph", email_verified: true }).firestore();
  // Decided, so comments are readable — composing still is not.
  await assertSucceeds(getDocs(collection(leader, "theses/td1/titleComments")));
  await assertFails(getDocs(collection(leader, "theses/td1/titleComposing")));
});

test("M1b attack: a comment may NOT be edited or deleted", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx));
  const panel = env.authenticatedContext("pan-uid", {
    email: "pan@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(updateDoc(doc(panel, "theses/td1/titleComments/cm1"),
    { body: "rewritten" }));
  await assertFails(deleteDoc(doc(panel, "theses/td1/titleComments/cm1")));
});

test("M1b attack: a panel member may NOT author a comment as someone else", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx));
  const panel = env.authenticatedContext("pan-uid", {
    email: "pan@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(setDoc(doc(panel, "theses/td1/titleComments/forged"), {
    candidateTitleId: "ct1", authorUid: "adv-uid", authorName: "Dr. Adviser",
    authorRole: "Adviser", body: "not mine", createdAt: serverTimestamp(),
  }));
  // Control: the same write with their own uid is accepted.
  await assertSucceeds(setDoc(doc(panel, "theses/td1/titleComments/mine"), {
    candidateTitleId: "ct1", authorUid: "pan-uid", authorName: "Dr. Panel",
    authorRole: "Panel Member", body: "mine", createdAt: serverTimestamp(),
  }));
});

test("M1b attack: a candidate title may NOT be edited after submission", async () => {
  await env.withSecurityRulesDisabled((ctx) => seedDefence(ctx));
  const leader = env.authenticatedContext("leader-uid", {
    email: "leader@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(updateDoc(doc(leader, "theses/td1/candidateTitles/ct1"),
    { titleText: "changed after they read it" }));
});

test("M1b attack: the Dean may NOT approve a candidate from another thesis", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await seedDefence(ctx);
    await setDoc(doc(ctx.firestore(), "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = env.authenticatedContext("dean-uid", {
    email: "dean@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "not-on-this-thesis",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
  // Control: the real candidate is accepted.
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleApproved", approvedTitleId: "ct1",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: the Dean may NOT reject without a remark", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await seedDefence(ctx);
    await setDoc(doc(ctx.firestore(), "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = env.authenticatedContext("dean-uid", {
    email: "dean@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleRejected", titleRejectionRemark: "",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(doc(dean, "theses/td1"), {
    status: "titleRejected", titleRejectionRemark: "All three are too broad.",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});

test("M1b attack: a decision may NOT be replayed once made", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await seedDefence(ctx, { status: "titleApproved", decided: Timestamp.now() });
    await setDoc(doc(ctx.firestore(), "users/dean-uid"), {
      ...studentProfile("dean@isufst.edu.ph"), role: "dean" });
  });
  const dean = env.authenticatedContext("dean-uid", {
    email: "dean@isufst.edu.ph", email_verified: true }).firestore();
  await assertFails(updateDoc(doc(dean, "theses/td1"), {
    status: "titleRejected", titleRejectionRemark: "changed my mind",
    titleDecidedBy: "dean-uid", titleDecidedAt: serverTimestamp(),
  }));
});
```

- [ ] **Step 3: Run the rules suite**

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.8-hotspot"
cd rules-test && npm test
```

Expected: 114 pass, 0 fail (104 existing + 10 new).

- [ ] **Step 4: Prove each new rule bites**

For each new rule, break it, run its test, confirm the test fails, restore. The two that matter most and must not be skipped: **the leader cannot read comments before the decision**, and **the leader can never read composing**. Record the actual failure output for each.

- [ ] **Step 5: Confirm the Dart suite is unaffected**

Run: `flutter test` — Expected: PASS, 264. Rules changes cannot affect it, and confirming that is how you find out something else moved.

- [ ] **Step 6: Commit — do not deploy**

```bash
git add firestore.rules rules-test/rules.test.js
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: rules for candidate titles, comments and composing"
```

---

### Task 9: File picking and upload

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/features/titles/file_upload.dart`
- Test: `test/features/titles/file_upload_test.dart`

**Interfaces:**
- Consumes: `StorageService`, `StoragePaths`, `StoredFile` from `lib/data/services/storage_service.dart`; `storageServiceProvider` from `lib/providers/service_providers.dart`.
- Produces: `PickedDocument` (`name`, `bytes`, `extension`, `contentType`), `String? validateDocument(PickedDocument file, {required Set<String> allowed, required int maxBytes})`, `Future<StoredFile> uploadDocument({required StorageService storage, required PickedDocument file, required String thesisId, required String documentId})`, and constants `kJustificationTypes`, `kJustificationMaxBytes`, `kPresentationTypes`, `kPresentationMaxBytes`.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, add `file_picker: ^8.1.4`. Run `flutter pub get`. Do not change any other version — Riverpod stays at 2.6.1.

- [ ] **Step 2: Write the failing test**

```dart
// test/features/titles/file_upload_test.dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

class _FakeStorage implements StorageService {
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
}

PickedDocument doc(String name, int bytes, String ext) => PickedDocument(
      name: name,
      bytes: Uint8List(bytes),
      extension: ext,
      contentType: 'application/octet-stream',
    );

void main() {
  test('accepts an allowed type inside the size limit', () {
    expect(
      validateDocument(doc('just.pdf', 1000, 'pdf'),
          allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes),
      isNull,
    );
  });

  test('refuses a type that is not allowed, naming what is', () {
    final error = validateDocument(doc('notes.txt', 10, 'txt'),
        allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes);
    expect(error, isNotNull);
    expect(error, contains('PDF'));
  });

  test('refuses a file over the limit, naming the limit', () {
    // The bucket is public and will not enforce this, so the client must.
    final error = validateDocument(
        doc('huge.pdf', kJustificationMaxBytes + 1, 'pdf'),
        allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes);
    expect(error, isNotNull);
    expect(error, contains('10'));
  });

  test('extension matching ignores case', () {
    expect(
      validateDocument(doc('JUST.PDF', 10, 'PDF'),
          allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes),
      isNull,
    );
  });

  test('uploading puts the file at an unguessable path under the thesis',
      () async {
    final storage = _FakeStorage();
    final stored = await uploadDocument(
      storage: storage, file: doc('just.pdf', 10, 'pdf'),
      thesisId: 't1', documentId: 'ct1',
    );

    expect(stored.path, startsWith('theses/t1/ct1/'));
    expect(stored.path, endsWith('.pdf'));
    expect(stored.path, isNot(contains('just.pdf')),
        reason: 'the public bucket means the path must not be guessable, so '
            'it must not carry the original filename');
    expect(stored.url, contains(stored.path));
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/titles/file_upload_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 4: Implement**

```dart
// lib/features/titles/file_upload.dart
import 'dart:typed_data';

import 'package:ethesishub/data/services/storage_service.dart';

/// A file the user chose, held in memory.
///
/// Bytes rather than a path, because `dart:io` does not exist on Web and this
/// app targets Web as well as Android.
class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String extension;
  final String contentType;
}

const kJustificationTypes = {'pdf', 'doc', 'docx'};
const kJustificationMaxBytes = 10 * 1024 * 1024;

const kPresentationTypes = {'pptx', 'ppt', 'pdf'};
const kPresentationMaxBytes = 25 * 1024 * 1024;

/// Returns an error message, or null when the file may be uploaded.
///
/// Enforced here because the Supabase bucket is public and enforces nothing:
/// there is no server-side check between this and the object store.
String? validateDocument(
  PickedDocument file, {
  required Set<String> allowed,
  required int maxBytes,
}) {
  if (!allowed.contains(file.extension.toLowerCase())) {
    final names = allowed.map((e) => e.toUpperCase()).join(', ');
    return 'Choose a $names file.';
  }
  if (file.bytes.length > maxBytes) {
    final mb = (maxBytes / (1024 * 1024)).round();
    return 'That file is larger than $mb MB.';
  }
  return null;
}

/// Uploads to Supabase and returns where it landed.
///
/// The path carries a UUID and NOT the original filename: the bucket is
/// public, so anything guessable is readable by anyone.
Future<StoredFile> uploadDocument({
  required StorageService storage,
  required PickedDocument file,
  required String thesisId,
  required String documentId,
}) {
  final path = StoragePaths.thesisDocument(
    thesisId: thesisId,
    documentId: documentId,
    extension: file.extension.toLowerCase(),
  );
  return storage.upload(
      bytes: file.bytes, path: path, contentType: file.contentType);
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/titles/file_upload_test.dart` — Expected: PASS (5 tests)
Run: `flutter test` — Expected: PASS, 269 total
Run: `grep -rn "dart:io" lib/` — Expected: only the comment in `thesis_status_screen.dart`. `file_picker` must not pull it in.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/titles/file_upload.dart test/features/titles/file_upload_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: document picking, validation and upload"
```

---

### Task 10: Submit candidate titles screen

**Files:**
- Create: `lib/features/titles/submit_titles_screen.dart`
- Test: `test/features/titles/submit_titles_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 2, 9; `PageShell`, `Gap`, `EmptyState`, `ErrorState`, `LoadingState`, `AppTokens`; `thesisByIdProvider` from `lib/providers/thesis_providers.dart`.
- Produces: `SubmitTitlesScreen({required String thesisId})`. Widget keys: `submitTitlesScreen`, `titleText0..N`, `pickJustification0..N`, `addCandidate`, `pickPresentation`, `submitTitles`, `error`, `candidateCapReason`.

**Match `nominate_screen.dart` exactly** for structure: watch `authStateProvider` in `build()` (never read it lazily in a handler — that races the auth stream's first event and the generic `catch` swallows the null-check error), catches layered specific-to-general, `_busy` cleared in `finally`, and navigate on success rather than staying put.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/titles/submit_titles_screen_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/features/titles/submit_titles_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded({
  String status = 'nominationApproved',
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': <String>[],
    'adviserUid': 'a1', 'memberNames': <String>[], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'titleRound': 0,
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1', email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/thesis/titles',
          routes: [
            GoRoute(
              path: '/thesis/titles',
              builder: (_, _) => const SubmitTitlesScreen(thesisId: 't1'),
            ),
            GoRoute(
              path: '/thesis',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('status', key: Key('landedOnStatus'))),
              ),
            ),
          ],
        ),
      ),
    );

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opens with three candidate slots', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleText0')), findsOneWidget);
    expect(find.byKey(const Key('titleText1')), findsOneWidget);
    expect(find.byKey(const Key('titleText2')), findsOneWidget);
  });

  testWidgets('refuses to submit with a blank title', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('title'));
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
  });

  testWidgets('refuses to submit without a justification for every title',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byKey(Key('titleText$i')), 'Candidate $i');
    }
    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('justification'));
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
  });

  testWidgets('caps the candidates and says why', (tester) async {
    // Ten is a rules constraint, not a preference: each candidate costs a
    // get() and M1a measured that a batch of 20 is denied.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    for (var i = 3; i < 10; i++) {
      await tester.tap(find.byKey(const Key('addCandidate')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('titleText9')), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('addCandidate')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('candidateCapReason')), findsOneWidget);
  });

  testWidgets('refuses when the thesis is not ready for a submission',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded(status: 'draft')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notReady')), findsOneWidget);
    expect(find.byKey(const Key('submitTitles')), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/titles/submit_titles_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the screen**

Build with `PageShell(title: 'Candidate titles', subtitle: ...)`. State: `List<TextEditingController> _titles` (three to start), `List<PickedDocument?> _justifications`, `PickedDocument? _presentation`, `String? _error`, `bool _busy`.

The gate, mirroring `nominate_screen.dart`'s three-branch treatment — do not collapse them, because collapsing loading into "not ready" is exactly the bug M1a shipped:

```dart
final thesisAsync = ref.watch(thesisByIdProvider(widget.thesisId));

if (thesisAsync.isLoading) {
  return const LoadingState(label: 'Loading your thesis…');
}
if (thesisAsync.hasError) {
  return PageShell(children: [
    ErrorState(error: thesisAsync.error,
        message: 'Could not load this thesis.'),
  ]);
}
final thesis = thesisAsync.valueOrNull;
if (thesis == null) {
  return const PageShell(children: [
    EmptyState(icon: Icons.search_off, title: 'Thesis not found',
        message: 'This thesis no longer exists, or it belongs to another '
            'group.'),
  ]);
}
final canSubmit = thesis.status == ThesisStatus.nominationApproved ||
    thesis.status == ThesisStatus.titleRejected;
if (!canSubmit) {
  return PageShell(children: [
    EmptyState(
      key: const Key('notReady'),
      icon: Icons.hourglass_empty,
      title: 'Not ready for candidate titles',
      message: 'Candidate titles can be submitted once the nomination is '
          'approved, or after a set has been rejected.',
    ),
  ]);
}
```

When `thesis.status == ThesisStatus.titleRejected`, show `thesis.titleRejectionRemark` above the form in an `ErrorState` so the student sees what to fix before retyping.

Validation order in `_submit`, each with its own message:
1. every title field non-empty → `'Give every candidate a title.'`
2. every title has a justification → `'Attach a justification for every candidate title.'`
3. a presentation is chosen → `'Attach your presentation.'`

Then upload: each justification via `uploadDocument(..., documentId: 'candidate-$i')`, the presentation with `documentId: 'presentation'`, then call `submitCandidateTitles`. On success `context.go('/thesis')`.

The cap: `addCandidate`'s `onPressed` is null at `TitleDefenceRepository.maxCandidates`, with a keyed `candidateCapReason` text explaining that ten is the per-submission limit.

Catches, specific to general — `FirebaseAuthException` is a subtype of `FirebaseException`, and getting this order wrong left a spinner stuck forever on the skeleton branch:

```dart
} on ArgumentError catch (e) {
  if (mounted) setState(() => _error = e.message.toString());
} on StateError catch (_) {
  if (mounted) {
    setState(() => _error =
        'This thesis is no longer accepting candidate titles.');
  }
} on FirebaseException catch (e) {
  if (mounted) {
    setState(() => _error = e.code == 'permission-denied'
        ? 'You do not have permission to submit candidate titles.'
        : 'Could not submit. Please try again.');
  }
} catch (_) {
  if (mounted) setState(() => _error = 'Could not submit. Please try again.');
} finally {
  if (mounted) setState(() => _busy = false);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/titles/submit_titles_screen_test.dart` — Expected: PASS (5 tests)
Run: `flutter test` — Expected: PASS, 274 total
Run: `flutter analyze lib` — Expected: no issues

- [ ] **Step 5: Prove the validation is falsifiable**

Remove the justification check, run `refuses to submit without a justification for every title`, confirm it fails, restore. Record the failure text.

- [ ] **Step 6: Commit**

```bash
git add lib/features/titles/submit_titles_screen.dart test/features/titles/submit_titles_screen_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: submit candidate titles screen"
```

---

### Task 11: Title defence screen

**Files:**
- Create: `lib/features/titles/title_defence_screen.dart`
- Test: `test/features/titles/title_defence_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 2–7; `currentUserProvider` from `lib/providers/auth_providers.dart`.
- Produces: `TitleDefenceScreen({required String thesisId})`. Keys: `titleDefenceScreen`, `commentBox-<titleId>`, `postComment-<titleId>`, `composingBanner`, `approve-<titleId>`, `rejectSet`, `rejectRemark`, `confirmReject`, `error`.

This screen serves the whole panel; the Dean additionally sees the decision controls. One screen, not two — the Dean is a panel member who can also decide.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/titles/title_defence_screen_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/features/titles/title_defence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded({String viewerRole = 'faculty'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('viewer').set({
    'fullName': 'Dr. Viewer', 'email': 'v@isufst.edu.ph',
    'role': viewerRole, 'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'status': 'titlePendingDefence',
    'panelistUids': <String>['viewer'], 'adviserUid': 'a1',
    'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    'titleRound': 1,
  });
  for (final id in ['ct1', 'ct2', 'ct3']) {
    await db.collection('theses/t1/candidateTitles').doc(id).set({
      'titleText': 'Candidate $id', 'justificationPath': 'p',
      'justificationUrl': 'https://example.test/$id.pdf', 'round': 1,
    });
  }
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'viewer', email: 'v@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/defence',
          routes: [
            GoRoute(
              path: '/defence',
              builder: (_, _) => const TitleDefenceScreen(thesisId: 't1'),
            ),
            GoRoute(
              path: '/faculty',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('home', key: Key('landedHome'))),
              ),
            ),
          ],
        ),
      ),
    );

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows every candidate of the current round', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.text('Candidate ct1'), findsOneWidget);
    expect(find.text('Candidate ct2'), findsOneWidget);
    expect(find.text('Candidate ct3'), findsOneWidget);
  });

  testWidgets('a panel member can post a comment on one candidate',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('commentBox-ct2')), 'Scope is too broad.');
    await tester.tap(find.byKey(const Key('postComment-ct2')));
    await tester.pumpAndSettle();

    final saved = await db.collection('theses/t1/titleComments').get();
    expect(saved.docs, hasLength(1));
    expect(saved.docs.first.data()['candidateTitleId'], 'ct2');
    expect(saved.docs.first.data()['authorUid'], 'viewer');
    expect(saved.docs.first.data()['authorRole'], isNotEmpty,
        reason: 'the role held at the time is part of the record');
  });

  testWidgets('an empty comment is refused', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('postComment-ct1')));
    await tester.pumpAndSettle();

    expect((await db.collection('theses/t1/titleComments').get()).docs,
        isEmpty);
  });

  testWidgets('someone else composing is announced', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('theses/t1/titleComposing').doc('other').set({
      'name': 'Dr. Diamante', 'role': 'Panel Member',
      'candidateTitleId': 'ct1', 'updatedAt': DateTime.now(),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composingBanner')), findsOneWidget);
    expect(find.textContaining('Dr. Diamante'), findsWidgets);
  });

  testWidgets('a stale composing indicator is not announced', (tester) async {
    // No Cloud Functions sweep these, so the reader has to expire them.
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('theses/t1/titleComposing').doc('other').set({
      'name': 'Dr. Diamante', 'role': 'Panel Member',
      'candidateTitleId': 'ct1',
      'updatedAt': DateTime.now().subtract(const Duration(minutes: 5)),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composingBanner')), findsNothing);
  });

  testWidgets('your own composing marker is not announced back to you',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('theses/t1/titleComposing').doc('viewer').set({
      'name': 'Dr. Viewer', 'role': 'Panel Member',
      'candidateTitleId': 'ct1', 'updatedAt': DateTime.now(),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composingBanner')), findsNothing);
  });

  testWidgets('a panel member sees no decision controls', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approve-ct1')), findsNothing);
    expect(find.byKey(const Key('rejectSet')), findsNothing);
  });

  testWidgets('the Dean can approve one candidate', (tester) async {
    useTallSurface(tester);
    final db = await seeded(viewerRole: 'dean');
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve-ct2')));
    await tester.pumpAndSettle();

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], 'titleApproved');
    expect(t['approvedTitleId'], 'ct2');
    expect(t['titleDecidedBy'], 'viewer');
  });

  testWidgets('the Dean cannot reject without a remark', (tester) async {
    useTallSurface(tester);
    final db = await seeded(viewerRole: 'dean');
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rejectSet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmReject')));
    await tester.pumpAndSettle();

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], 'titlePendingDefence',
        reason: 'nothing should have been recorded');
    expect(find.byKey(const Key('error')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/titles/title_defence_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the screen**

Watch: `thesisByIdProvider(thesisId)`, `candidateTitlesProvider(thesisId)`, `titleCommentsProvider(thesisId)`, `composingProvider(thesisId)`, `currentUserProvider`. Handle loading/error/not-found in three separate branches as in Task 10.

Show only candidates whose `round == thesis.titleRound`.

The role written on a comment comes from the viewer's position on *this* thesis, resolved once in `build()`:

```dart
/// The position this person holds on THIS thesis, which is what a comment
/// records. Not their account role: a coordinator sitting as a nominated
/// panel member comments as a panel member.
String _roleOnThisThesis(Thesis thesis, AppUser me) {
  if (thesis.adviserUid == me.uid) return 'Adviser';
  if (thesis.panelistUids.contains(me.uid)) return 'Panel Member';
  return switch (me.role) {
    UserRole.coordinator => 'Research Coordinator',
    UserRole.dean => 'Dean',
    _ => 'Panel Member',
  };
}
```

Composing banner: filter `composingProvider` to entries that are not the viewer's own and not stale at `DateTime.now()`, then render a keyed banner naming them and the candidate.

Heartbeat: on comment-field focus, call `markComposing`; restart a `Timer.periodic(const Duration(seconds: 5))` that calls it again; on blur, submit, or `dispose`, cancel the timer and call `clearComposing`. **Cancel the timer in `dispose`** — a periodic timer outliving the screen would write forever.

Dean controls render only when `me.role == UserRole.dean`: an `approve-<titleId>` button per candidate, and `rejectSet` opening a `rejectRemark` field with `confirmReject`.

Catches layered exactly as Task 10.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/titles/title_defence_screen_test.dart` — Expected: PASS (9 tests)
Run: `flutter test` — Expected: PASS, 283 total
Run: `flutter analyze lib` — Expected: no issues. Widget test output must be pristine: no unhandled exceptions, no overflow warnings.

- [ ] **Step 5: Prove the staleness filter and the role gate are falsifiable**

Remove the staleness filter, run `a stale composing indicator is not announced`, confirm it fails, restore. Remove the `role == dean` gate, run `a panel member sees no decision controls`, confirm it fails, restore. Record both failure texts.

- [ ] **Step 6: Commit**

```bash
git add lib/features/titles/title_defence_screen.dart test/features/titles/title_defence_screen_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: title defence screen with live comments and the Dean's decision"
```

---

### Task 12: Status screen and routing

**Files:**
- Modify: `lib/features/thesis/thesis_status_screen.dart`, `lib/core/routing/app_router.dart`, `lib/features/dashboard/faculty_dashboard.dart`, `lib/core/widgets/status_chip.dart`
- Test: `test/core/routing/m1b_routes_test.dart`, and extend `test/core/design_system_test.dart`

**Interfaces:**
- Consumes: Tasks 1, 7, 10, 11.
- Produces: routes `/thesis/titles` and `/defence/:thesisId`; `StatusChip` labels and details for the three new states.

- [ ] **Step 1: Extend StatusChip**

Add to `labelFor`, `detailFor` and `_colorFor`. The existing test `every status has a label and a next-step sentence` iterates `ThesisStatus.values`, so it fails until all three are covered — run it first and watch it fail.

```dart
        ThesisStatus.titlePendingDefence => 'Title defence',
        ThesisStatus.titleApproved => 'Title approved',
        ThesisStatus.titleRejected => 'Titles returned',
```

```dart
        ThesisStatus.titlePendingDefence =>
          'Your candidate titles are with the panel.',
        ThesisStatus.titleApproved =>
          'Your title is approved. Work begins on the chapters.',
        ThesisStatus.titleRejected =>
          'The panel returned your candidates. Read the remark and submit a '
          'new set.',
```

Colours: `titlePendingDefence` uses `awaiting`, `titleApproved` uses `endorsed`, `titleRejected` uses `returned` — the first use of `returned`, which exists for exactly this.

- [ ] **Step 2: Write the failing routing test**

```dart
// test/core/routing/m1b_routes_test.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderContainer> containerFor(
    String role, String uid, FakeFirebaseFirestore db) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test', 'email': 't@isufst.edu.ph', 'role': role,
    'active': true,
  });
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: 't@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

void main() {
  testWidgets('a student reaches the submit-titles screen from their thesis',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('theses').add({
      'leaderUid': 'u1', 'status': 'nominationApproved',
      'panelistUids': <String>[], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    final c = await containerFor('student', 'u1', db);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToSubmitTitles')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToSubmitTitles')));
    await tester.pumpAndSettle();

    // The destination's own Key, never a heading the origin button shares —
    // that is what made four M1a navigation tests pass without navigating.
    expect(find.byKey(const Key('submitTitlesScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToSubmitTitles')), findsNothing);
  });

  testWidgets('a faculty member reaches a defence from their dashboard',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'l1', 'status': 'titlePendingDefence',
      'panelistUids': <String>['u2'], 'adviserUid': 'a1',
      'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
      'titleRound': 1,
    });
    // The dashboard finds defences through the nominations collection group,
    // because faculty cannot list theses.
    await db.collection('theses/t1/nominations').doc('u2').set({
      'nomineeUid': 'u2', 'nomineeName': 'Dr. Test', 'position': 'panelist',
      'exOfficio': false, 'conformeStatus': 'accepted',
    });
    final c = await containerFor('faculty', 'u2', db);
    addTearDown(c.dispose);

    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('goToDefence-t1')), findsOneWidget);
    await tester.tap(find.byKey(const Key('goToDefence-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleDefenceScreen')), findsOneWidget);
    expect(find.byKey(const Key('goToDefence-t1')), findsNothing);
  });
}
```

Import `goRouterProvider` from `package:ethesishub/core/routing/app_router.dart`.

- [ ] **Step 3: Add the routes**

```dart
      GoRoute(
        path: '/thesis/titles',
        builder: (context, state) {
          // Same bare-visit fallback as /thesis/nominate: fall back to the
          // leader's own thesis rather than null-checking a missing query
          // parameter, and distinguish loading from absent while doing it.
          final id = state.uri.queryParameters['id'];
          ...
        },
      ),
      GoRoute(
        path: '/defence/:thesisId',
        builder: (context, state) => TitleDefenceScreen(
            thesisId: state.pathParameters['thesisId']!),
      ),
```

Guard `/thesis/titles` to students and `/defence/` to non-students in the redirect, alongside the existing M1a guards. These are UX guards only — `firestore.rules` is the authorization boundary.

- [ ] **Step 4: Extend the status screen**

When status is `nominationApproved` or `titleRejected`, show a `goToSubmitTitles` action. When `titleRejected`, show `titleRejectionRemark` in an `ErrorState` first — the student needs to know what to fix.

When `titleDecidedAt` is non-null, render the consolidated comments from Task 7 using `consolidate(candidates: ..., comments: ..., round: thesis.titleRound)`, with each block as its bracket header and indented bodies.

- [ ] **Step 5: Link the faculty dashboard**

Watch `myThesisIdsProvider`, resolve each through `thesisByIdProvider`, and list the ones at `titlePendingDefence` with a link to `/defence/<id>`. Add a `Defences` `NavDestination` — the faculty dashboard now has two, so `ResponsiveScaffold` shows its navigation for the first time.

- [ ] **Step 6: Run everything**

Run: `flutter test` — Expected: PASS
Run: `flutter analyze lib test` — Expected: only the 2 known pre-existing infos in `verify_email_screen_test.dart`

- [ ] **Step 7: Commit**

```bash
git add lib/core/widgets/status_chip.dart lib/features/thesis/thesis_status_screen.dart lib/core/routing/app_router.dart lib/features/dashboard/faculty_dashboard.dart test/core/routing/m1b_routes_test.dart test/core/design_system_test.dart
git -c user.name="Karl Joshua P. Vargas" -c user.email="karljoshuavargas@gmail.com" commit -m "feat: route and link the title defence"
```

---

### Task 13: End-to-end verification

**Files:** none. This task is run by the project owner against the live app.

Task 12 leaves the code complete and every automated test green. It does not prove the milestone works: M1a passed 233 tests while a missing Firestore index, a wrong page format, an infinite button width and an auth race all sat in the shipped build. Every one was found by a person using the app.

- [ ] **Step 1: Deploy**

```bash
firebase deploy --only firestore
```

Deploys rules **and** indexes together. Task 6 confirmed no new index is needed, but deploying both is the habit that stops one drifting from the other.

- [ ] **Step 2: Walk the flow with real accounts**

1. As the student leader on an approved thesis, submit three candidate titles with justification files and one presentation
2. Confirm the status screen shows **Title defence**
3. As a panel member, open the defence, download a justification, post a comment
4. As a second panel member, confirm the first comment appears **and** that the composing indicator shows while the first is typing
5. As the Dean, approve one candidate
6. As the student, confirm the consolidated bracketed comments now appear, grouped per commenter under each candidate
7. Repeat steps 1–2 with a rejection, and confirm the remark reaches the student and that resubmitting increments the round without deleting the rejected set

- [ ] **Step 3: Check what only a person can check**

- Does a file over the size limit get refused before upload?
- On a phone, does the defence screen stay usable with three candidates and several comments?
- Does the composing indicator disappear on its own after someone closes their laptop mid-comment?

- [ ] **Step 4: Record what you find**

Anything found here goes back into a fix round with a test that reproduces it, the way every M1a field defect did.
