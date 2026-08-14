# M1a — Group Creation and Nomination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A student creates a thesis group, nominates an adviser and three or more panel members, each accepts in-app, the coordinator recommends, the dean approves, and the student downloads a completed Form 1.

**Architecture:** New `theses` collection with a `nominations` subcollection keyed by nominee uid, plus a `facultyDirectory` collection that exposes faculty names without their emails. All authorization lives in Firestore rules; the faculty inbox uses a collection-group query. Form 1 is generated client-side with the `pdf` package.

**Tech Stack:** Flutter 3.44.2 · Riverpod 2.6.1 (pinned) · Firebase Auth / Firestore (Spark plan) · `pdf` + `printing` · fake_cloud_firestore + firebase_auth_mocks (tests) · Firebase Emulator + @firebase/rules-unit-testing (rules tests)

**Spec:** `docs/superpowers/specs/2026-08-14-m1-nomination-design.md`

## Global Constraints

- Flutter 3.44.2, Dart `^3.12.2`. Targets **Android and Web only** — `dart:io` must never be imported in `lib/`
- **Riverpod pinned at 2.6.1.** Do not upgrade
- Firebase **Spark plan**: no Cloud Functions, no server-side triggers
- Models in `lib/data/models/` are **pure Dart** — no Firebase imports. `Timestamp`↔`DateTime` conversion happens in repositories
- Account roles: `student`, `faculty`, `coordinator`, `dean`
- **Students choose only `faculty`.** Dean and coordinators are ex officio — never in the picker, never asked to accept
- **Minimum three panel members, no maximum**
- `academicYear` format is `YYYY-YYYY`
- `AuditService.log` writes **exactly** six keys — `actorUid, action, targetType, targetId, metadata, timestamp` — with `FieldValue.serverTimestamp()`. Any extra key breaks every audit write under the deployed `hasOnly` rule
- Rules tests require **Java 21**: `export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.8-hotspot"`
- Every `setState` and `BuildContext` use after an `await` must be `mounted`-guarded; dispose every `TextEditingController`

**Exit criteria:** a student creates a group, nominates 1 adviser + 3 faculty, three faculty accept in-app, a coordinator recommends, a dean approves, and Form 1 downloads showing the full panel including ex officio members.

---

## File Structure

**Created in `lib/`:**

| File | Responsibility |
|---|---|
| `data/models/thesis_status.dart` | `ThesisStatus` enum + parsing |
| `data/models/nomination.dart` | `NominationPosition`, `ConformeStatus`, `Nomination` |
| `data/models/thesis.dart` | `Thesis` model |
| `data/models/faculty_directory_entry.dart` | `FacultyDirectoryEntry` |
| `data/repositories/faculty_directory_repository.dart` | Directory reads + own-entry upsert |
| `data/repositories/thesis_repository.dart` | Thesis + nomination writes and streams |
| `features/thesis/create_thesis_screen.dart` | Group creation form |
| `features/thesis/nominate_screen.dart` | Faculty picker |
| `features/thesis/thesis_status_screen.dart` | Student's status view + Form 1 download |
| `features/nomination/nomination_inbox_screen.dart` | Faculty accept/decline |
| `features/nomination/review_queue_screen.dart` | Coordinator recommend + dean approve |
| `features/forms/form1_data.dart` | Data assembled for Form 1 |
| `features/forms/form1_pdf.dart` | PDF layout |
| `providers/thesis_providers.dart` | Riverpod wiring |

**Modified:** `firestore.rules`, `rules-test/rules.test.js`, `lib/features/auth/login_screen.dart`, `lib/features/auth/verify_email_screen.dart`, `lib/core/routing/app_router.dart`, the four dashboards, `pubspec.yaml`.

---

## Task 1: Domain models

**Files:**
- Create: `lib/data/models/thesis_status.dart`, `lib/data/models/nomination.dart`, `lib/data/models/thesis.dart`, `lib/data/models/faculty_directory_entry.dart`
- Test: `test/data/models/thesis_test.dart`, `test/data/models/nomination_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum ThesisStatus { draft, nominationPendingConforme, nominationPendingCoordinator, nominationPendingDean, nominationApproved }` with `String get value` and `static ThesisStatus fromString(String?)` (defaults to `draft`)
  - `enum NominationPosition { adviser, panelist, coordinator, dean }` with `value` / `fromString`
  - `enum ConformeStatus { pending, accepted, declined, exOfficio }` with `value` / `fromString`
  - `class Nomination { nomineeUid, nomineeName, position, exOfficio, conformeStatus, respondedAt, declineReason }`, `Nomination.fromMap(String nomineeUid, Map<String,dynamic>)`, `toMap()`
  - `class Thesis { id, leaderUid, memberNames, workingTitle, college, program, semester, academicYear, status, adviserUid, panelistUids, coordinatorRecommendedAt, coordinatorRecommendedBy, deanApprovedAt, deanApprovedBy, createdAt }`, `Thesis.fromMap(String id, Map<String,dynamic>)`, `toMap()`
  - `class FacultyDirectoryEntry { uid, fullName, college, specialization, role }` with `fromMap` / `toMap`

- [ ] **Step 1: Write the failing tests**

Create `test/data/models/nomination_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/nomination.dart';

void main() {
  test('parses a nominated panelist', () {
    final n = Nomination.fromMap('uid-1', {
      'nomineeName': 'Dr. Diamante',
      'position': 'panelist',
      'exOfficio': false,
      'conformeStatus': 'pending',
    });
    expect(n.nomineeUid, 'uid-1');
    expect(n.position, NominationPosition.panelist);
    expect(n.exOfficio, isFalse);
    expect(n.conformeStatus, ConformeStatus.pending);
  });

  test('parses an ex officio dean entry', () {
    final n = Nomination.fromMap('uid-2', {
      'nomineeName': 'Dr. Siason',
      'position': 'dean',
      'exOfficio': true,
      'conformeStatus': 'exOfficio',
    });
    expect(n.position, NominationPosition.dean);
    expect(n.exOfficio, isTrue);
    expect(n.conformeStatus, ConformeStatus.exOfficio);
  });

  test('unknown conforme status degrades to pending', () {
    final n = Nomination.fromMap('uid-3', {
      'nomineeName': 'X',
      'position': 'panelist',
      'exOfficio': false,
      'conformeStatus': 'approved',
    });
    expect(n.conformeStatus, ConformeStatus.pending);
  });

  test('toMap round-trips', () {
    final original = Nomination(
      nomineeUid: 'uid-4',
      nomineeName: 'Dr. Armada',
      position: NominationPosition.adviser,
      exOfficio: false,
      conformeStatus: ConformeStatus.accepted,
      respondedAt: DateTime.utc(2026, 8, 14),
    );
    final restored = Nomination.fromMap('uid-4', original.toMap());
    expect(restored.position, NominationPosition.adviser);
    expect(restored.conformeStatus, ConformeStatus.accepted);
    expect(restored.respondedAt, DateTime.utc(2026, 8, 14));
  });
}
```

Create `test/data/models/thesis_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 14);

  Map<String, dynamic> base() => {
        'leaderUid': 'leader-1',
        'memberNames': ['Bagsain, Karlo June', 'Solinap, Jepte'],
        'workingTitle': 'eThesisHub',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': 'First',
        'academicYear': '2026-2027',
        'status': 'nominationPendingConforme',
        'adviserUid': null,
        'panelistUids': <String>[],
        'createdAt': createdAt,
      };

  test('parses all fields', () {
    final t = Thesis.fromMap('t1', base());
    expect(t.id, 't1');
    expect(t.leaderUid, 'leader-1');
    expect(t.memberNames, hasLength(2));
    expect(t.status, ThesisStatus.nominationPendingConforme);
    expect(t.panelistUids, isEmpty);
  });

  test('unknown status degrades to draft', () {
    final t = Thesis.fromMap('t2', {...base(), 'status': 'wat'});
    expect(t.status, ThesisStatus.draft);
  });

  test('toMap round-trips', () {
    final restored = Thesis.fromMap('t3', Thesis.fromMap('t3', base()).toMap());
    expect(restored.academicYear, '2026-2027');
    expect(restored.memberNames, contains('Solinap, Jepte'));
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/models/`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the enums**

Create `lib/data/models/thesis_status.dart`:

```dart
enum ThesisStatus {
  draft,
  nominationPendingConforme,
  nominationPendingCoordinator,
  nominationPendingDean,
  nominationApproved;

  String get value => name;

  static ThesisStatus fromString(String? raw) {
    for (final s in ThesisStatus.values) {
      if (s.name == raw) return s;
    }
    return ThesisStatus.draft;
  }
}
```

Create `lib/data/models/nomination.dart`:

```dart
enum NominationPosition {
  adviser,
  panelist,
  coordinator,
  dean;

  String get value => name;

  static NominationPosition fromString(String? raw) {
    for (final p in NominationPosition.values) {
      if (p.name == raw) return p;
    }
    return NominationPosition.panelist;
  }
}

enum ConformeStatus {
  pending,
  accepted,
  declined,
  exOfficio;

  String get value => name;

  static ConformeStatus fromString(String? raw) {
    for (final c in ConformeStatus.values) {
      if (c.name == raw) return c;
    }
    return ConformeStatus.pending;
  }
}

class Nomination {
  const Nomination({
    required this.nomineeUid,
    required this.nomineeName,
    required this.position,
    required this.exOfficio,
    required this.conformeStatus,
    this.respondedAt,
    this.declineReason,
  });

  final String nomineeUid;
  final String nomineeName;
  final NominationPosition position;
  final bool exOfficio;
  final ConformeStatus conformeStatus;
  final DateTime? respondedAt;
  final String? declineReason;

  /// Ex officio seats are never asked, so they must not gate approval.
  bool get needsConforme => !exOfficio;

  factory Nomination.fromMap(String nomineeUid, Map<String, dynamic> map) {
    return Nomination(
      nomineeUid: nomineeUid,
      nomineeName: map['nomineeName'] as String? ?? '',
      position: NominationPosition.fromString(map['position'] as String?),
      exOfficio: map['exOfficio'] as bool? ?? false,
      conformeStatus: ConformeStatus.fromString(map['conformeStatus'] as String?),
      respondedAt: map['respondedAt'] as DateTime?,
      declineReason: map['declineReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'nomineeName': nomineeName,
        'position': position.value,
        'exOfficio': exOfficio,
        'conformeStatus': conformeStatus.value,
        'respondedAt': respondedAt,
        'declineReason': declineReason,
      };
}
```

- [ ] **Step 4: Implement Thesis and FacultyDirectoryEntry**

Create `lib/data/models/thesis.dart`:

```dart
import 'package:ethesishub/data/models/thesis_status.dart';

class Thesis {
  const Thesis({
    required this.id,
    required this.leaderUid,
    required this.memberNames,
    required this.workingTitle,
    required this.college,
    required this.program,
    required this.semester,
    required this.academicYear,
    required this.status,
    required this.panelistUids,
    required this.createdAt,
    this.adviserUid,
    this.coordinatorRecommendedAt,
    this.coordinatorRecommendedBy,
    this.deanApprovedAt,
    this.deanApprovedBy,
  });

  final String id;
  final String leaderUid;
  final List<String> memberNames;
  final String workingTitle;
  final String college;
  final String program;
  final String semester;
  final String academicYear;
  final ThesisStatus status;
  final List<String> panelistUids;
  final DateTime createdAt;
  final String? adviserUid;
  final DateTime? coordinatorRecommendedAt;
  final String? coordinatorRecommendedBy;
  final DateTime? deanApprovedAt;
  final String? deanApprovedBy;

  factory Thesis.fromMap(String id, Map<String, dynamic> map) {
    return Thesis(
      id: id,
      leaderUid: map['leaderUid'] as String? ?? '',
      memberNames: List<String>.from(map['memberNames'] as List? ?? const []),
      workingTitle: map['workingTitle'] as String? ?? '',
      college: map['college'] as String? ?? '',
      program: map['program'] as String? ?? '',
      semester: map['semester'] as String? ?? '',
      academicYear: map['academicYear'] as String? ?? '',
      status: ThesisStatus.fromString(map['status'] as String?),
      panelistUids: List<String>.from(map['panelistUids'] as List? ?? const []),
      createdAt: map['createdAt'] as DateTime? ?? DateTime.now().toUtc(),
      adviserUid: map['adviserUid'] as String?,
      coordinatorRecommendedAt: map['coordinatorRecommendedAt'] as DateTime?,
      coordinatorRecommendedBy: map['coordinatorRecommendedBy'] as String?,
      deanApprovedAt: map['deanApprovedAt'] as DateTime?,
      deanApprovedBy: map['deanApprovedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'leaderUid': leaderUid,
        'memberNames': memberNames,
        'workingTitle': workingTitle,
        'college': college,
        'program': program,
        'semester': semester,
        'academicYear': academicYear,
        'status': status.value,
        'panelistUids': panelistUids,
        'createdAt': createdAt,
        'adviserUid': adviserUid,
        'coordinatorRecommendedAt': coordinatorRecommendedAt,
        'coordinatorRecommendedBy': coordinatorRecommendedBy,
        'deanApprovedAt': deanApprovedAt,
        'deanApprovedBy': deanApprovedBy,
      };
}
```

