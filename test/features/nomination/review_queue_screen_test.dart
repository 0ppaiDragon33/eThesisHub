import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/features/nomination/review_queue_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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

Widget wrap(FakeFirebaseFirestore db, ThesisStatus queue, bool isDean,
        {ThesisRepository? repository}) =>
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
        if (repository != null)
          thesisRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
          home: ReviewQueueScreen(queue: queue, isDean: isDean)),
    );

/// Matches the `useTallSurface` pattern from `nominate_screen_test.dart` /
/// `nomination_inbox_screen_test.dart` — the default 800x600 test surface
/// can leave the act button below the fold.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('coordinator recommends and records who acted', (tester) async {
    useTallSurface(tester);
    final db = await seeded('nominationPendingCoordinator');
    await tester.pumpWidget(wrap(
        db, ThesisStatus.nominationPendingCoordinator, false));
    await tester.pumpAndSettle();

    // `recommend`'s internal `watchThesis(...).first` read never delivers
    // its event on `fake_cloud_firestore`'s stream under the fake clock that
    // `pump()`/`pumpAndSettle()` alone drive — confirmed empirically (see
    // task-11-report.md): the same tap, awaited only via `pumpAndSettle()`,
    // leaves the write permanently pending and the doc unchanged.
    // `approve`'s transaction (`tx.get()`) does not have this problem, only
    // `recommend`'s plain `.snapshots().first` does. `runAsync` steps outside
    // the fake clock so the real Future actually resolves; this is a
    // test-only accommodation for a `fake_cloud_firestore` limitation, not a
    // change to `ThesisRepository`.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('act-t1')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final t = await db.collection('theses').doc('t1').get();
    expect(t.data()!['status'], 'nominationPendingDean');
    expect(t.data()!['coordinatorRecommendedBy'], 'reviewer-1');
  });

  testWidgets('dean approves and fixes the panel', (tester) async {
    useTallSurface(tester);
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

  testWidgets('approval writes an audit entry with the exact whitelisted '
      'keys and a server timestamp', (tester) async {
    useTallSurface(tester);
    final db = await seeded('nominationPendingDean');
    await tester.pumpWidget(
        wrap(db, ThesisStatus.nominationPendingDean, true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('act-t1')));
    await tester.pumpAndSettle();

    final logs = await db.collection('auditLogs').get();
    expect(logs.docs, hasLength(1));
    final data = logs.docs.first.data();
    expect(data['action'], 'nomination.approved');
    expect(data['actorUid'], 'reviewer-1');
    expect(data['targetType'], 'thesis');
    expect(data['targetId'], 't1');
    expect(
      data.keys,
      unorderedEquals([
        'actorUid', 'action', 'targetType', 'targetId', 'metadata', 'timestamp',
      ]),
      reason: 'auditLogs rules use hasOnly — an extra key breaks every write',
    );
    // Falsifiability: a client DateTime is rejected by the deployed rules
    // (`request.resource.data.timestamp == request.time`); only
    // FieldValue.serverTimestamp() satisfies that, and only that survives a
    // round trip through fake_cloud_firestore as a Timestamp.
    expect(data['timestamp'], isA<Timestamp>());
  });

  testWidgets(
      'a coordinator does not see the dean queue and has no way to approve '
      'from it', (tester) async {
    useTallSurface(tester);
    // Only a thesis pending DEAN review exists. This screen instance is
    // configured as the COORDINATOR queue (nominationPendingCoordinator).
    // Falsifiability: if the screen ignored `widget.queue` and just listed
    // every thesis, 'eThesisHub' and the act button would show up here.
    final db = await seeded('nominationPendingDean');
    await tester.pumpWidget(wrap(
        db, ThesisStatus.nominationPendingCoordinator, false));
    await tester.pumpAndSettle();

    expect(find.text('eThesisHub'), findsNothing);
    expect(find.byKey(const Key('act-t1')), findsNothing);
    expect(find.byKey(const Key('empty')), findsOneWidget);
  });

  testWidgets(
      'a dean does not see the coordinator queue and has no way to '
      'recommend from it', (tester) async {
    useTallSurface(tester);
    // Only a thesis pending COORDINATOR review exists. This screen instance
    // is configured as the DEAN queue (nominationPendingDean).
    final db = await seeded('nominationPendingCoordinator');
    await tester.pumpWidget(
        wrap(db, ThesisStatus.nominationPendingDean, true));
    await tester.pumpAndSettle();

    expect(find.text('eThesisHub'), findsNothing);
    expect(find.byKey(const Key('act-t1')), findsNothing);
    expect(find.byKey(const Key('empty')), findsOneWidget);
  });

  testWidgets(
      'a StateError from a stale queue (someone else already acted) is '
      'shown as a human message, and the button re-enables so the user can '
      'retry', (tester) async {
    useTallSurface(tester);
    final db = await seeded('nominationPendingCoordinator');
    await tester.pumpWidget(wrap(
      db,
      ThesisStatus.nominationPendingCoordinator,
      false,
      repository: _AlwaysStaleThesisRepository(db),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('act-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, isNot(contains('StateError')));
    expect(error.data!.toLowerCase(), contains('already'));

    // Falsifiability for "busy state cleared on every path": if the finally
    // block never ran for the StateError branch, the button would stay
    // disabled forever.
    final actButton =
        tester.widget<FilledButton>(find.byKey(const Key('act-t1')));
    expect(actButton.onPressed, isNotNull,
        reason: 'busy state must be cleared even when recommend/approve '
            'throws StateError, so a retry is possible');
  });

  testWidgets(
      'the act button disables itself immediately after being tapped, so a '
      'double tap cannot send two decisions', (tester) async {
    useTallSurface(tester);
    final db = await seeded('nominationPendingCoordinator');
    await tester.pumpWidget(wrap(
      db,
      ThesisStatus.nominationPendingCoordinator,
      false,
      repository: _SlowThesisRepository(db),
    ));
    await tester.pumpAndSettle();

    // The tap, the intermediate "still busy" check, and the wait for
    // completion are all done inside one `runAsync` block.
    // `_SlowThesisRepository`'s delay and `recommend`'s internal
    // `.snapshots().first` both need a real event-loop tick to resolve (see
    // the comment on the "recommend and records who acted" test above) —
    // splitting the wait across the fake clock (`pump()`) and a separate
    // `runAsync` call left the first Timer parked forever on the fake clock,
    // never reaching the point where the real-only `.snapshots().first`
    // could even be scheduled.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('act-t1')));
      await tester.pump();

      final actButton =
          tester.widget<FilledButton>(find.byKey(const Key('act-t1')));
      expect(actButton.onPressed, isNull,
          reason: 'a second tap while the first decision is still in '
              'flight must be impossible, not merely harmless');

      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    final t = await db.collection('theses').doc('t1').get();
    expect(t.data()!['status'], 'nominationPendingDean');
  });
}

/// Always reports the thesis as already having moved past the stage this
/// screen is meant to act on — simulating a stale queue where another
/// coordinator/dean already acted before this tab's tap lands.
class _AlwaysStaleThesisRepository extends ThesisRepository {
  _AlwaysStaleThesisRepository(super.db);

  @override
  Future<void> recommend({
    required String thesisId,
    required String coordinatorUid,
  }) async {
    throw StateError(
        'Cannot recommend a thesis that is not pending coordinator review.');
  }

  @override
  Future<void> approve({
    required String thesisId,
    required String deanUid,
  }) async {
    throw StateError(
        'Cannot approve a thesis that is not pending dean review.');
  }
}

/// Delays `recommend`/`approve` behind a real `Future.delayed`, keeping the
/// call genuinely in flight across the `tester.pump()` inside the
/// `runAsync` block above. Without this, the fake Firestore write could
/// resolve within the same event-loop turn as that single `pump()`, which
/// would make the double-tap-guard test pass even if the guard in
/// `ReviewQueueScreen` were deleted.
class _SlowThesisRepository extends ThesisRepository {
  _SlowThesisRepository(super.db);

  @override
  Future<void> recommend({
    required String thesisId,
    required String coordinatorUid,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.recommend(thesisId: thesisId, coordinatorUid: coordinatorUid);
  }

  @override
  Future<void> approve({
    required String thesisId,
    required String deanUid,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.approve(thesisId: thesisId, deanUid: deanUid);
  }
}
