import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Task 9 fix round 1. `NeedsYouQueue` decides `push` vs `go` per row on
/// `NeedsYouItem.deep` (`lib/core/widgets/needs_you_queue.dart:114-116`),
/// and every provider in this file sets that flag by hand on the rows it
/// builds. Nothing pinned the flag to the route it is attached to, so
/// dropping `deep: true` from a row — or the ternary itself flipping —
/// would fail no test.
///
/// [_isDeepRoute] is an independent restatement of the five deep routes
/// named in the Task 9 brief (`/thesis/chapters/:chapterId`,
/// `/defence/:thesisId`, `/defence/schedule`, `/defence/room/:defenceId`,
/// and its `/consolidated` child), derived from the route's own shape
/// rather than from whatever `deep` says. The tests below walk every item
/// each provider emits and assert the two agree — so a NEW row, wired with
/// the wrong flag, fails automatically without anyone updating a
/// hand-written list of cases.
bool _isDeepRoute(String route) {
  final path = route.split('?').first;
  if (path.startsWith('/thesis/chapters/')) return true;
  if (path == '/defence/schedule') return true;
  if (path.startsWith('/defence/room/')) return true;
  // What remains starting with '/defence/' and not already matched above
  // is '/defence/:thesisId' -- the title-defence panel route.
  if (path.startsWith('/defence/')) return true;
  return false;
}

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
          // row, route '/thesis/chapters?id=...', deep: false (it is the
          // LIST route, not '/thesis/chapters/:chapterId').
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
        expect(item.deep, _isDeepRoute(item.route),
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
        expect(item.deep, _isDeepRoute(item.route),
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
        expect(item.deep, _isDeepRoute(item.route),
            reason: 'NeedsYouItem.deep=${item.deep} disagrees with the '
                'route shape for "${item.route}" (title: ${item.title})');
      }
    });
  });
}