Create `lib/data/models/faculty_directory_entry.dart`:

```dart
class FacultyDirectoryEntry {
  const FacultyDirectoryEntry({
    required this.uid,
    required this.fullName,
    required this.role,
    this.college,
    this.specialization,
  });

  final String uid;
  final String fullName;
  final String role;
  final String? college;
  final String? specialization;

  /// Shown under the name in the picker.
  String get subtitle => [college, specialization]
      .where((s) => s != null && s.isNotEmpty)
      .join(' · ');

  factory FacultyDirectoryEntry.fromMap(String uid, Map<String, dynamic> map) {
    return FacultyDirectoryEntry(
      uid: uid,
      fullName: map['fullName'] as String? ?? '',
      role: map['role'] as String? ?? 'faculty',
      college: map['college'] as String?,
      specialization: map['specialization'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'role': role,
        'college': college,
        'specialization': specialization,
      };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/models/`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/data/models/thesis_status.dart lib/data/models/nomination.dart lib/data/models/thesis.dart lib/data/models/faculty_directory_entry.dart test/data/models/thesis_test.dart test/data/models/nomination_test.dart
git commit -m "feat: add thesis, nomination and faculty directory models"
```

---

## Task 2: FacultyDirectoryRepository

**Files:**
- Create: `lib/data/repositories/faculty_directory_repository.dart`
- Test: `test/data/repositories/faculty_directory_repository_test.dart`

**Interfaces:**
- Consumes: `FacultyDirectoryEntry`, `AppUser`, `UserRole`
- Produces: `FacultyDirectoryRepository(FirebaseFirestore)` with
  - `Future<void> upsertOwnEntry(AppUser user)` — no-op when `user.role == UserRole.student`
  - `Stream<List<FacultyDirectoryEntry>> watchSelectableFaculty()` — role `faculty` only, sorted by name
  - `Future<List<FacultyDirectoryEntry>> fetchExOfficio()` — roles `coordinator` and `dean`
  - `Future<FacultyDirectoryEntry?> fetch(String uid)`

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/faculty_directory_repository_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';

AppUser user(String uid, String name, UserRole role) => AppUser(
      uid: uid,
      fullName: name,
      email: '$uid@isufst.edu.ph',
      role: role,
      active: true,
      createdAt: DateTime.utc(2026, 8, 14),
      college: 'CICT',
    );

void main() {
  late FakeFirebaseFirestore db;
  late FacultyDirectoryRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FacultyDirectoryRepository(db);
  });

  test('upsert writes an entry for faculty', () async {
    await repo.upsertOwnEntry(user('f1', 'Dr. Armada', UserRole.faculty));
    final entry = await repo.fetch('f1');
    expect(entry!.fullName, 'Dr. Armada');
    expect(entry.role, 'faculty');
  });

  test('upsert never writes an entry for a student', () async {
    await repo.upsertOwnEntry(user('s1', 'A Student', UserRole.student));
    expect(await repo.fetch('s1'), isNull);
  });

  test('the entry never contains an email', () async {
    await repo.upsertOwnEntry(user('f2', 'Dr. Diamante', UserRole.faculty));
    final raw = await db.collection('facultyDirectory').doc('f2').get();
    expect(raw.data()!.containsKey('email'), isFalse);
  });

  test('selectable faculty excludes coordinators and deans', () async {
    await repo.upsertOwnEntry(user('f3', 'Dr. Faculty', UserRole.faculty));
    await repo.upsertOwnEntry(user('c1', 'Dr. Coordinator', UserRole.coordinator));
    await repo.upsertOwnEntry(user('d1', 'Dr. Dean', UserRole.dean));

    final selectable = await repo.watchSelectableFaculty().first;
    expect(selectable.map((e) => e.uid), ['f3']);
  });

  test('fetchExOfficio returns coordinators and deans only', () async {
    await repo.upsertOwnEntry(user('f4', 'Dr. Faculty', UserRole.faculty));
    await repo.upsertOwnEntry(user('c2', 'Dr. Coordinator', UserRole.coordinator));
    await repo.upsertOwnEntry(user('d2', 'Dr. Dean', UserRole.dean));

    final ex = await repo.fetchExOfficio();
    expect(ex.map((e) => e.uid).toSet(), {'c2', 'd2'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/faculty_directory_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the repository**

Create `lib/data/repositories/faculty_directory_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/user_role.dart';

/// Exposes faculty names to students without exposing their emails.
///
/// Firestore has no field-level read security, so a rule letting a student
/// read a faculty `users` document would expose that document's email too.
/// This collection holds only what the nomination picker needs.
class FacultyDirectoryRepository {
  FacultyDirectoryRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('facultyDirectory');

  /// Written by the subject's own client — there are no Cloud Functions on
  /// Spark, so the directory is maintained client-side at sign-in.
  Future<void> upsertOwnEntry(AppUser user) async {
    if (user.role == UserRole.student) return;
    await _col.doc(user.uid).set({
      'fullName': user.fullName,
      'role': user.role.value,
      'college': user.college,
      'specialization': user.specialization,
    });
  }

  Future<FacultyDirectoryEntry?> fetch(String uid) async {
    final snap = await _col.doc(uid).get();
    if (!snap.exists) return null;
    return FacultyDirectoryEntry.fromMap(uid, snap.data()!);
  }

