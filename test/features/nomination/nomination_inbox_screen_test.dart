import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/features/nomination/nomination_inbox_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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
    'nomineeUid': 'fac-1',
    'nomineeName': 'Dr. Armada', 'position': 'adviser', 'exOfficio': false,
    'conformeStatus': 'pending', 'respondedAt': null, 'declineReason': null,
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db,
        {String uid = 'fac-1', ThesisRepository? repository}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: uid, email: 'f@isufst.edu.ph', isEmailVerified: true),
        )),
        if (repository != null)
          thesisRepositoryProvider.overrideWithValue(repository),
      ],
      // the app shell supplies the Scaffold in the real app.
      child: const MaterialApp(
        home: Scaffold(body: NominationInboxScreen()),
      ),
    );

/// The inbox lists both a title and (potentially several) action rows; the
/// default 800x600 test surface can leave content below the fold. Matches
/// the `useTallSurface` pattern from `nominate_screen_test.dart`.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

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

    // Falsifiability: this must fail if the reason requirement is deleted —
    // it targets the screen's own keyed error banner, not a label that
    // exists regardless (see task brief's warning about
    // `find.textContaining('Working title')` matching a field's own
    // always-present labelText).
    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('reason'));

    final nom = await db
        .collection('theses').doc('t1')
        .collection('nominations').doc('fac-1').get();
    expect(nom.data()!['conformeStatus'], 'pending');
  });

  testWidgets(
      'an ex officio seat is absent from the inbox, but a by-name adviser '
      'nomination for the same person is present', (tester) async {
    final db = FakeFirebaseFirestore();
    // Same person (fac-1) holds an ex-officio seat on t1 (never asked) and
    // is separately nominated by name as adviser on t2 (must be asked).
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'leader-1', 'status': 'nominationPendingConforme',
      'panelistUids': [], 'adviserUid': null, 'memberNames': [],
      'workingTitle': 'Ex Officio Thesis', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    await db
        .collection('theses').doc('t1')
        .collection('nominations').doc('fac-1')
        .set({
      'nomineeUid': 'fac-1',
      'nomineeName': 'Dr. Coordinator', 'position': 'coordinator',
      'exOfficio': true, 'conformeStatus': 'exOfficio', 'respondedAt': null,
      'declineReason': null,
    });
    await db.collection('theses').doc('t2').set({
      'leaderUid': 'leader-2', 'status': 'nominationPendingConforme',
      'panelistUids': [], 'adviserUid': null, 'memberNames': [],
      'workingTitle': 'By Name Adviser Thesis', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    await db
        .collection('theses').doc('t2')
        .collection('nominations').doc('fac-1')
        .set({
      'nomineeUid': 'fac-1',
      'nomineeName': 'Dr. Coordinator', 'position': 'adviser',
      'exOfficio': false, 'conformeStatus': 'pending', 'respondedAt': null,
      'declineReason': null,
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    // Falsifiability: fails if the ex-officio filter is deleted, because
    // then both keys would exist.
    expect(find.byKey(const Key('accept-t1')), findsNothing);
    expect(find.byKey(const Key('accept-t2')), findsOneWidget);
  });

  testWidgets(
      'a StateError from a stale tab (thesis already advanced) is shown as '
      'a human message, and the button re-enables so the user can retry',
      (tester) async {
    final db = FakeFirebaseFirestore();
    // The thesis has already advanced past nominationPendingConforme (e.g.
    // the last co-nominee's accept already flipped it), but this nominee's
    // own doc is still 'pending' and so still surfaces in the inbox. That
    // combination is exactly what makes respondToNomination throw
    // StateError when this stale tab finally taps Accept.
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'leader-1', 'status': 'nominationPendingCoordinator',
      'panelistUids': [], 'adviserUid': null, 'memberNames': [],
      'workingTitle': 'Stale Tab Thesis', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    await db
        .collection('theses').doc('t1')
        .collection('nominations').doc('fac-1')
        .set({
      'nomineeUid': 'fac-1',
      'nomineeName': 'Dr. Armada', 'position': 'panelist', 'exOfficio': false,
      'conformeStatus': 'pending', 'respondedAt': null, 'declineReason': null,
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accept-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, isNot(contains('StateError')));
    expect(error.data!.toLowerCase(), contains('already'));

    // Falsifiability for "loading state cleared on every path": if busy
    // state were never reset in the StateError branch, the button would
    // stay disabled forever.
    final acceptButton =
        tester.widget<FilledButton>(find.byKey(const Key('accept-t1')));
    expect(acceptButton.onPressed, isNotNull,
        reason: 'busy state must be cleared even when respondToNomination '
            'throws StateError, so a retry is possible');
  });

  testWidgets(
      'the accept button disables itself immediately after being tapped, '
      'so a double tap cannot send two responses', (tester) async {
    final db = await seeded();
    // The fake repository call otherwise resolves within the same
    // microtask flush as a single tester.pump(), which would make this
    // test pass regardless of whether the busy guard exists. Delaying the
    // underlying write keeps the response genuinely "in flight" across one
    // pump so the assertion below is actually falsifiable. flutter_test
    // fakes the clock for Future.delayed, so a bare `pump()` (no duration)
    // does not advance it — only `pumpAndSettle()` below does.
    await tester.pumpWidget(
        wrap(db, repository: _SlowThesisRepository(db)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('accept-t1')));
    // One pump only — deliberately not settled, so the async response is
    // still in flight and busy state, if wired, must already be visible.
    await tester.pump();

    final acceptButton =
        tester.widget<FilledButton>(find.byKey(const Key('accept-t1')));
    expect(acceptButton.onPressed, isNull,
        reason: 'a second tap while the first response is still in flight '
            'must be impossible, not merely harmless');

    await tester.pumpAndSettle();

    final nom = await db
        .collection('theses').doc('t1')
        .collection('nominations').doc('fac-1').get();
    expect(nom.data()!['conformeStatus'], 'accepted');
  });
}

/// Delays `respondToNomination` behind a real `Future.delayed`, which
/// `flutter_test`'s fake clock only advances on `pumpAndSettle` (or an
/// explicit duration), not on a bare `pump()`. Without this, the fake
/// Firestore write resolves within the same microtask flush as a single
/// `pump()`, which would make the double-tap-guard test pass even if the
/// guard in `NominationInboxScreen` were deleted.
class _SlowThesisRepository extends ThesisRepository {
  _SlowThesisRepository(super.db);

  @override
  Future<void> respondToNomination({
    required String thesisId,
    required String nomineeUid,
    required bool accept,
    String? declineReason,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.respondToNomination(
      thesisId: thesisId,
      nomineeUid: nomineeUid,
      accept: accept,
      declineReason: declineReason,
    );
  }
}
