import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Task 9 fix round 2 (whole-branch review, IMPORTANT 1+2). `NeedsYouQueue`
/// decides `push` vs `go` per row on `NeedsYouItem.deep`
/// (`lib/core/widgets/needs_you_queue.dart:114-116`).
///
/// Round 1 pinned that flag against `_isDeepRoute`, a hand-written
/// restatement of "the five deep routes named in the Task 9 brief" -- which
/// is exactly the enumeration the implementation itself was built against,
/// so the test could never disagree with the bug: both were reading off the
/// same wrong list. `/review` (no destination anywhere owns it) and
/// `/thesis/chapters` read by a role that holds no Chapters destination
/// (an adviser, a dean, a coordinator) both shipped `deep: false` and
/// neither test nor implementation noticed.
///
/// This now asserts against [isDeepForRole] -- the same ownership test
/// `AppShell` itself runs to decide the back control -- rather than a
/// second hand-written list. A new row wired with the wrong flag still
/// fails automatically, but now it fails against the actual definition of
/// "deep", not a copy of it.

/// Stands in for [documentRepositoryProvider] without touching Firestore:
/// the base [DocumentRepository] only needs *a* [FirebaseFirestore], never
/// used here, since every read below is served straight from [_chapters].
class _FakeDocumentRepository extends DocumentRepository {
  _FakeDocumentRepository(this._chapters) : super(FakeFirebaseFirestore());

  final Map<String, List<ThesisChapter>> _chapters;

  @override
  Stream<List<ThesisChapter>> watchChapters(String thesisId) =>
      Stream.value(_chapters[thesisId] ?? const []);
}

/// Provider-level, not widget-level, deliberately.
///
/// The three widget tests named "a loading queue is distinguishable from an
/// empty one" each override the very provider under test with their own
/// never-emitting stream, so they exercise `NeedsYouQueue` and say nothing
/// about the fan-ins. These do the opposite: they drive the real fan-in
/// with controlled sources and read the provider's own `AsyncValue`.
///
/// The bug they pin: `ref.listen(..., fireImmediately: true)` hands the
/// listener an `AsyncLoading` VALUE, which is not null. A gate written as
/// `if (source == null) return` therefore passes on the first frame, and
/// `valueOrNull ?? const []` publishes `data([])` -- "Nothing needs you
/// today" before a single snapshot has landed, and forever after a
/// `permission-denied`.

/// Lets every pending microtask and the fan-in's own listeners run.
Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A stream that is subscribed but never produces anything.
Stream<T> never<T>() => StreamController<T>().stream;

/// A minimal world for the evaluation-queue-row tests below: just a faculty
/// profile for `fac-uid`. Each test seeds its own `defenses/d9` document on
/// top of this, since what varies between them is the defence itself.
Future<FakeFirebaseFirestore> seedFacultyWorld() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('fac-uid').set({
    'fullName': 'Dr. Faculty',
    'email': 'fac-uid@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  return db;
}

/// Drives [facultyNeedsYouProvider] off a real (fake) Firestore for [uid],
/// with the nomination and advisee sources stubbed empty -- these tests are
/// only about the evaluation row, so the other three fan-in sources are held
/// still rather than exercised. [currentUserProvider] is stubbed to `null`
/// rather than seeded: `myDefencesProvider` only branches on
/// coordinator/dean/student roles, and a null profile falls through to the
/// same adviser+panelist fan-in a `faculty` role would, without this helper
/// needing to know which uid is signed in ahead of seeding `users/{uid}`.
ProviderContainer facultyContainer(FakeFirebaseFirestore db, String uid) {
  return ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    signedInUidProvider.overrideWithValue(uid),
    currentUserProvider.overrideWith((ref) => Stream.value(null)),
    myPendingNominationsProvider.overrideWith((ref) =>
        Stream.value(const <({String thesisId, Nomination nomination})>[])),
    myAdviseesProvider.overrideWith((ref) => Stream.value(const <Thesis>[])),
  ]);
}