  /// Only `faculty` — the dean and coordinators are ex officio and must not
  /// appear in the picker.
  Stream<List<FacultyDirectoryEntry>> watchSelectableFaculty() {
    return _col.where('role', isEqualTo: 'faculty').snapshots().map((s) {
      final list = s.docs
          .map((d) => FacultyDirectoryEntry.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) => a.fullName.compareTo(b.fullName));
      return list;
    });
  }

  Future<List<FacultyDirectoryEntry>> fetchExOfficio() async {
    final snap =
        await _col.where('role', whereIn: ['coordinator', 'dean']).get();
    return snap.docs
        .map((d) => FacultyDirectoryEntry.fromMap(d.id, d.data()))
        .toList();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/faculty_directory_repository_test.dart`
Expected: PASS, all five tests

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/faculty_directory_repository.dart test/data/repositories/faculty_directory_repository_test.dart
git commit -m "feat: add faculty directory repository"
```

---

## Task 3: Populate the directory at sign-in

**Files:**
- Modify: `lib/features/auth/login_screen.dart`, `lib/features/auth/verify_email_screen.dart`, `lib/providers/thesis_providers.dart` (create)
- Test: `test/providers/thesis_providers_test.dart`

**Interfaces:**
- Consumes: `FacultyDirectoryRepository`, `currentUserProvider`, `firestoreProvider`
- Produces: `facultyDirectoryRepositoryProvider`, `thesisRepositoryProvider` (added in Task 4), `selectableFacultyProvider`

A faculty member's directory entry is written by their own client. `promoteFromInvite` already runs at sign-in in both screens, so the upsert goes immediately after a successful promotion **and** on every sign-in for users who are already faculty — otherwise anyone promoted before this module shipped never appears.

- [ ] **Step 1: Create the providers file**

Create `lib/providers/thesis_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final facultyDirectoryRepositoryProvider =
    Provider<FacultyDirectoryRepository>(
  (ref) => FacultyDirectoryRepository(ref.watch(firestoreProvider)),
);

/// Faculty a student may nominate. Excludes the dean and coordinators,
/// who sit on every panel ex officio.
final selectableFacultyProvider =
    StreamProvider<List<FacultyDirectoryEntry>>((ref) {
  return ref.watch(facultyDirectoryRepositoryProvider).watchSelectableFaculty();
});
```

- [ ] **Step 2: Write the failing test**

Create `test/providers/thesis_providers_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

void main() {
  test('selectableFacultyProvider exposes only faculty', () async {
    final db = FakeFirebaseFirestore();
    final repo = FacultyDirectoryRepository(db);
    await repo.upsertOwnEntry(AppUser(
      uid: 'f1', fullName: 'Dr. Armada', email: 'a@isufst.edu.ph',
      role: UserRole.faculty, active: true, createdAt: DateTime.utc(2026),
    ));
    await repo.upsertOwnEntry(AppUser(
      uid: 'd1', fullName: 'Dr. Siason', email: 'd@isufst.edu.ph',
      role: UserRole.dean, active: true, createdAt: DateTime.utc(2026),
    ));

    final container = ProviderContainer(
      overrides: [firestoreProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    final faculty = await container.read(selectableFacultyProvider.future);
    expect(faculty.map((e) => e.uid), ['f1']);
  });
}
```

- [ ] **Step 3: Run test to verify it passes**

Run: `flutter test test/providers/thesis_providers_test.dart`
Expected: PASS

- [ ] **Step 4: Upsert the directory entry after sign-in**

In `lib/features/auth/login_screen.dart`, inside the existing block that runs after a successful `signIn` and `promoteFromInvite`, add a directory upsert. Place it inside the same inner `try` that already absorbs `permission-denied`, so an unverified user does not see an error:

```dart
        // Keep the faculty directory current. Written by the subject's own
        // client because Spark has no Cloud Functions. Also backfills anyone
        // promoted before this module shipped.
        final profile = await ref.read(userRepositoryProvider).fetchUser(user.uid);
        if (profile != null) {
          await ref
              .read(facultyDirectoryRepositoryProvider)
              .upsertOwnEntry(profile);
        }
```

Add the import for `thesis_providers.dart`.

- [ ] **Step 5: Do the same in the verify-email screen**

Apply the identical block in `lib/features/auth/verify_email_screen.dart`, immediately after its `promoteFromInvite` call, inside the same error-absorbing `try`.

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS, no regressions

- [ ] **Step 7: Commit**

```bash
git add lib/providers/thesis_providers.dart lib/features/auth/login_screen.dart lib/features/auth/verify_email_screen.dart test/providers/thesis_providers_test.dart
git commit -m "feat: maintain the faculty directory at sign-in"
```

---

## Task 4: ThesisRepository — creation and reads

**Files:**
- Create: `lib/data/repositories/thesis_repository.dart`
- Modify: `lib/providers/thesis_providers.dart`
- Test: `test/data/repositories/thesis_repository_test.dart`

**Interfaces:**
- Consumes: `Thesis`, `ThesisStatus`, `Nomination`
- Produces: `ThesisRepository(FirebaseFirestore)` with
  - `Future<String> createThesis({required String leaderUid, required String workingTitle, required List<String> memberNames, required String college, required String program, required String semester, required String academicYear})` → new thesis id, status `draft`
  - `Stream<Thesis?> watchThesisForLeader(String leaderUid)`
  - `Stream<Thesis?> watchThesis(String thesisId)`
  - `Stream<List<Nomination>> watchNominations(String thesisId)`
  - `Stream<List<Thesis>> watchByStatus(ThesisStatus status)`
  - `thesisRepositoryProvider`

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/thesis_repository_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
  });

  Future<String> create() => repo.createThesis(
        leaderUid: 'leader-1',
        workingTitle: 'eThesisHub',
        memberNames: ['Bagsain, Karlo June'],
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
      );

  test('createThesis stores a draft owned by the leader', () async {
    final id = await create();
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.leaderUid, 'leader-1');
    expect(thesis.status, ThesisStatus.draft);
    expect(thesis.panelistUids, isEmpty);
    expect(thesis.adviserUid, isNull);
    expect(thesis.memberNames, ['Bagsain, Karlo June']);
  });

  test('watchThesisForLeader finds the leader thesis', () async {
    await create();
    final thesis = await repo.watchThesisForLeader('leader-1').first;
    expect(thesis, isNotNull);
    expect(thesis!.workingTitle, 'eThesisHub');
  });

  test('watchThesisForLeader is null for someone else', () async {
    await create();
    expect(await repo.watchThesisForLeader('other').first, isNull);
  });

  test('watchByStatus filters', () async {
    await create();
    final drafts = await repo.watchByStatus(ThesisStatus.draft).first;
    expect(drafts, hasLength(1));
    final pending =
        await repo.watchByStatus(ThesisStatus.nominationPendingDean).first;
    expect(pending, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/thesis_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement creation and reads**

Create `lib/data/repositories/thesis_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

class ThesisRepository {
  ThesisRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _theses =>
      _db.collection('theses');

  CollectionReference<Map<String, dynamic>> _nominations(String thesisId) =>
      _theses.doc(thesisId).collection('nominations');

  static DateTime? _date(Object? v) =>
      v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

  Thesis _toThesis(String id, Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data);
    raw['createdAt'] = _date(raw['createdAt']) ?? DateTime.now().toUtc();
    raw['coordinatorRecommendedAt'] = _date(raw['coordinatorRecommendedAt']);
    raw['deanApprovedAt'] = _date(raw['deanApprovedAt']);
    return Thesis.fromMap(id, raw);
  }

  Nomination _toNomination(String uid, Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data);
    raw['respondedAt'] = _date(raw['respondedAt']);
    return Nomination.fromMap(uid, raw);
  }

  Future<String> createThesis({
    required String leaderUid,
    required String workingTitle,
    required List<String> memberNames,
    required String college,
    required String program,
    required String semester,
    required String academicYear,
  }) async {
    final doc = _theses.doc();
    await doc.set({
      'leaderUid': leaderUid,
      'workingTitle': workingTitle.trim(),
      'memberNames': memberNames,
      'college': college,
      'program': program,
      'semester': semester,
      'academicYear': academicYear,
      'status': ThesisStatus.draft.value,
      'adviserUid': null,
      'panelistUids': <String>[],
      'coordinatorRecommendedAt': null,
      'coordinatorRecommendedBy': null,
      'deanApprovedAt': null,
      'deanApprovedBy': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<Thesis?> watchThesis(String thesisId) {
    return _theses.doc(thesisId).snapshots().map(
        (s) => s.exists ? _toThesis(s.id, s.data()!) : null);
  }

  Stream<Thesis?> watchThesisForLeader(String leaderUid) {
    return _theses
        .where('leaderUid', isEqualTo: leaderUid)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : _toThesis(s.docs.first.id, s.docs.first.data()));
  }

  Stream<List<Nomination>> watchNominations(String thesisId) {
    return _nominations(thesisId).snapshots().map((s) =>
        s.docs.map((d) => _toNomination(d.id, d.data())).toList());
  }

  Stream<List<Thesis>> watchByStatus(ThesisStatus status) {
    return _theses
        .where('status', isEqualTo: status.value)
        .snapshots()
        .map((s) => s.docs.map((d) => _toThesis(d.id, d.data())).toList());
  }
}
```

- [ ] **Step 4: Add the provider**

Append to `lib/providers/thesis_providers.dart`:

```dart
final thesisRepositoryProvider = Provider<ThesisRepository>(
  (ref) => ThesisRepository(ref.watch(firestoreProvider)),
);

/// The signed-in leader's thesis, or null if they have not created one.
final myThesisProvider = StreamProvider<Thesis?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(thesisRepositoryProvider).watchThesisForLeader(uid);
});
```

Add imports for `thesis_repository.dart` and `thesis.dart`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/repositories/thesis_repository_test.dart`
Expected: PASS, all four tests

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/thesis_repository.dart lib/providers/thesis_providers.dart test/data/repositories/thesis_repository_test.dart
git commit -m "feat: add thesis repository creation and reads"
```

---

## Task 5: ThesisRepository — nomination submission

**Files:**
- Modify: `lib/data/repositories/thesis_repository.dart`
- Test: `test/data/repositories/thesis_nomination_test.dart`

**Interfaces:**
- Produces: `Future<void> submitNominations({required String thesisId, required FacultyDirectoryEntry adviser, required List<FacultyDirectoryEntry> panelists, required List<FacultyDirectoryEntry> exOfficio})`

Writes one `nominations` document per person and advances the thesis to `nominationPendingConforme`, all in a single `WriteBatch` so a half-written nomination cannot exist.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/thesis_nomination_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

FacultyDirectoryEntry entry(String uid, String name, String role) =>
    FacultyDirectoryEntry(uid: uid, fullName: name, role: role);

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;
  late String thesisId;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
    thesisId = await repo.createThesis(
      leaderUid: 'leader-1', workingTitle: 'T', memberNames: const [],
      college: 'CICT', program: 'BSIT', semester: 'First',
      academicYear: '2026-2027',
    );
  });

  Future<void> submit() => repo.submitNominations(
        thesisId: thesisId,
        adviser: entry('a1', 'Dr. Armada', 'faculty'),
        panelists: [
          entry('p1', 'Dr. Diamante', 'faculty'),
          entry('p2', 'Prof. Padojinog', 'faculty'),
          entry('p3', 'Dr. Braganza', 'faculty'),
        ],
        exOfficio: [
          entry('c1', 'Dr. Bito-onon', 'coordinator'),
          entry('d1', 'Dr. Siason', 'dean'),
        ],
      );

  test('writes one nomination per person', () async {
    await submit();
    final noms = await repo.watchNominations(thesisId).first;
    expect(noms, hasLength(6));
  });

  test('nominated members are pending, ex officio are not', () async {
    await submit();
    final noms = await repo.watchNominations(thesisId).first;

    final adviser = noms.firstWhere((n) => n.nomineeUid == 'a1');
    expect(adviser.position, NominationPosition.adviser);
    expect(adviser.conformeStatus, ConformeStatus.pending);
    expect(adviser.exOfficio, isFalse);

    final dean = noms.firstWhere((n) => n.nomineeUid == 'd1');
    expect(dean.position, NominationPosition.dean);
    expect(dean.conformeStatus, ConformeStatus.exOfficio);
    expect(dean.exOfficio, isTrue);
    expect(dean.needsConforme, isFalse);
  });

  test('advances the thesis to pending conforme', () async {
    await submit();
    final thesis = await repo.watchThesis(thesisId).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test('rejects fewer than three panel members', () async {
    expect(
      () => repo.submitNominations(
        thesisId: thesisId,
        adviser: entry('a1', 'Dr. Armada', 'faculty'),
        panelists: [entry('p1', 'Dr. Diamante', 'faculty')],
        exOfficio: const [],
      ),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/thesis_nomination_test.dart`
Expected: FAIL — `submitNominations` is not defined

- [ ] **Step 3: Implement submission**

Add to `ThesisRepository` (and import `faculty_directory_entry.dart`):

```dart
  /// Writes every nomination and advances the thesis in one batch, so a
  /// half-submitted nomination cannot exist.
  ///
  /// Ex officio entries are written by the leader's client too, but the rules
  /// pin their `exOfficio` and `conformeStatus` values so a student cannot
  /// forge an acceptance.
  Future<void> submitNominations({
    required String thesisId,
    required FacultyDirectoryEntry adviser,
    required List<FacultyDirectoryEntry> panelists,
    required List<FacultyDirectoryEntry> exOfficio,
  }) async {
    if (panelists.length < 3) {
      throw ArgumentError('At least three panel members are required.');
    }

    final batch = _db.batch();
    final noms = _nominations(thesisId);

    batch.set(noms.doc(adviser.uid), {
      'nomineeName': adviser.fullName,
      'position': NominationPosition.adviser.value,
      'exOfficio': false,
      'conformeStatus': ConformeStatus.pending.value,
      'respondedAt': null,
      'declineReason': null,
    });

    for (final p in panelists) {
      batch.set(noms.doc(p.uid), {
        'nomineeName': p.fullName,
        'position': NominationPosition.panelist.value,
        'exOfficio': false,
        'conformeStatus': ConformeStatus.pending.value,
        'respondedAt': null,
        'declineReason': null,
      });
    }

    for (final e in exOfficio) {
      batch.set(noms.doc(e.uid), {
        'nomineeName': e.fullName,
        'position': e.role == 'dean'
            ? NominationPosition.dean.value
            : NominationPosition.coordinator.value,
        'exOfficio': true,
        'conformeStatus': ConformeStatus.exOfficio.value,
        'respondedAt': null,
        'declineReason': null,
      });
    }

    batch.update(_theses.doc(thesisId), {
      'status': ThesisStatus.nominationPendingConforme.value,
    });

    await batch.commit();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/thesis_nomination_test.dart`
Expected: PASS, all four tests

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/thesis_repository.dart test/data/repositories/thesis_nomination_test.dart
git commit -m "feat: submit nominations including ex officio entries"
```

---

## Task 6: ThesisRepository — Conforme, recommend, approve

**Files:**
- Modify: `lib/data/repositories/thesis_repository.dart`, `lib/providers/thesis_providers.dart`
- Test: `test/data/repositories/thesis_workflow_test.dart`

**Interfaces:**
- Produces:
  - `Future<void> respondToNomination({required String thesisId, required String nomineeUid, required bool accept, String? declineReason})`
  - `Future<void> recommend({required String thesisId, required String coordinatorUid})`
  - `Future<void> approve({required String thesisId, required String deanUid})`
  - `Stream<List<Nomination>> watchMyPendingNominations(String uid)` — collection-group query
  - `myPendingNominationsProvider`

`respondToNomination` advances the thesis to `nominationPendingCoordinator` once **every non-ex-officio** nomination is accepted. `approve` derives `adviserUid` and `panelistUids` from the accepted nominations.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/thesis_workflow_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

FacultyDirectoryEntry entry(String uid, String name, String role) =>
    FacultyDirectoryEntry(uid: uid, fullName: name, role: role);

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;
  late String id;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
    id = await repo.createThesis(
      leaderUid: 'leader-1', workingTitle: 'T', memberNames: const [],
      college: 'CICT', program: 'BSIT', semester: 'First',
      academicYear: '2026-2027',
    );
    await repo.submitNominations(
      thesisId: id,
      adviser: entry('a1', 'Dr. Armada', 'faculty'),
      panelists: [
        entry('p1', 'Dr. Diamante', 'faculty'),
        entry('p2', 'Prof. Padojinog', 'faculty'),
        entry('p3', 'Dr. Braganza', 'faculty'),
      ],
      exOfficio: [entry('d1', 'Dr. Siason', 'dean')],
    );
  });

  Future<void> acceptAll() async {
    for (final uid in ['a1', 'p1', 'p2', 'p3']) {
      await repo.respondToNomination(
          thesisId: id, nomineeUid: uid, accept: true);
    }
  }

  test('accepting all non-ex-officio advances to pending coordinator',
      () async {
    await acceptAll();
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingCoordinator);
  });

  test('the ex officio dean never blocks the advance', () async {
    await acceptAll();
    final noms = await repo.watchNominations(id).first;
    final dean = noms.firstWhere((n) => n.nomineeUid == 'd1');
    expect(dean.conformeStatus, ConformeStatus.exOfficio);
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingCoordinator);
  });

  test('a partial set does not advance', () async {
    await repo.respondToNomination(
        thesisId: id, nomineeUid: 'a1', accept: true);
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test('declining records the reason and does not advance', () async {
    await repo.respondToNomination(
        thesisId: id, nomineeUid: 'p1', accept: false,
        declineReason: 'Already at capacity');
    final noms = await repo.watchNominations(id).first;
    final p1 = noms.firstWhere((n) => n.nomineeUid == 'p1');
    expect(p1.conformeStatus, ConformeStatus.declined);
    expect(p1.declineReason, 'Already at capacity');
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingConforme);
  });

  test('recommend records who acted and advances to pending dean', () async {
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationPendingDean);
    expect(thesis.coordinatorRecommendedBy, 'c1');
    expect(thesis.coordinatorRecommendedAt, isNotNull);
  });

  test('approve fixes the panel from accepted nominations', () async {
    await acceptAll();
    await repo.recommend(thesisId: id, coordinatorUid: 'c1');
    await repo.approve(thesisId: id, deanUid: 'd1');

    final thesis = await repo.watchThesis(id).first;
    expect(thesis!.status, ThesisStatus.nominationApproved);
    expect(thesis.adviserUid, 'a1');
    expect(thesis.panelistUids.toSet(), {'p1', 'p2', 'p3'});
    expect(thesis.deanApprovedBy, 'd1');
  });

  test('the faculty inbox finds a nomination across theses', () async {
    final pending = await repo.watchMyPendingNominations('p1').first;
    expect(pending, hasLength(1));
    expect(pending.first.nomineeUid, 'p1');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/thesis_workflow_test.dart`
Expected: FAIL — `respondToNomination` is not defined

- [ ] **Step 3: Implement the workflow methods**

Add to `ThesisRepository`:

```dart
  Future<void> respondToNomination({
    required String thesisId,
    required String nomineeUid,
    required bool accept,
    String? declineReason,
  }) async {
    await _nominations(thesisId).doc(nomineeUid).update({
      'conformeStatus':
          (accept ? ConformeStatus.accepted : ConformeStatus.declined).value,
      'respondedAt': FieldValue.serverTimestamp(),
      'declineReason': accept ? null : declineReason,
    });

    if (!accept) return;

    // Advance only when every nomination that actually needs a Conforme has
    // one. Ex officio seats are never asked and must not gate this.
    final snap = await _nominations(thesisId).get();
    final all = snap.docs.map((d) => _toNomination(d.id, d.data())).toList();
    final outstanding = all
        .where((n) => n.needsConforme)
        .where((n) => n.conformeStatus != ConformeStatus.accepted);

    if (outstanding.isEmpty) {
      await _theses.doc(thesisId).update({
        'status': ThesisStatus.nominationPendingCoordinator.value,
      });
    }
  }

  Future<void> recommend({
    required String thesisId,
    required String coordinatorUid,
  }) {
    return _theses.doc(thesisId).update({
      'status': ThesisStatus.nominationPendingDean.value,
      'coordinatorRecommendedAt': FieldValue.serverTimestamp(),
      'coordinatorRecommendedBy': coordinatorUid,
    });
  }

  /// Fixes the panel from the accepted nominations, so the stored panel can
  /// never disagree with what the nominees actually accepted.
  Future<void> approve({
    required String thesisId,
    required String deanUid,
  }) async {
    final snap = await _nominations(thesisId).get();
    final all = snap.docs.map((d) => _toNomination(d.id, d.data())).toList();

    final accepted =
        all.where((n) => n.conformeStatus == ConformeStatus.accepted);
    final adviser = accepted
        .where((n) => n.position == NominationPosition.adviser)
        .toList();
    final panelists = accepted
        .where((n) => n.position == NominationPosition.panelist)
        .map((n) => n.nomineeUid)
        .toList();

    if (adviser.isEmpty) {
      throw StateError('Cannot approve without an accepted adviser.');
    }
    if (panelists.length < 3) {
      throw StateError('Cannot approve with fewer than three panel members.');
    }

    await _theses.doc(thesisId).update({
      'status': ThesisStatus.nominationApproved.value,
      'adviserUid': adviser.first.nomineeUid,
      'panelistUids': panelists,
      'deanApprovedAt': FieldValue.serverTimestamp(),
      'deanApprovedBy': deanUid,
    });
  }

  /// Every nomination addressed to this user, across all theses. Requires the
  /// collection-group rule on `nominations`.
  Stream<List<Nomination>> watchMyPendingNominations(String uid) {
    return _db
        .collectionGroup('nominations')
        .where(FieldPath.documentId, isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs
            .map((d) => _toNomination(d.id, d.data()))
            .where((n) => n.conformeStatus == ConformeStatus.pending)
            .toList());
  }

  /// The thesis id owning a nomination document, for acting on it.
  String thesisIdOfNomination(DocumentSnapshot doc) =>
      doc.reference.parent.parent!.id;
```

- [ ] **Step 4: Add the inbox provider**

Append to `lib/providers/thesis_providers.dart`:

```dart
/// Nominations awaiting this faculty member's Conforme.
final myPendingNominationsProvider =
    StreamProvider<List<Nomination>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(thesisRepositoryProvider).watchMyPendingNominations(uid);
});
```

Add the import for `nomination.dart`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/data/repositories/thesis_workflow_test.dart`
Expected: PASS, all seven tests

> If `fake_cloud_firestore` does not support `collectionGroup` with a
> `FieldPath.documentId` filter, report exactly what you observe rather than
> loosening the test. The inbox query is load-bearing and its rule is verified
> separately in Task 7.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/thesis_repository.dart lib/providers/thesis_providers.dart test/data/repositories/thesis_workflow_test.dart
git commit -m "feat: conforme, recommend and approve transitions"
```

---

## Task 7: Firestore rules

**Files:**
- Modify: `firestore.rules`, `rules-test/rules.test.js`

**Interfaces:**
- Consumes: existing helpers `signedIn()`, `verified()`, `myEmail()`, `myRole()`, `isCoordinator()`, `isDean()`, `onlyChanged()`
- Produces: rules for `theses`, `theses/{id}/nominations`, `facultyDirectory`, plus the collection-group rule

**This is the security surface. Do not weaken a rule to make a test pass.**

- [ ] **Step 1: Write the failing rules tests**

Append to `rules-test/rules.test.js`, before the final `env.cleanup()`:

```javascript
async function seedThesis(id, leaderUid, status) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "theses", id), {
      leaderUid, status, panelistUids: [], adviserUid: null,
      memberNames: [], workingTitle: "T", college: "CICT",
      program: "BSIT", semester: "First", academicYear: "2026-2027",
    });
  });
}

test("a student may create their own thesis as draft", async () => {
  await assertSucceeds(
    setDoc(doc(student, "theses/t-new"), {
      leaderUid: "student-uid", status: "draft", panelistUids: [],
      adviserUid: null, memberNames: [], workingTitle: "T",
      college: "CICT", program: "BSIT", semester: "First",
      academicYear: "2026-2027",
    })
  );
});

test("a student may NOT create a thesis owned by someone else", async () => {
  await assertFails(
    setDoc(doc(student, "theses/t-other"), {
      leaderUid: "someone-else", status: "draft", panelistUids: [],
      adviserUid: null, memberNames: [], workingTitle: "T",
      college: "CICT", program: "BSIT", semester: "First",
      academicYear: "2026-2027",
    })
  );
});

test("a student may NOT create a thesis already approved", async () => {
  await assertFails(
    setDoc(doc(student, "theses/t-cheat"), {
      leaderUid: "student-uid", status: "nominationApproved",
      panelistUids: [], adviserUid: null, memberNames: [],
      workingTitle: "T", college: "CICT", program: "BSIT",
      semester: "First", academicYear: "2026-2027",
    })
  );
});

test("a student may NOT read another student's thesis", async () => {
  await seedThesis("t-private", "other-uid", "draft");
  await assertFails(getDoc(doc(student, "theses/t-private")));
});

test("a student may NOT set the approval fields", async () => {
  await seedThesis("t-mine", "student-uid", "nominationPendingDean");
  await assertFails(
    updateDoc(doc(student, "theses/t-mine"), {
      status: "nominationApproved", adviserUid: "a1",
      panelistUids: ["p1", "p2", "p3"],
    })
  );
});

test("only the nominee may write their own conforme", async () => {
  await seedThesis("t-conf", "student-uid", "nominationPendingConforme");
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "theses/t-conf/nominations/invited-uid"), {
      nomineeName: "Dr. X", position: "panelist", exOfficio: false,
      conformeStatus: "pending", respondedAt: null, declineReason: null,
    });
  });

  await assertFails(
    updateDoc(doc(student, "theses/t-conf/nominations/invited-uid"), {
      conformeStatus: "accepted",
    })
  );

  const nominee = env
    .authenticatedContext("invited-uid", {
      email: "invited@isufst.edu.ph", email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(nominee, "theses/t-conf/nominations/invited-uid"), {
      conformeStatus: "accepted",
    })
  );
});

test("a student may NOT forge an ex officio acceptance", async () => {
  await seedThesis("t-forge", "student-uid", "draft");
  await assertFails(
    setDoc(doc(student, "theses/t-forge/nominations/fake-uid"), {
      nomineeName: "Dr. Fake", position: "panelist", exOfficio: true,
      conformeStatus: "accepted", respondedAt: null, declineReason: null,
    })
  );
});

test("anyone verified may read the faculty directory", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyDirectory/f1"), {
      fullName: "Dr. Armada", role: "faculty",
      college: "CICT", specialization: "SE",
    });
  });
  await assertSucceeds(getDoc(doc(student, "facultyDirectory/f1")));
});

test("a student may NOT write a faculty directory entry", async () => {
  await assertFails(
    setDoc(doc(student, "facultyDirectory/student-uid"), {
      fullName: "A Student", role: "faculty",
      college: "CICT", specialization: null,
    })
  );
});
```

- [ ] **Step 2: Run the rules tests to verify they fail**

```bash
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.8-hotspot"
export PATH="$JAVA_HOME/bin:$PATH"
cd rules-test && npm test
```

Expected: FAIL — the new tests are denied by the deny-by-default catch-all.

- [ ] **Step 3: Write the rules**

Insert into `firestore.rules`, before the terminal catch-all:

```javascript
    function thesisData(thesisId) {
      return get(/databases/$(database)/documents/theses/$(thesisId)).data;
    }

    function isThesisLeader(thesisId) {
      return signedIn() && thesisData(thesisId).leaderUid == request.auth.uid;
    }

    function isOnPanel(thesisId) {
      return signedIn() && (
        thesisData(thesisId).adviserUid == request.auth.uid ||
        request.auth.uid in thesisData(thesisId).panelistUids
      );
    }

    match /theses/{thesisId} {
      allow get: if isThesisLeader(thesisId)
                 || isOnPanel(thesisId)
                 || isCoordinator() || isDean();
      allow list: if isCoordinator() || isDean();

      // A leader creates their own thesis, always as a draft with an empty
      // panel. Nothing here may arrive pre-approved.
      allow create: if verified()
                    && request.resource.data.leaderUid == request.auth.uid
                    && request.resource.data.status == 'draft'
                    && request.resource.data.adviserUid == null
                    && request.resource.data.panelistUids.size() == 0
                    && request.resource.data.academicYear.matches('[0-9]{4}-[0-9]{4}');

      // The leader edits group details and may submit the nomination, but
      // may never touch the approval fields.
      allow update: if isThesisLeader(thesisId)
                    && onlyChanged(['memberNames', 'workingTitle', 'college',
                                    'program', 'semester', 'academicYear',
                                    'status'])
                    && request.resource.data.status in
                       ['draft', 'nominationPendingConforme'];

      // A nominee's acceptance advances the status; nothing else changes.
      allow update: if verified()
                    && onlyChanged(['status'])
                    && request.resource.data.status ==
                       'nominationPendingCoordinator';

      allow update: if isCoordinator()
                    && onlyChanged(['status', 'coordinatorRecommendedAt',
                                    'coordinatorRecommendedBy'])
                    && request.resource.data.coordinatorRecommendedBy ==
                       request.auth.uid
                    && request.resource.data.status == 'nominationPendingDean';

      allow update: if isDean()
                    && onlyChanged(['status', 'deanApprovedAt',
                                    'deanApprovedBy', 'adviserUid',
                                    'panelistUids'])
                    && request.resource.data.deanApprovedBy == request.auth.uid
                    && request.resource.data.status == 'nominationApproved'
                    && request.resource.data.panelistUids.size() >= 3;

      allow delete: if false;

      match /nominations/{nomineeUid} {
        allow get, list: if isThesisLeader(thesisId)
                         || request.auth.uid == nomineeUid
                         || isCoordinator() || isDean();

        // The leader writes every entry, including the ex officio ones —
        // but those are pinned so a student cannot forge an acceptance.
        allow create: if isThesisLeader(thesisId)
                      && (
                        (request.resource.data.exOfficio == false
                         && request.resource.data.conformeStatus == 'pending')
                        ||
                        (request.resource.data.exOfficio == true
                         && request.resource.data.conformeStatus == 'exOfficio')
                      );

        // Only the nominee answers, and only on a seat that was asked.
        allow update: if verified()
                      && request.auth.uid == nomineeUid
                      && resource.data.exOfficio == false
                      && onlyChanged(['conformeStatus', 'respondedAt',
                                      'declineReason'])
                      && request.resource.data.conformeStatus in
                         ['accepted', 'declined'];

        // Re-nomination of a declined slot.
        allow delete: if isThesisLeader(thesisId)
                      && resource.data.conformeStatus == 'declined';
      }
    }

    // The faculty inbox queries nominations across all theses.
    match /{path=**}/nominations/{nomineeUid} {
      allow read: if verified() && request.auth.uid == nomineeUid;
    }

    match /facultyDirectory/{uid} {
      allow read: if verified();
      allow write: if signedIn()
                   && request.auth.uid == uid
                   && myRole() != 'student';
    }
```

- [ ] **Step 4: Run the rules tests to verify they pass**

```bash
cd rules-test && npm test
```

Expected: PASS — all previous tests plus the nine new ones.

- [ ] **Step 5: Deploy**

```bash
firebase deploy --only firestore:rules
```

Expected: `Deploy complete!`

- [ ] **Step 6: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: rules for theses, nominations and faculty directory"
```

---

## Task 8: Create-thesis screen

**Files:**
- Create: `lib/features/thesis/create_thesis_screen.dart`
- Test: `test/features/thesis/create_thesis_screen_test.dart`

**Interfaces:**
- Consumes: `thesisRepositoryProvider`, `authStateProvider`
- Produces: `CreateThesisScreen` (route `/thesis/create`)

Fixed sets are dropdowns; only the working title and member names are typed.

- [ ] **Step 1: Write the failing test**