void main() {
  group('facultyNeedsYouProvider', () {
    test('stays loading while its sources are loading, never data([])',
        () async {
      final container = ProviderContainer(overrides: [
        signedInUidProvider.overrideWithValue('f1'),
        myPendingNominationsProvider.overrideWith(
            (ref) => never<List<({String thesisId, Nomination nomination})>>()),
        myAdviseesProvider.overrideWith((ref) => never<List<Thesis>>()),
        myDefencesProvider.overrideWith((ref) => never<List<Defence>>()),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<NeedsYouItem>>>[];
      container.listen(facultyNeedsYouProvider, (_, next) => states.add(next),
          fireImmediately: true);
      await settle();

      expect(container.read(facultyNeedsYouProvider), isA<AsyncLoading>());
      expect(
        states.any((s) => s is AsyncData<List<NeedsYouItem>> && s.value.isEmpty),
        isFalse,
        reason: 'published an empty queue before any source had a snapshot',
      );
    });

    test('surfaces a source error rather than an empty queue', () async {
      final container = ProviderContainer(overrides: [
        signedInUidProvider.overrideWithValue('f1'),
        myPendingNominationsProvider.overrideWith((ref) =>
            Stream<List<({String thesisId, Nomination nomination})>>.error(
                StateError('permission-denied'))),
        myAdviseesProvider.overrideWith((ref) => never<List<Thesis>>()),
        myDefencesProvider.overrideWith((ref) => never<List<Defence>>()),
      ]);
      addTearDown(container.dispose);

      container.listen(facultyNeedsYouProvider, (_, _) {},
          fireImmediately: true);
      await settle();

      expect(container.read(facultyNeedsYouProvider).hasError, isTrue);
    });
  });

  group('facultyNeedsYouProvider: the evaluation queue row', () {
    test('a panelist owes a sheet on a closed, unreleased defence',
        () async {
      final db = await seedFacultyWorld();
      await db.collection('defenses').doc('d9').set({
        'thesisId': 't1', 'type': 'final',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
        'venue': 'AVR', 'panelUids': <String>['fac-uid'],
        'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
        'createdBy': 'c1',
      });
      final c = facultyContainer(db, 'fac-uid');
      addTearDown(c.dispose);

      final items = await c.read(facultyNeedsYouProvider.future);
      final row = items.where((i) => i.chipLabel == 'Evaluate');

      expect(row, hasLength(1));
      expect(row.single.route, '/defence/room/d9/evaluate');
      expect(row.single.title, 'Final defence');
    });

    test('the row goes once that panelist has submitted', () async {
      final db = await seedFacultyWorld();
      await db.collection('defenses').doc('d9').set({
        'thesisId': 't1', 'type': 'final',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
        'venue': 'AVR', 'panelUids': <String>['fac-uid'],
        'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
        'createdBy': 'c1',
      });
      await db
          .collection('defenses')
          .doc('d9')
          .collection('evaluations')
          .doc('fac-uid')
          .set({
        'scores': {for (final cr in evaluationCriteria) cr.key: cr.weight},
        'comments': const <String, String>{},
        'total': 100, 'rating': 'pass',
      });
      final c = facultyContainer(db, 'fac-uid');
      addTearDown(c.dispose);

      final items = await c.read(facultyNeedsYouProvider.future);
      expect(items.where((i) => i.chipLabel == 'Evaluate'), isEmpty);
    });

    test('a released defence owes nothing, submitted or not', () async {
      final db = await seedFacultyWorld();
      await db.collection('defenses').doc('d9').set({
        'thesisId': 't1', 'type': 'final',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
        'venue': 'AVR', 'panelUids': <String>['fac-uid'],
        'adviserUid': 'a1', 'leaderUid': 'l1', 'status': 'completed',
        'createdBy': 'c1',
        'evaluationsReleasedAt':
            Timestamp.fromDate(DateTime(2026, 9, 24)),
      });
      final c = facultyContainer(db, 'fac-uid');
      addTearDown(c.dispose);

      final items = await c.read(facultyNeedsYouProvider.future);
      expect(items.where((i) => i.chipLabel == 'Evaluate'), isEmpty);
    });

    // The adviser is barred from scoring, so they can never owe a sheet --
    // and this is the queue that would otherwise nag them forever.
    test('the adviser is never asked to evaluate', () async {
      final db = await seedFacultyWorld();
      await db.collection('defenses').doc('d9').set({
        'thesisId': 't1', 'type': 'final',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
        'venue': 'AVR', 'panelUids': <String>['p1'],
        'adviserUid': 'fac-uid', 'leaderUid': 'l1', 'status': 'completed',
        'createdBy': 'c1',
      });
      final c = facultyContainer(db, 'fac-uid');
      addTearDown(c.dispose);

      final items = await c.read(facultyNeedsYouProvider.future);
      expect(items.where((i) => i.chipLabel == 'Evaluate'), isEmpty);
    });
  });

  group('deanNeedsYouProvider', () {
    test('stays loading while its sources are loading, never data([])',
        () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingDean)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<NeedsYouItem>>>[];
      container.listen(deanNeedsYouProvider, (_, next) => states.add(next),
          fireImmediately: true);
      await settle();

      expect(container.read(deanNeedsYouProvider), isA<AsyncLoading>());
      expect(
        states.any((s) => s is AsyncData<List<NeedsYouItem>> && s.value.isEmpty),
        isFalse,
        reason: 'published an empty queue before any source had a snapshot',
      );
    });

    test('surfaces a source error rather than an empty queue', () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingDean).overrideWith(
            (ref) => Stream<List<Thesis>>.error(
                StateError('permission-denied'))),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
      ]);
      addTearDown(container.dispose);

      container.listen(deanNeedsYouProvider, (_, _) {}, fireImmediately: true);
      await settle();

      expect(container.read(deanNeedsYouProvider).hasError, isTrue);
    });
  });

  group('coordinatorNeedsYouProvider', () {
    test('stays loading while its sources are loading, never data([])',
        () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titleApproved)
            .overrideWith((ref) => never<List<Thesis>>()),
        allDefencesProvider.overrideWith((ref) => never<List<Defence>>()),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<NeedsYouItem>>>[];
      container.listen(
          coordinatorNeedsYouProvider, (_, next) => states.add(next),
          fireImmediately: true);
      await settle();

      expect(
          container.read(coordinatorNeedsYouProvider), isA<AsyncLoading>());
      expect(
        states.any((s) => s is AsyncData<List<NeedsYouItem>> && s.value.isEmpty),
        isFalse,
        reason: 'published an empty queue before any source had a snapshot',
      );
    });

    test('surfaces a source error rather than an empty queue', () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titleApproved)
            .overrideWith((ref) => never<List<Thesis>>()),
        allDefencesProvider.overrideWith((ref) =>
            Stream<List<Defence>>.error(StateError('permission-denied'))),
      ]);
      addTearDown(container.dispose);

      container.listen(coordinatorNeedsYouProvider, (_, _) {},
          fireImmediately: true);
      await settle();

      expect(container.read(coordinatorNeedsYouProvider).hasError, isTrue);
    });
  });

  group('deep-route classification (Task 9 fix round 1)', () {
    test('facultyNeedsYouProvider: every row\'s deep flag matches its route',
        () async {
      final defenceDue = Defence(
        id: 'd-consolidate',
        thesisId: 't-consolidate',
        type: DefenceType.preOral,
        venue: 'Room 101',
        panelUids: const [],
        adviserUid: 'f1',
        leaderUid: 'leader1',
        status: DefenceStatus.completed,
        createdBy: 'c1',
        // consolidatedAt absent -- still owed, so this is the
        // 'Consolidate' row, route '/defence/{id}', deep: true.
      );
      final defenceInProgress = Defence(
        id: 'd-join',
        thesisId: 't-join',
        type: DefenceType.final_,
        venue: 'Room 102',
        panelUids: const [],
        adviserUid: 'f1',
        leaderUid: 'leader2',
        status: DefenceStatus.inProgress,
        createdBy: 'c1',
        // 'Join' row, route '/defence/{id}', deep: true.
      );
      final advisee = Thesis(
        id: 't-advisee',
        leaderUid: 'leader3',
        memberNames: const [],
        workingTitle: 'A working title',
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
        status: ThesisStatus.titleApproved,
        panelistUids: const [],
        createdAt: DateTime(2026),
      );

      final container = ProviderContainer(overrides: [
        signedInUidProvider.overrideWithValue('f1'),
        myPendingNominationsProvider.overrideWith((ref) => Stream.value([
              (
                thesisId: 't-nom',
                nomination: const Nomination(
                  nomineeUid: 'f1',
                  nomineeName: 'Dr. Faculty',
                  position: NominationPosition.panelist,
                  exOfficio: false,
                  conformeStatus: ConformeStatus.pending,
                ),
              ),
            ])),
        myAdviseesProvider.overrideWith((ref) => Stream.value([advisee])),
        myDefencesProvider
            .overrideWith((ref) => Stream.value([defenceDue, defenceInProgress])),
        documentRepositoryProvider.overrideWithValue(_FakeDocumentRepository({
          // A submitted chapter on the one advisee thesis -- the 'Review'
          // row, route '/thesis/chapters?id=...', deep: true. It is the
          // LIST route, not '/thesis/chapters/:chapterId', but no faculty
          // destination owns '/thesis/chapters' at all -- only a
          // student's sidebar does -- so it is deep for this reader
          // regardless.
          't-advisee': const [
            ThesisChapter(
              id: ChapterId.chapterI,
              currentVersion: 1,
              status: ChapterStatus.submitted,
            ),
          ],
        })),
      ]);
      addTearDown(container.dispose);

      container.listen(facultyNeedsYouProvider, (_, _) {},
          fireImmediately: true);
      await settle();

      final items = container.read(facultyNeedsYouProvider).requireValue;
      // Sanity: the fixture above must actually produce every row shape it
      // claims to, or this test would vacuously pass with an empty list.
      expect(items.length, 4, reason: 'fixture did not emit the expected '
          'nomination + chapter-review + two defence rows: $items');
      for (final item in items) {
        expect(item.deep, isDeepForRole(UserRole.faculty, item.route),
            reason: 'NeedsYouItem.deep=${item.deep} disagrees with the '
                'route shape for "${item.route}" (title: ${item.title})');
      }
    });

    test('deanNeedsYouProvider: every row\'s deep flag matches its route',
        () async {
      final approvalThesis = Thesis(
        id: 't-approval',
        leaderUid: 'leader1',
        memberNames: const [],
        workingTitle: 'Approval-pending thesis',
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
        status: ThesisStatus.nominationPendingDean,
        panelistUids: const [],
        createdAt: DateTime(2026),
      );
      final titleDefenceThesis = Thesis(
        id: 't-defence',
        leaderUid: 'leader2',
        memberNames: const [],
        workingTitle: 'Title-defence-pending thesis',
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
        status: ThesisStatus.titlePendingDefence,
        panelistUids: const [],
        createdAt: DateTime(2026),
      );

      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingDean)
            .overrideWith((ref) => Stream.value([approvalThesis])),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => Stream.value([titleDefenceThesis])),
      ]);
      addTearDown(container.dispose);

      container.listen(deanNeedsYouProvider, (_, _) {}, fireImmediately: true);
      await settle();

      final items = container.read(deanNeedsYouProvider).requireValue;
      expect(items.length, 2,
          reason: 'fixture did not emit the expected approval + title-'
              'defence rows: $items');
      for (final item in items) {
        expect(item.deep, isDeepForRole(UserRole.dean, item.route),
            reason: 'NeedsYouItem.deep=${item.deep} disagrees with the '
                'route shape for "${item.route}" (title: ${item.title})');
      }
    });

    test(
        'coordinatorNeedsYouProvider: every row\'s deep flag matches its '
        'route', () async {
      final recommendation = Thesis(
        id: 't-rec',
        leaderUid: 'leader1',
        memberNames: const [],
        workingTitle: 'Recommendation-pending thesis',
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
        status: ThesisStatus.nominationPendingCoordinator,
        panelistUids: const [],
        createdAt: DateTime(2026),
      );
      final titleDefence = Thesis(
        id: 't-defence',
        leaderUid: 'leader2',
        memberNames: const [],
        workingTitle: 'Title-defence-pending thesis',
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
        status: ThesisStatus.titlePendingDefence,
        panelistUids: const [],
        createdAt: DateTime(2026),
      );
      // Cleared the chapter gate (chapters I-III approved -- proposalReady)
      // and has no scheduled defence yet -- the 'Schedule' row, route
      // '/defence/schedule?id=...', deep: true.
      final readyCandidate = Thesis(
        id: 't-ready',
        leaderUid: 'leader3',
        memberNames: const [],
        workingTitle: 'Ready-for-defence thesis',
        college: 'CICT',
        program: 'BSIT',
        semester: 'First',
        academicYear: '2026-2027',
        status: ThesisStatus.titleApproved,
        panelistUids: const [],
        createdAt: DateTime(2026),
      );

      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator)
            .overrideWith((ref) => Stream.value([recommendation])),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => Stream.value([titleDefence])),
        thesesByStatusProvider(ThesisStatus.titleApproved)
            .overrideWith((ref) => Stream.value([readyCandidate])),
        allDefencesProvider.overrideWith((ref) => Stream.value(const [])),
        documentRepositoryProvider.overrideWithValue(_FakeDocumentRepository({
          't-ready': const [
            ThesisChapter(
              id: ChapterId.chapterI,
              currentVersion: 1,
              status: ChapterStatus.approved,
            ),
            ThesisChapter(
              id: ChapterId.chapterII,
              currentVersion: 1,
              status: ChapterStatus.approved,
            ),
            ThesisChapter(
              id: ChapterId.chapterIII,
              currentVersion: 1,
              status: ChapterStatus.approved,
            ),
          ],
        })),
      ]);
      addTearDown(container.dispose);

      container.listen(coordinatorNeedsYouProvider, (_, _) {},
          fireImmediately: true);
      await settle();

      final items = container.read(coordinatorNeedsYouProvider).requireValue;
      expect(items.length, 3,
          reason: 'fixture did not emit the expected recommendation + '
              'title-defence + schedule rows: $items');
      for (final item in items) {
        expect(item.deep, isDeepForRole(UserRole.coordinator, item.route),
            reason: 'NeedsYouItem.deep=${item.deep} disagrees with the '
                'route shape for "${item.route}" (title: ${item.title})');
      }
    });
  });

  group('deep-route classification is role-dependent, not a fixed list',
      () {
    // The defect this fixes: '/thesis/chapters' IS a destination for a
    // student (once chapters are unlocked) but is NOT one for anybody
    // else, so whether it counts as "deep" must be computed against the
    // reading role's own destination list, never a role-blind list of
    // route shapes.
    test('is NOT deep for a student once chapters are unlocked', () {
      expect(isDeepForRole(UserRole.student, '/thesis/chapters?id=t1'),
          isFalse);
    });

    test('IS deep for a faculty member -- no destination of theirs owns it',
        () {
      expect(
          isDeepForRole(UserRole.faculty, '/thesis/chapters?id=t1'), isTrue);
    });

    test('IS deep for a dean -- no destination of theirs owns it either',
        () {
      expect(isDeepForRole(UserRole.dean, '/thesis/chapters?id=t1'), isTrue);
    });

    test('IS deep for a coordinator, same reason', () {
      expect(isDeepForRole(UserRole.coordinator, '/thesis/chapters?id=t1'),
          isTrue);
    });

    test('/review is deep for every role -- no ShellDestination owns it',
        () {
      for (final role in UserRole.values) {
        expect(isDeepForRole(role, '/review'), isTrue,
            reason: '$role should treat /review as deep');
      }
    });
  });
}