Create `test/features/thesis/create_thesis_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/thesis/create_thesis_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: const MaterialApp(home: CreateThesisScreen()),
    );

void main() {
  testWidgets('fixed sets are dropdowns, not text fields', (tester) async {
    await tester.pumpWidget(wrap(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('college')), findsOneWidget);
    expect(find.byKey(const Key('program')), findsOneWidget);
    expect(find.byKey(const Key('semester')), findsOneWidget);
    expect(find.byKey(const Key('academicYear')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(4));
  });

  testWidgets('requires a working title', (tester) async {
    await tester.pumpWidget(wrap(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Working title'), findsWidgets);
  });

  testWidgets('creates a draft thesis owned by the signed-in leader',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final docs = await db.collection('theses').get();
    expect(docs.docs, hasLength(1));
    expect(docs.docs.first.data()['leaderUid'], 'leader-1');
    expect(docs.docs.first.data()['status'], 'draft');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/thesis/create_thesis_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the screen**

Create `lib/features/thesis/create_thesis_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

const kColleges = ['CICT', 'CFAS', 'COED', 'COAG', 'CIT'];
const kPrograms = ['BSIT', 'BSCS', 'BSIS'];
const kSemesters = ['First', 'Second'];
const kAcademicYears = ['2026-2027', '2027-2028'];

class CreateThesisScreen extends ConsumerStatefulWidget {
  const CreateThesisScreen({super.key});

  @override
  ConsumerState<CreateThesisScreen> createState() => _CreateThesisScreenState();
}

class _CreateThesisScreenState extends ConsumerState<CreateThesisScreen> {
  final _workingTitle = TextEditingController();
  final _members = <TextEditingController>[TextEditingController()];

  String _college = kColleges.first;
  String _program = kPrograms.first;
  String _semester = kSemesters.first;
  String _academicYear = kAcademicYears.first;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _workingTitle.dispose();
    for (final c in _members) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _workingTitle.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Working title is required.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final uid = ref.read(authStateProvider).value!.uid;
      await ref.read(thesisRepositoryProvider).createThesis(
            leaderUid: uid,
            workingTitle: title,
            memberNames: _members
                .map((c) => c.text.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            college: _college,
            program: _program,
            semester: _semester,
            academicYear: _academicYear,
          );
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not create the group.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown(String key, String label, String value,
      List<String> options, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: (v) => onChanged(v!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create thesis group')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('workingTitle'),
                  controller: _workingTitle,
                  decoration: const InputDecoration(
                    labelText: 'Working title',
                    helperText: 'Your initial idea. Candidate titles come later.',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Group members'),
                for (var i = 0; i < _members.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      key: Key('member$i'),
                      controller: _members[i],
                      decoration: const InputDecoration(
                          labelText: 'Surname, First name'),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('addMember'),
                    onPressed: () => setState(
                        () => _members.add(TextEditingController())),
                    child: const Text('+ Add member'),
                  ),
                ),
                const SizedBox(height: 8),
                _dropdown('college', 'College', _college, kColleges,
                    (v) => setState(() => _college = v)),
                const SizedBox(height: 12),
                _dropdown('program', 'Program', _program, kPrograms,
                    (v) => setState(() => _program = v)),
                const SizedBox(height: 12),
                _dropdown('semester', 'Semester', _semester, kSemesters,
                    (v) => setState(() => _semester = v)),
                const SizedBox(height: 12),
                _dropdown('academicYear', 'Academic year', _academicYear,
                    kAcademicYears, (v) => setState(() => _academicYear = v)),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  key: const Key('submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Creating…' : 'Create group'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/thesis/create_thesis_screen_test.dart`
Expected: PASS, all three tests

- [ ] **Step 5: Commit**

```bash
git add lib/features/thesis/create_thesis_screen.dart test/features/thesis/create_thesis_screen_test.dart
git commit -m "feat: add create thesis group screen"
```

---

## Task 9: Nomination screen

**Files:**
- Create: `lib/features/thesis/nominate_screen.dart`
- Test: `test/features/thesis/nominate_screen_test.dart`

**Interfaces:**
- Consumes: `selectableFacultyProvider`, `facultyDirectoryRepositoryProvider`, `thesisRepositoryProvider`, `myThesisProvider`
- Produces: `NominateScreen` (route `/thesis/nominate`)

Adviser and panel members come from dropdowns backed by `facultyDirectory`. The dean and coordinators are shown read-only and are never selectable.

- [ ] **Step 1: Write the failing test**

Create `test/features/thesis/nominate_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/thesis/nominate_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  for (final f in ['Armada', 'Diamante', 'Padojinog', 'Braganza']) {
    await db.collection('facultyDirectory').doc(f).set(
        {'fullName': 'Dr. $f', 'role': 'faculty', 'college': 'CICT'});
  }
  await db.collection('facultyDirectory').doc('coord').set(
      {'fullName': 'Dr. Bito-onon', 'role': 'coordinator', 'college': 'CICT'});
  await db.collection('facultyDirectory').doc('dean').set(
      {'fullName': 'Dr. Siason', 'role': 'dean', 'college': 'CICT'});
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': 'draft', 'panelistUids': [],
    'adviserUid': null, 'memberNames': [], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027',
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: const MaterialApp(home: NominateScreen(thesisId: 't1')),
    );

void main() {
  testWidgets('ex officio members are shown but not selectable',
      (tester) async {
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dr. Bito-onon'), findsOneWidget);
    expect(find.textContaining('Dr. Siason'), findsOneWidget);
    expect(find.textContaining('added automatically'), findsOneWidget);

    // Four selectable faculty in every picker; never the coordinator or dean.
    final adviser = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('adviser')));
    expect(adviser.items!.length, 4);
    expect(
      adviser.items!.map((i) => i.value),
      isNot(contains('coord')),
    );
  });

  testWidgets('refuses fewer than three panel members', (tester) async {
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitNomination')));
    await tester.pumpAndSettle();

    expect(find.textContaining('three panel members'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/thesis/nominate_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the screen**

Create `lib/features/thesis/nominate_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class NominateScreen extends ConsumerStatefulWidget {
  const NominateScreen({super.key, required this.thesisId});

  final String thesisId;

  @override
  ConsumerState<NominateScreen> createState() => _NominateScreenState();
}

class _NominateScreenState extends ConsumerState<NominateScreen> {
  String? _adviserUid;
  final List<String?> _panelUids = [null, null, null];

  String? _error;
  bool _busy = false;
  List<FacultyDirectoryEntry> _exOfficio = const [];

  @override
  void initState() {
    super.initState();
    _loadExOfficio();
  }

  Future<void> _loadExOfficio() async {
    final list =
        await ref.read(facultyDirectoryRepositoryProvider).fetchExOfficio();
    if (mounted) setState(() => _exOfficio = list);
  }

  Future<void> _submit(List<FacultyDirectoryEntry> faculty) async {
    final chosen = _panelUids.whereType<String>().toSet();
    if (_adviserUid == null) {
      setState(() => _error = 'Choose a thesis adviser.');
      return;
    }
    if (chosen.length < 3) {
      setState(() => _error = 'Choose at least three panel members.');
      return;
    }
    if (chosen.contains(_adviserUid)) {
      setState(() =>
          _error = 'The adviser cannot also be a panel member.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      FacultyDirectoryEntry byUid(String uid) =>
          faculty.firstWhere((f) => f.uid == uid);

      await ref.read(thesisRepositoryProvider).submitNominations(
            thesisId: widget.thesisId,
            adviser: byUid(_adviserUid!),
            panelists: chosen.map(byUid).toList(),
            exOfficio: _exOfficio,
          );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit the nomination.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DropdownButtonFormField<String> _picker(
    String key,
    String label,
    String? value,
    List<FacultyDirectoryEntry> faculty,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final f in faculty)
          DropdownMenuItem(
            value: f.uid,
            child: Text('${f.fullName} — ${f.subtitle}',
                overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final facultyAsync = ref.watch(selectableFacultyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nominate adviser and panel')),
      body: facultyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load the faculty list.')),
        data: (faculty) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _picker('adviser', 'Thesis Adviser', _adviserUid, faculty,
                      (v) => setState(() => _adviserUid = v)),
                  const SizedBox(height: 20),
                  const Text('Panel members (minimum 3)'),
                  for (var i = 0; i < _panelUids.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _picker('panel$i', 'Panel member ${i + 1}',
                          _panelUids[i], faculty,
                          (v) => setState(() => _panelUids[i] = v)),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('addPanelist'),
                      onPressed: () => setState(() => _panelUids.add(null)),
                      child: const Text('+ Add panel member'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Also on your panel — added automatically'),
                          const SizedBox(height: 6),
                          for (final e in _exOfficio)
                            Text('${e.fullName} — ${e.role}'),
                          const SizedBox(height: 6),
                          Text(
                            'They sit on every panel by role, so there is '
                            'nothing to choose and nothing for them to accept.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  FilledButton(
                    key: const Key('submitNomination'),
                    onPressed: _busy ? null : () => _submit(faculty),
                    child: Text(_busy ? 'Submitting…' : 'Submit nomination'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/thesis/nominate_screen_test.dart`
Expected: PASS, both tests

- [ ] **Step 5: Commit**

```bash
git add lib/features/thesis/nominate_screen.dart test/features/thesis/nominate_screen_test.dart
git commit -m "feat: add nomination screen with faculty picker"
```

---

## Task 10: Faculty nomination inbox

**Files:**
- Create: `lib/features/nomination/nomination_inbox_screen.dart`
- Test: `test/features/nomination/nomination_inbox_screen_test.dart`

**Interfaces:**
- Consumes: `myPendingNominationsProvider`, `thesisRepositoryProvider`
- Produces: `NominationInboxScreen`

Because `watchMyPendingNominations` returns `Nomination` objects without their parent thesis id, this screen needs it. Extend the repository with a small record type rather than reaching into snapshots from the widget.

- [ ] **Step 1: Add the parent-id-carrying query**

Replace `watchMyPendingNominations` in `ThesisRepository` with:

```dart
  /// A pending nomination together with the thesis it belongs to.
  Stream<List<({String thesisId, Nomination nomination})>>
      watchMyPendingNominations(String uid) {
    return _db
        .collectionGroup('nominations')
        .where(FieldPath.documentId, isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs
            .map((d) => (
                  thesisId: d.reference.parent.parent!.id,
                  nomination: _toNomination(d.id, d.data()),
                ))
            .where((r) =>
                r.nomination.conformeStatus == ConformeStatus.pending)
            .toList());
  }
```

Update `myPendingNominationsProvider`'s type to
`StreamProvider<List<({String thesisId, Nomination nomination})>>`, and update
the Task 6 test's last case to read `pending.first.nomination.nomineeUid`.

Delete `thesisIdOfNomination` — the record replaces it.

- [ ] **Step 2: Write the failing test**

Create `test/features/nomination/nomination_inbox_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/nomination/nomination_inbox_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': 'nominationPendingConforme',
    'panelistUids': [], 'adviserUid': null, 'memberNames': [],
    'workingTitle': 'eThesisHub', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  await db
      .collection('theses').doc('t1')
      .collection('nominations').doc('fac-1')
      .set({
    'nomineeName': 'Dr. Armada', 'position': 'adviser', 'exOfficio': false,
    'conformeStatus': 'pending', 'respondedAt': null, 'declineReason': null,
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'fac-1', email: 'f@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: const MaterialApp(home: NominationInboxScreen()),
    );

void main() {
  testWidgets('accepting records the conforme', (tester) async {
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.textContaining('eThesisHub'), findsOneWidget);
    await tester.tap(find.byKey(const Key('accept-t1')));
    await tester.pumpAndSettle();

    final nom = await db
        .collection('theses').doc('t1')
        .collection('nominations').doc('fac-1').get();
    expect(nom.data()!['conformeStatus'], 'accepted');
  });

  testWidgets('declining requires a reason', (tester) async {
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('decline-t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmDecline')));
    await tester.pumpAndSettle();

    expect(find.textContaining('reason'), findsWidgets);

    final nom = await db
        .collection('theses').doc('t1')
        .collection('nominations').doc('fac-1').get();
    expect(nom.data()!['conformeStatus'], 'pending');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/nomination/nomination_inbox_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 4: Implement the screen**

Create `lib/features/nomination/nomination_inbox_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class NominationInboxScreen extends ConsumerStatefulWidget {
  const NominationInboxScreen({super.key});

  @override
  ConsumerState<NominationInboxScreen> createState() =>
      _NominationInboxScreenState();
}

class _NominationInboxScreenState
    extends ConsumerState<NominationInboxScreen> {
  final _reason = TextEditingController();
  String? _decliningThesisId;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _respond(String thesisId, bool accept) async {
    if (!accept && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Please give a reason for declining.');
      return;
    }
    try {
      final uid = ref.read(authStateProvider).value!.uid;
      await ref.read(thesisRepositoryProvider).respondToNomination(
            thesisId: thesisId,
            nomineeUid: uid,
            accept: accept,
            declineReason: accept ? null : _reason.text.trim(),
          );
      if (mounted) {
        setState(() {
          _decliningThesisId = null;
          _error = null;
          _reason.clear();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record your response.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(myPendingNominationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nomination inbox')),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load your nominations.')),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No pending nominations.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              for (final item in items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ThesisTitle(thesisId: item.thesisId),
                        Text('Nominated as ${item.nomination.position.value}'),
                        if (_decliningThesisId == item.thesisId) ...[
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('declineReason'),
                            controller: _reason,
                            decoration: const InputDecoration(
                                labelText: 'Reason for declining'),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            FilledButton(
                              key: Key('accept-${item.thesisId}'),
                              onPressed: () => _respond(item.thesisId, true),
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 10),
                            if (_decliningThesisId == item.thesisId)
                              OutlinedButton(
                                key: const Key('confirmDecline'),
                                onPressed: () =>
                                    _respond(item.thesisId, false),
                                child: const Text('Confirm decline'),
                              )
                            else
                              OutlinedButton(
                                key: Key('decline-${item.thesisId}'),
                                onPressed: () => setState(
                                    () => _decliningThesisId = item.thesisId),
                                child: const Text('Decline'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ThesisTitle extends ConsumerWidget {
  const _ThesisTitle({required this.thesisId});

  final String thesisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesis =
        ref.watch(thesisRepositoryProvider).watchThesis(thesisId);
    return StreamBuilder(
      stream: thesis,
      builder: (context, snap) => Text(
        snap.data?.workingTitle ?? '…',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/nomination/`
Expected: PASS, both tests

- [ ] **Step 6: Commit**

```bash
git add lib/features/nomination/nomination_inbox_screen.dart lib/data/repositories/thesis_repository.dart lib/providers/thesis_providers.dart test/features/nomination/nomination_inbox_screen_test.dart test/data/repositories/thesis_workflow_test.dart
git commit -m "feat: add faculty nomination inbox"
```

---

## Task 11: Coordinator and dean review queue

**Files:**
- Create: `lib/features/nomination/review_queue_screen.dart`
- Test: `test/features/nomination/review_queue_screen_test.dart`

**Interfaces:**
- Consumes: `thesisRepositoryProvider`, `currentUserProvider`
- Produces: `ReviewQueueScreen({required ThesisStatus queue, required bool isDean})`

One screen serves both roles: the coordinator sees `nominationPendingCoordinator` and recommends; the dean sees `nominationPendingDean` and approves.

- [ ] **Step 1: Write the failing test**

Create `test/features/nomination/review_queue_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/nomination/review_queue_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded(String status) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': [],
    'adviserUid': null, 'memberNames': [], 'workingTitle': 'eThesisHub',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027',
  });
  final noms = db.collection('theses').doc('t1').collection('nominations');
  await noms.doc('a1').set({
    'nomineeName': 'Dr. Armada', 'position': 'adviser', 'exOfficio': false,
    'conformeStatus': 'accepted', 'respondedAt': null, 'declineReason': null,
  });
  for (final p in ['p1', 'p2', 'p3']) {
    await noms.doc(p).set({
      'nomineeName': 'Dr. $p', 'position': 'panelist', 'exOfficio': false,
      'conformeStatus': 'accepted', 'respondedAt': null,
      'declineReason': null,
    });
  }
  return db;
}

Widget wrap(FakeFirebaseFirestore db, ThesisStatus queue, bool isDean) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'reviewer-1',
              email: 'r@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: MaterialApp(
          home: ReviewQueueScreen(queue: queue, isDean: isDean)),
    );

void main() {
  testWidgets('coordinator recommends and records who acted', (tester) async {
    final db = await seeded('nominationPendingCoordinator');
    await tester.pumpWidget(wrap(
        db, ThesisStatus.nominationPendingCoordinator, false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('act-t1')));
    await tester.pumpAndSettle();

    final t = await db.collection('theses').doc('t1').get();
    expect(t.data()!['status'], 'nominationPendingDean');
    expect(t.data()!['coordinatorRecommendedBy'], 'reviewer-1');
  });

  testWidgets('dean approves and fixes the panel', (tester) async {
    final db = await seeded('nominationPendingDean');
    await tester.pumpWidget(
        wrap(db, ThesisStatus.nominationPendingDean, true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('act-t1')));
    await tester.pumpAndSettle();

    final t = await db.collection('theses').doc('t1').get();
    expect(t.data()!['status'], 'nominationApproved');
    expect(t.data()!['adviserUid'], 'a1');
    expect((t.data()!['panelistUids'] as List).toSet(),
        {'p1', 'p2', 'p3'});
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/nomination/review_queue_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the screen**

Create `lib/features/nomination/review_queue_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({
    super.key,
    required this.queue,
    required this.isDean,
  });

  final ThesisStatus queue;
  final bool isDean;

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  String? _error;

  Future<void> _act(String thesisId) async {
    try {
      final uid = ref.read(authStateProvider).value!.uid;
      final repo = ref.read(thesisRepositoryProvider);
      if (widget.isDean) {
        await repo.approve(thesisId: thesisId, deanUid: uid);
      } else {
        await repo.recommend(thesisId: thesisId, coordinatorUid: uid);
      }
      if (mounted) setState(() => _error = null);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record the decision.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(thesisRepositoryProvider);
    final label = widget.isDean ? 'Approve' : 'Recommend';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isDean
            ? 'Nomination approvals'
            : 'Nomination recommendations'),
      ),
      body: StreamBuilder(
        stream: repo.watchByStatus(widget.queue),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final theses = snap.data!;
          if (theses.isEmpty) {
            return const Center(child: Text('Nothing waiting.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
              for (final t in theses)
                Card(
                  child: ListTile(
                    title: Text(t.workingTitle),
                    subtitle: Text(
                        '${t.program} · ${t.semester} · ${t.academicYear}'),
                    trailing: FilledButton(
                      key: Key('act-${t.id}'),
                      onPressed: () => _act(t.id),
                      child: Text(label),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/nomination/review_queue_screen_test.dart`
Expected: PASS, both tests

- [ ] **Step 5: Log the approval to the audit trail**

Spec §7.4 requires a `nomination.approved` audit entry at the Dean's approval.
`AuditService` is already wired from the skeleton.

In `_act`, immediately after a successful `approve`, add:

```dart
      if (widget.isDean) {
        // Audit failures must never break the approval they record.
        try {
          await ref.read(auditServiceProvider).log(
                actorUid: uid,
                action: 'nomination.approved',
                targetType: 'thesis',
                targetId: thesisId,
                metadata: {'queue': widget.queue.value},
              );
        } catch (_) {}
      }
```

Import `package:ethesishub/providers/service_providers.dart`.

`AuditService.log` writes exactly the six whitelisted keys with
`FieldValue.serverTimestamp()`, matching the deployed `hasOnly` rule. Do not add
a seventh key.

- [ ] **Step 6: Add the audit test**

Append to `review_queue_screen_test.dart`:

```dart
  testWidgets('approval writes an audit entry', (tester) async {
    final db = await seeded('nominationPendingDean');
    await tester.pumpWidget(
        wrap(db, ThesisStatus.nominationPendingDean, true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('act-t1')));
    await tester.pumpAndSettle();

    final logs = await db.collection('auditLogs').get();
    expect(logs.docs, hasLength(1));
    expect(logs.docs.first.data()['action'], 'nomination.approved');
    expect(logs.docs.first.data()['actorUid'], 'reviewer-1');
    expect(
      logs.docs.first.data().keys,
      unorderedEquals([
        'actorUid', 'action', 'targetType', 'targetId', 'metadata', 'timestamp',
      ]),
      reason: 'auditLogs rules use hasOnly — an extra key breaks every write',
    );
  });
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/features/nomination/review_queue_screen_test.dart`
Expected: PASS, all three tests

- [ ] **Step 8: Commit**

```bash
git add lib/features/nomination/review_queue_screen.dart test/features/nomination/review_queue_screen_test.dart
git commit -m "feat: add coordinator and dean review queue with audit logging"
```

---

## Task 12: Form 1 data assembly

**Files:**
- Create: `lib/features/forms/form1_data.dart`
- Test: `test/features/forms/form1_data_test.dart`

**Interfaces:**
- Consumes: `Thesis`, `Nomination`, `AppUser`, `FacultyDirectoryEntry`
- Produces: `Form1Data` with `Form1Data.assemble({required Thesis thesis, required List<Nomination> nominations, required String leaderName, required Map<String, String> directoryNames})`, exposing `adviserName`, `panelNames`, `exOfficioEntries`, `conformeRows`, `coordinatorName`, `deanName`, `submittedOn`

Pure Dart — no Firebase, no PDF. Keeps the layout task free of data-shaping logic.

- [ ] **Step 1: Write the failing test**

Create `test/features/forms/form1_data_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';

Nomination nom(String uid, String name, NominationPosition pos,
        {bool ex = false, ConformeStatus status = ConformeStatus.accepted}) =>
    Nomination(
      nomineeUid: uid, nomineeName: name, position: pos,
      exOfficio: ex, conformeStatus: status,
      respondedAt: DateTime.utc(2026, 8, 14, 10, 22),
    );

void main() {
  final thesis = Thesis(
    id: 't1', leaderUid: 'l1', memberNames: const ['Bagsain, Karlo June'],
    workingTitle: 'eThesisHub', college: 'CICT', program: 'BSIT',
    semester: 'First', academicYear: '2026-2027',
    status: ThesisStatus.nominationApproved, panelistUids: const ['p1'],
    createdAt: DateTime.utc(2026, 8, 14), adviserUid: 'a1',
    coordinatorRecommendedBy: 'c1', deanApprovedBy: 'd1',
  );

  final nominations = [
    nom('a1', 'Dr. Armada', NominationPosition.adviser),
    nom('p1', 'Dr. Diamante', NominationPosition.panelist),
    nom('c1', 'Dr. Bito-onon', NominationPosition.coordinator,
        ex: true, status: ConformeStatus.exOfficio),
    nom('d1', 'Dr. Siason', NominationPosition.dean,
        ex: true, status: ConformeStatus.exOfficio),
  ];

  test('separates nominated members from ex officio', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );
    expect(data.adviserName, 'Dr. Armada');
    expect(data.panelNames, ['Dr. Diamante']);
    expect(data.exOfficioEntries.map((e) => e.name).toSet(),
        {'Dr. Bito-onon', 'Dr. Siason'});
  });

  test('conforme rows carry acceptance text for nominated members only', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );
    final adviserRow =
        data.conformeRows.firstWhere((r) => r.name == 'Dr. Armada');
    expect(adviserRow.status, contains('Accepted'));

    final deanRow =
        data.conformeRows.firstWhere((r) => r.name == 'Dr. Siason');
    expect(deanRow.status, 'Ex officio member');
    expect(deanRow.role, contains('ex officio'));
  });

  test('all researchers are listed with the leader first', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl Joshua P. Vargas', directoryNames: const {},
    );
    expect(data.researchers.first.name, 'Karl Joshua P. Vargas');
    expect(data.researchers.first.isLeader, isTrue);
    expect(data.researchers, hasLength(2));
  });

  test('uses plural wording when the group has members', () {
    final data = Form1Data.assemble(
      thesis: thesis, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.subjectPronoun, 'We');
    expect(data.possessivePronoun, 'our');
  });

  test('uses singular wording for a solo thesis', () {
    final solo = Thesis(
      id: 't2', leaderUid: 'l1', memberNames: const [],
      workingTitle: 'X', college: 'CICT', program: 'BSIT',
      semester: 'First', academicYear: '2026-2027',
      status: ThesisStatus.nominationApproved, panelistUids: const [],
      createdAt: DateTime.utc(2026, 8, 14),
    );
    final data = Form1Data.assemble(
      thesis: solo, nominations: nominations,
      leaderName: 'Karl', directoryNames: const {},
    );
    expect(data.subjectPronoun, 'I');
    expect(data.possessivePronoun, 'my');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/forms/form1_data_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the assembler**

Create `lib/features/forms/form1_data.dart`:

```dart
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';

class Researcher {
  const Researcher({required this.name, required this.isLeader});
  final String name;
  final bool isLeader;
}

class ConformeRow {
  const ConformeRow({
    required this.name,
    required this.role,
    required this.status,
  });
  final String name;
  final String role;
  final String status;
}

class ExOfficioEntry {
  const ExOfficioEntry({required this.name, required this.role});
  final String name;
  final String role;
}

/// Everything Form 1 prints, shaped once so the PDF layer holds no logic.
class Form1Data {
  const Form1Data({
    required this.thesis,
    required this.researchers,
    required this.adviserName,
    required this.panelNames,
    required this.conformeRows,
    required this.exOfficioEntries,
    required this.coordinatorName,
    required this.deanName,
    required this.submittedOn,
  });

  final Thesis thesis;
  final List<Researcher> researchers;
  final String adviserName;
  final List<String> panelNames;
  final List<ConformeRow> conformeRows;
  final List<ExOfficioEntry> exOfficioEntries;
  final String? coordinatorName;
  final String? deanName;
  final DateTime submittedOn;

  /// Several researchers sign, so the printed form's singular reads wrongly.
  String get subjectPronoun => researchers.length > 1 ? 'We' : 'I';
  String get possessivePronoun => researchers.length > 1 ? 'our' : 'my';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  static Form1Data assemble({
    required Thesis thesis,
    required List<Nomination> nominations,
    required String leaderName,
    required Map<String, String> directoryNames,
  }) {
    final nominated = nominations.where((n) => !n.exOfficio).toList();
    final exOfficio = nominations.where((n) => n.exOfficio).toList();

    final adviser = nominated
        .where((n) => n.position == NominationPosition.adviser)
        .toList();
    final panel = nominated
        .where((n) => n.position == NominationPosition.panelist)
        .toList();

    String roleLabel(Nomination n) => switch (n.position) {
          NominationPosition.adviser => 'Thesis Adviser',
          NominationPosition.panelist => 'Panel Member',
          NominationPosition.coordinator =>
            'Research Coordinator (ex officio)',
          NominationPosition.dean => 'Dean (ex officio)',
        };

    final rows = <ConformeRow>[
      for (final n in [...adviser, ...panel])
        ConformeRow(
          name: n.nomineeName,
          role: roleLabel(n),
          status: n.conformeStatus == ConformeStatus.accepted
              ? 'Accepted · ${_stamp(n.respondedAt)} — via eThesisHub'
              : n.conformeStatus.value,
        ),
      for (final n in exOfficio)
        ConformeRow(
          name: n.nomineeName,
          role: roleLabel(n),
          status: 'Ex officio member',
        ),
    ];

    return Form1Data(
      thesis: thesis,
      researchers: [
        Researcher(name: leaderName, isLeader: true),
        for (final m in thesis.memberNames)
          Researcher(name: m, isLeader: false),
      ],
      adviserName: adviser.isEmpty ? '' : adviser.first.nomineeName,
      panelNames: panel.map((n) => n.nomineeName).toList(),
      conformeRows: rows,
      exOfficioEntries: [
        for (final n in exOfficio)
          ExOfficioEntry(name: n.nomineeName, role: roleLabel(n)),
      ],
      coordinatorName: _nameFor(
          thesis.coordinatorRecommendedBy, directoryNames, exOfficio),
      deanName:
          _nameFor(thesis.deanApprovedBy, directoryNames, exOfficio),
      submittedOn: thesis.createdAt,
    );
  }

  /// Prefer the directory, fall back to the ex officio entry already on the
  /// thesis. Written as a loop rather than `firstOrNull`, which lives in
  /// `package:collection` and is not a dependency here.
  static String? _nameFor(
    String? uid,
    Map<String, String> directoryNames,
    List<Nomination> exOfficio,
  ) {
    if (uid == null) return null;
    final fromDirectory = directoryNames[uid];
    if (fromDirectory != null) return fromDirectory;
    for (final n in exOfficio) {
      if (n.nomineeUid == uid) return n.nomineeName;
    }
    return null;
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/features/forms/form1_data_test.dart`
Expected: PASS, all five tests

- [ ] **Step 5: Commit**

```bash
git add lib/features/forms/form1_data.dart test/features/forms/form1_data_test.dart
git commit -m "feat: assemble Form 1 data"
```

---

## Task 13: Form 1 PDF

**Files:**
- Create: `lib/features/forms/form1_pdf.dart`
- Modify: `pubspec.yaml`
- Test: `test/features/forms/form1_pdf_test.dart`

**Interfaces:**
- Consumes: `Form1Data`
- Produces: `Future<Uint8List> buildForm1Pdf(Form1Data data)`

Layout per spec §7.3: no rules above names, ~22px signing space, researchers stacked under the closing, ex officio entries after the nominated members.

- [ ] **Step 1: Add the dependency**

```bash
flutter pub add pdf printing
```

- [ ] **Step 2: Write the failing test**

Create `test/features/forms/form1_pdf_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';

void main() {
  test('produces a non-empty PDF', () async {
    final thesis = Thesis(
      id: 't1', leaderUid: 'l1', memberNames: const ['Bagsain, Karlo June'],
      workingTitle: 'eThesisHub', college: 'CICT', program: 'BSIT',
      semester: 'First', academicYear: '2026-2027',
      status: ThesisStatus.nominationApproved,
      panelistUids: const ['p1', 'p2', 'p3'],
      createdAt: DateTime.utc(2026, 8, 14), adviserUid: 'a1',
    );

    final data = Form1Data.assemble(
      thesis: thesis,
      nominations: [
        Nomination(
            nomineeUid: 'a1', nomineeName: 'Dr. Armada',
            position: NominationPosition.adviser, exOfficio: false,
            conformeStatus: ConformeStatus.accepted,
            respondedAt: DateTime.utc(2026, 8, 14, 10, 22)),
        for (final p in ['p1', 'p2', 'p3'])
          Nomination(
              nomineeUid: p, nomineeName: 'Dr. $p',
              position: NominationPosition.panelist, exOfficio: false,
              conformeStatus: ConformeStatus.accepted,
              respondedAt: DateTime.utc(2026, 8, 14, 11, 0)),
        Nomination(
            nomineeUid: 'd1', nomineeName: 'Dr. Siason',
            position: NominationPosition.dean, exOfficio: true,
            conformeStatus: ConformeStatus.exOfficio),
      ],
      leaderName: 'Karl Joshua P. Vargas',
      directoryNames: const {},
    );

    final bytes = await buildForm1Pdf(data);
    expect(bytes.length, greaterThan(1000));
    // Every PDF starts with %PDF.
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/forms/form1_pdf_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 4: Implement the PDF**

Create `lib/features/forms/form1_pdf.dart`:

```dart
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ethesishub/features/forms/form1_data.dart';

const _accent = PdfColor.fromInt(0xFF0B5FA5);
const _green = PdfColor.fromInt(0xFF15803D);

/// A name with clear space above it to sign into. No rule — the spec
/// deliberately leaves the signing area blank.
pw.Widget _signable(String name, String role,
    {String? status, bool bold = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Expanded(
          flex: 58,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 22),
              pw.Text(name,
                  style: pw.TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text(role,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
        ),
        if (status != null)
          pw.Expanded(
            flex: 42,
            child: pw.Text(status,
                textAlign: pw.TextAlign.right,
                style: const pw.TextStyle(fontSize: 9, color: _green)),
          ),
      ],
    ),
  );
}

Future<Uint8List> buildForm1Pdf(Form1Data data) async {
  final doc = pw.Document();
  final t = data.thesis;

  final panelSentence = data.panelNames.length <= 1
      ? data.panelNames.join()
      : '${data.panelNames.sublist(0, data.panelNames.length - 1).join(', ')} '
          'and ${data.panelNames.last}';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 26, 40, 26),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('RD-30-06/24-04',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Column(children: [
              pw.Text('Republic of the Philippines',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text(
                  'ILOILO STATE UNIVERSITY OF FISHERIES SCIENCE AND TECHNOLOGY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _accent)),
              pw.Text('RESEARCH AND DEVELOPMENT',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text('Tiwi, Barotac Nuevo, Iloilo | research@isufst.edu.ph',
                  style: const pw.TextStyle(fontSize: 8.5)),
            ]),
          ),
          pw.SizedBox(height: 5),
          pw.Container(height: 2, color: _accent),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Form 1. Nomination of Thesis Adviser and Panel Members',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('Ref. ${t.id.substring(0, 8).toUpperCase()}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey700)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
                '${data.submittedOn.day} ${_month(data.submittedOn.month)} '
                '${data.submittedOn.year}'),
          ),
          pw.SizedBox(height: 10),
          pw.Text('The Dean'),
          pw.Text('College of ${t.college}'),
          pw.Text('Iloilo State University of Fisheries Science and Technology'),
          pw.Text('Barotac Nuevo, Iloilo'),
          pw.SizedBox(height: 10),
          pw.Text('Sir/Madam:'),
          pw.SizedBox(height: 6),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 30),
            child: pw.Text(
              '${data.subjectPronoun} have the honor to nominate Prof./Inst. '
              '${data.adviserName.toUpperCase()} to be '
              '${data.possessivePronoun} Undergraduate Thesis Adviser this '
              '${t.semester.toUpperCase()} semester, Academic Year '
              '${t.academicYear}.',
              textAlign: pw.TextAlign.justify,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 30),
            child: pw.Text(
              'Furthermore, ${data.subjectPronoun.toLowerCase()} '
              '${data.researchers.length > 1 ? "are" : "am"} nominating '
              'Prof./Inst. ${panelSentence.toUpperCase()} to be '
              '${data.possessivePronoun} panel members.',
              textAlign: pw.TextAlign.justify,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 30),
            child: pw.Text(
                'Your approval on this matter is highly appreciated.'),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Very truly yours,',
                    style: const pw.TextStyle(fontSize: 11)),
                for (final r in data.researchers) ...[
                  pw.SizedBox(height: 20),
                  pw.Text(r.name.toUpperCase(),
                      style: pw.TextStyle(
                          fontSize: 11.5,
                          fontWeight: r.isLeader
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal)),
                  pw.Text(
                      r.isLeader ? 'Researcher · Group Leader' : 'Researcher',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey700)),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Text('Conforme:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          for (final row in data.conformeRows)
            _signable(row.name, row.role, status: row.status),
          if (data.coordinatorName != null) ...[
            pw.Text('Recommending Approval:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _signable(data.coordinatorName!, 'College Research Coordinator',
                status: 'Recommended · '
                    '${_stampOf(t.coordinatorRecommendedAt)}'),
          ],
          if (data.deanName != null) ...[
            pw.Text('Approved:',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            _signable(data.deanName!, 'Dean, College of ${t.college}',
                status: 'Approved · ${_stampOf(t.deanApprovedAt)}'),
          ],
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blue100),
              color: PdfColors.blue50,
            ),
            child: pw.Text(
              'Electronically completed in eThesisHub. Acceptances recorded '
              'against verified institutional accounts.',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Integrity  ·  Social Justice  ·  Discipline  ·  Academic Excellence',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

String _month(int m) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ][m - 1];

String _stampOf(DateTime? d) {
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${_month(d.month).substring(0, 3)} ${d.year}, '
      '${two(d.hour)}:${two(d.minute)}';
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/features/forms/`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/features/forms/form1_pdf.dart pubspec.yaml pubspec.lock test/features/forms/form1_pdf_test.dart
git commit -m "feat: generate Form 1 as a PDF"
```

---

## Task 14: Student thesis status screen with Form 1 download

**Files:**
- Create: `lib/features/thesis/thesis_status_screen.dart`
- Test: `test/features/thesis/thesis_status_screen_test.dart`

**Interfaces:**
- Consumes: `myThesisProvider`, `thesisRepositoryProvider`, `currentUserProvider`, `buildForm1Pdf`, `Form1Data`
- Produces: `ThesisStatusScreen`

Shows the stage, each nominee's Conforme state, a re-nominate action on declined slots, and a Download Form 1 button once approved.

- [ ] **Step 1: Write the failing test**

Create `test/features/thesis/thesis_status_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/thesis/thesis_status_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded(String status) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('leader-1').set({
    'fullName': 'Karl Joshua P. Vargas', 'email': 'l@isufst.edu.ph',
    'role': 'student', 'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': ['p1'],
    'adviserUid': 'a1', 'memberNames': ['Bagsain, Karlo June'],
    'workingTitle': 'eThesisHub', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  final noms = db.collection('theses').doc('t1').collection('nominations');
  await noms.doc('a1').set({
    'nomineeName': 'Dr. Armada', 'position': 'adviser', 'exOfficio': false,
    'conformeStatus': 'declined', 'respondedAt': null,
    'declineReason': 'At capacity',
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: const MaterialApp(home: ThesisStatusScreen()),
    );

void main() {
  testWidgets('shows a declined slot with its reason', (tester) async {
    await tester.pumpWidget(wrap(await seeded('nominationPendingConforme')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dr. Armada'), findsOneWidget);
    expect(find.textContaining('Declined'), findsOneWidget);
    expect(find.textContaining('At capacity'), findsOneWidget);
  });

  testWidgets('Form 1 download appears only once approved', (tester) async {
    await tester.pumpWidget(wrap(await seeded('nominationPendingConforme')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloadForm1')), findsNothing);

    await tester.pumpWidget(wrap(await seeded('nominationApproved')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloadForm1')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/thesis/thesis_status_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the screen**

Create `lib/features/thesis/thesis_status_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

class ThesisStatusScreen extends ConsumerWidget {
  const ThesisStatusScreen({super.key});

  static String label(ThesisStatus s) => switch (s) {
        ThesisStatus.draft => 'Draft — nominate your adviser and panel',
        ThesisStatus.nominationPendingConforme =>
          'Waiting for nominees to accept',
        ThesisStatus.nominationPendingCoordinator =>
          'Waiting for the Research Coordinator',
        ThesisStatus.nominationPendingDean => 'Waiting for the Dean',
        ThesisStatus.nominationApproved => 'Nomination approved',
      };

  Future<void> _download(
      WidgetRef ref, Thesis thesis, List<Nomination> nominations) async {
    final leader =
        await ref.read(userRepositoryProvider).fetchUser(thesis.leaderUid);
    final data = Form1Data.assemble(
      thesis: thesis,
      nominations: nominations,
      leaderName: leader?.fullName ?? '',
      directoryNames: const {},
    );
    final bytes = await buildForm1Pdf(data);
    await Printing.sharePdf(bytes: bytes, filename: 'Form1-${thesis.id}.pdf');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesisAsync = ref.watch(myThesisProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My thesis')),
      body: thesisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load your thesis.')),
        data: (thesis) {
          if (thesis == null) {
            return const Center(
                child: Text('You have not created a thesis group yet.'));
          }
          return StreamBuilder<List<Nomination>>(
            stream: ref
                .read(thesisRepositoryProvider)
                .watchNominations(thesis.id),
            builder: (context, snap) {
              final nominations = snap.data ?? const <Nomination>[];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(thesis.workingTitle,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(label(thesis.status)),
                  const SizedBox(height: 16),
                  if (nominations.isNotEmpty)
                    Text('Panel',
                        style: Theme.of(context).textTheme.titleMedium),
                  for (final n in nominations)
                    ListTile(
                      dense: true,
                      title: Text(n.nomineeName),
                      subtitle: Text(n.exOfficio
                          ? '${n.position.value} · ex officio'
                          : n.position.value),
                      trailing: Text(
                        switch (n.conformeStatus) {
                          ConformeStatus.accepted => 'Accepted',
                          ConformeStatus.declined =>
                            'Declined — ${n.declineReason ?? ''}',
                          ConformeStatus.exOfficio => 'Ex officio',
                          ConformeStatus.pending => 'Pending',
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (thesis.status == ThesisStatus.nominationApproved)
                    FilledButton.icon(
                      key: const Key('downloadForm1'),
                      icon: const Icon(Icons.download),
                      label: const Text('Download Form 1'),
                      onPressed: () => _download(ref, thesis, nominations),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Add re-nomination of a declined slot**

Spec §5 requires a declined slot to return to the student while accepted
Conformes stand. Add to `ThesisRepository`:

```dart
  /// Clears a declined slot so the leader can nominate someone else.
  /// Accepted Conformes on other slots are untouched.
  Future<void> withdrawDeclinedNomination({
    required String thesisId,
    required String nomineeUid,
  }) async {
    await _nominations(thesisId).doc(nomineeUid).delete();
  }

  /// Nominates a replacement into an empty slot.
  Future<void> addPanelist({
    required String thesisId,
    required FacultyDirectoryEntry replacement,
  }) async {
    await _nominations(thesisId).doc(replacement.uid).set({
      'nomineeName': replacement.fullName,
      'position': NominationPosition.panelist.value,
      'exOfficio': false,
      'conformeStatus': ConformeStatus.pending.value,
      'respondedAt': null,
      'declineReason': null,
    });
  }
```

The rules from Task 7 already permit the leader to delete a nomination whose
`conformeStatus` is `declined`, and nothing else.

- [ ] **Step 5: Wire the re-nominate action into the status screen**

In the nomination `ListTile`, when `n.conformeStatus == ConformeStatus.declined`
and the signed-in user is the leader, show a trailing action that calls
`withdrawDeclinedNomination`, then routes to `/thesis/nominate?id=<thesisId>`:

```dart
                      onTap: n.conformeStatus == ConformeStatus.declined
                          ? () async {
                              await ref
                                  .read(thesisRepositoryProvider)
                                  .withdrawDeclinedNomination(
                                    thesisId: thesis.id,
                                    nomineeUid: n.nomineeUid,
                                  );
                            }
                          : null,
```

- [ ] **Step 6: Add the re-nomination test**

Append to `thesis_status_screen_test.dart`:

```dart
  testWidgets('withdrawing a declined slot removes it', (tester) async {
    final db = await seeded('nominationPendingConforme');
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Dr. Armada'));
    await tester.pumpAndSettle();

    final noms = await db
        .collection('theses').doc('t1').collection('nominations').get();
    expect(noms.docs, isEmpty);
  });
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/features/thesis/thesis_status_screen_test.dart`
Expected: PASS, all three tests

- [ ] **Step 8: Commit**

```bash
git add lib/features/thesis/thesis_status_screen.dart lib/data/repositories/thesis_repository.dart test/features/thesis/thesis_status_screen_test.dart
git commit -m "feat: thesis status screen, Form 1 download and re-nomination"
```

---

## Task 15: Routing and dashboard wiring

**Files:**
- Modify: `lib/core/routing/app_router.dart`, `lib/features/dashboard/student_dashboard.dart`, `faculty_dashboard.dart`, `coordinator_dashboard.dart`, `dean_dashboard.dart`
- Test: `test/core/routing/m1a_routes_test.dart`

**Interfaces:**
- Produces: routes `/thesis/create`, `/thesis/nominate`, `/thesis`, `/nominations`, `/review`

Every screen built so far is unreachable until this task. **A screen with no route does not exist** — this was a blocking defect in the skeleton, caught only by manual testing.

- [ ] **Step 1: Write the failing test**

Create `test/core/routing/m1a_routes_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderContainer> containerFor(String role, String uid) async {
  final db = FakeFirebaseFirestore();
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
  testWidgets('a student can reach the create-thesis screen', (tester) async {
    final c = await containerFor('student', 'u1');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/thesis/create');
    await tester.pumpAndSettle();
    expect(find.text('Create thesis group'), findsOneWidget);
  });

  testWidgets('a faculty member can reach the nomination inbox',
      (tester) async {
    final c = await containerFor('faculty', 'u2');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/nominations');
    await tester.pumpAndSettle();
    expect(find.text('Nomination inbox'), findsOneWidget);
  });

  testWidgets('a student cannot reach the review queue', (tester) async {
    final c = await containerFor('student', 'u3');
    addTearDown(c.dispose);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
    await tester.pumpAndSettle();

    c.read(goRouterProvider).go('/review');
    await tester.pumpAndSettle();
    expect(find.text('Nomination recommendations'), findsNothing);
    expect(find.text('My Thesis'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/routing/m1a_routes_test.dart`
Expected: FAIL — routes not defined

- [ ] **Step 3: Add the routes**

In `lib/core/routing/app_router.dart`, add to the `routes` list:

```dart
      GoRoute(
        path: '/thesis/create',
        builder: (context, state) => const CreateThesisScreen(),
      ),
      GoRoute(
        path: '/thesis',
        builder: (context, state) => const ThesisStatusScreen(),
      ),
      GoRoute(
        path: '/thesis/nominate',
        builder: (context, state) =>
            NominateScreen(thesisId: state.uri.queryParameters['id']!),
      ),
      GoRoute(
        path: '/nominations',
        builder: (context, state) => const NominationInboxScreen(),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) {
          final profile = ref.read(currentUserProvider).value;
          final isDean = profile?.role == UserRole.dean;
          return ReviewQueueScreen(
            queue: isDean
                ? ThesisStatus.nominationPendingDean
                : ThesisStatus.nominationPendingCoordinator,
            isDean: isDean,
          );
        },
      ),
```

- [ ] **Step 4: Extend the role guard**

In the redirect callback, after the existing cross-role dashboard block, add:

```dart
      // M1a screens are role-scoped. A wrong-role user goes to their own home
      // rather than seeing an empty or forbidden screen.
      const studentOnly = ['/thesis', '/thesis/create', '/thesis/nominate'];
      if (studentOnly.any(location.startsWith) &&
          profile.role != UserRole.student) {
        return home;
      }
      if (location.startsWith('/nominations') &&
          profile.role == UserRole.student) {
        return home;
      }
      if (location.startsWith('/review') &&
          profile.role != UserRole.coordinator &&
          profile.role != UserRole.dean) {
        return home;
      }
```

Note `/nominations` is open to faculty, coordinators and deans — a coordinator
nominated as a panel member on another group still needs their inbox.

- [ ] **Step 5: Wire the dashboards**

Add a navigation action to each dashboard's body. For `student_dashboard.dart`:

```dart
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('My Thesis'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('goToThesis'),
              onPressed: () => context.go('/thesis'),
              child: const Text('My thesis'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('goToCreateThesis'),
              onPressed: () => context.go('/thesis/create'),
              child: const Text('Create group'),
            ),
          ],
        ),
      ),
```

Apply the same shape to the others, keeping each dashboard's existing heading
text so the Task 12 routing tests still pass:

- `faculty_dashboard.dart` — keep `My Advisees`, add a `goToInbox` button to `/nominations`
- `coordinator_dashboard.dart` — keep `All Theses`, add a `goToReview` button to `/review`
- `dean_dashboard.dart` — keep `College Overview`, add a `goToReview` button to `/review`

Import `package:go_router/go_router.dart` in each.

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS, all tests including the earlier routing tests

- [ ] **Step 7: Verify the guard actually guards**

Temporarily remove the `/review` role guard block added in Step 4, confirm the
third test ("a student cannot reach the review queue") **fails**, restore it, and
confirm it passes again. Report what you observed.

A guard test that cannot detect the guard's absence is worthless, and that
mistake has already been made three times on this project.

- [ ] **Step 8: Commit**

```bash
git add lib/core/routing/app_router.dart lib/features/dashboard/ test/core/routing/m1a_routes_test.dart
git commit -m "feat: route and link every M1a screen"
```

---

## Task 16: End-to-end verification

**Files:**
- Create: `docs/superpowers/plans/m1a-verification.md`

**Interfaces:**
- Consumes: everything above

- [ ] **Step 1: Run everything**

```bash
flutter analyze
flutter test
export JAVA_HOME="/c/Program Files/Eclipse Adoptium/jdk-21.0.12.8-hotspot"
export PATH="$JAVA_HOME/bin:$PATH"
cd rules-test && npm test && cd ..
```

Expected: no analyzer errors beyond the two known style infos; all Dart tests pass; all rules tests pass.

- [ ] **Step 2: Backfill the faculty directory**

Existing faculty accounts have no directory entry until they next sign in. For each faculty account, either sign in once, or create `facultyDirectory/{uid}` by hand in the Console with `fullName`, `role`, `college`, `specialization`.

Confirm at least four faculty entries exist, or the nomination picker cannot offer three panel members plus an adviser.

- [ ] **Step 3: Walk the flow**

```bash
flutter run -d chrome
```

As a student: create a group with two member names, then nominate one adviser and three panel members. Confirm the coordinator and dean appear read-only and are absent from every dropdown.

As each nominated faculty member: open the inbox and accept. After the last acceptance, confirm the thesis moves to *Waiting for the Research Coordinator*.

As the coordinator: recommend. As the dean: approve.

As the student: confirm the panel shows all six people with the dean and coordinator marked ex officio, and download Form 1.

- [ ] **Step 4: Check Form 1**

Confirm it shows all researchers with the leader first, plural wording, the full panel including ex officio entries, blank signing space above every name, and the coordinator and dean blocks with their recorded timestamps.

- [ ] **Step 5: Confirm a student cannot escalate**

Signed in as a student, in the browser console:

```javascript
const { getFirestore, doc, updateDoc } = await import(
  "https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore.js");
const { getAuth } = await import(
  "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js");
const db = getFirestore(); const uid = getAuth().currentUser.uid;
try {
  await updateDoc(doc(db, "theses", "PUT_THESIS_ID_HERE"),
    { status: "nominationApproved", adviserUid: uid, panelistUids: ["x","y","z"] });
  console.error("SECURITY FAILURE: student approved their own nomination");
} catch (e) { console.log("Correctly denied:", e.code); }
```

Expected: `Correctly denied: permission-denied`.

- [ ] **Step 6: Record the results**

Write `docs/superpowers/plans/m1a-verification.md` listing each exit criterion with its outcome and the date, following the format of `skeleton-verification.md`.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/plans/m1a-verification.md
git commit -m "docs: record M1a verification"
```
