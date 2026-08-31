import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/repository/archive_queue_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// A thesis `t1` led by `l1`, with a completed FINAL defence `d1`.
///
/// [verdict] is the only signal that the defence passed — the thesis
/// status stays `titleApproved` throughout, because nothing in M2–M4 ever
/// advances it. Pass `null` for a defence that finished without a verdict
/// recorded yet.
///
/// Shared in shape with Task 9's `manuscript_upload_test.dart` `seed()`,
/// copied verbatim per the brief rather than shared across files — the two
/// suites must not share a file.
Future<FakeFirebaseFirestore> seed({
  String? verdict = 'pass',
  bool withManuscript = false,
  bool alreadyArchived = false,
}) async {
  final db = FakeFirebaseFirestore();
  // The brief's given fixture carries no `users` collection at all, and
  // `ArchiveQueueScreen` is a coordinator's screen -- a coordinator with no
  // `users/c1` profile does not resolve as a coordinator anywhere that
  // branches on `currentUserProvider`. Folded into `seed()` itself, in the
  // SAME awaited chain as every other document below, rather than as a
  // separate await inside `app()`: `app()` stays a plain synchronous
  // function this way, matching the codebase's own idiom in
  // `defences_list_test.dart`'s `_seedUser` (one seeding function, fully
  // awaited by the caller before `app(db)` ever runs) rather than adding a
  // second, later await between "data seeded" and "widget pumped".
  await db.collection('users').doc('c1').set({
    'fullName': 'Coordinator One',
    'email': 'c1@isufst.edu.ph',
    'role': 'coordinator',
    'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>['Santos, J.'],
    'workingTitle': 'Working',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'status': 'titleApproved',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    if (withManuscript) ...{
      'manuscriptPath': 'theses/t1/manuscript/abc.pdf',
      'manuscriptUrl': 'https://example.test/abc.pdf',
      'manuscriptAbstract': 'Fish were counted.',
      'manuscriptUploadedAt':
          Timestamp.fromDate(DateTime(2026, 9, 25)),
    },
  });
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR',
    'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': 'completed',
    'createdBy': 'c1',
    'evaluationsReleasedAt':
        Timestamp.fromDate(DateTime(2026, 9, 23, 14)),
    if (verdict != null) ...{
      'panelVerdict': verdict,
      'verdictRecordedBy': 'a1',
      'verdictRecordedAt':
          Timestamp.fromDate(DateTime(2026, 9, 23, 15)),
    },
  });
  if (alreadyArchived) {
    await db.collection('archive').doc('t1').set({
      'title': 'A Study of Coastal Fisheries',
      'memberNames': <String>['Santos, J.'],
      'abstract': 'Fish were counted.',
      'college': 'CICT',
      'program': 'BSIT',
      'academicYear': '2026-2027',
      'adviserName': 'Dr. Zamora',
      'panelNames': <String>['Dr. Reyes'],
      'manuscriptUrl': 'https://example.test/abc.pdf',
      'manuscriptPath': 'theses/t1/manuscript/abc.pdf',
      'finalDefenceId': 'd1',
      'uploadedBy': 'l1',
      'archivedBy': 'c1',
      'archivedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
    });
  }
  return db;
}

/// A bare db carrying only the `users/c1` coordinator profile, for the
/// empty-queue case -- `seed()` is the only place that writes it for every
/// other test, but the empty-queue test deliberately does not go through
/// `seed()` at all.
Future<FakeFirebaseFirestore> emptyCoordinatorDb() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('c1').set({
    'fullName': 'Coordinator One',
    'email': 'c1@isufst.edu.ph',
    'role': 'coordinator',
    'active': true,
  });
  return db;
}

/// [ArchiveQueueScreen] is a coordinator's screen, and the fan-in behind it
/// resolves the signed-in user's role through `currentUserProvider`
/// (indirectly, via anything that branches on it). The `users/c1` profile
/// this needs is written by [seed] (or [emptyCoordinatorDb]) and fully
/// awaited by the caller before `app(db)` ever runs -- exactly
/// `defences_list_test.dart`'s `_seedUser`/`_wrap` split, one seeding
/// function the caller awaits, then a plain synchronous wrapper. Kept
/// `app()` itself synchronous rather than adding a second, later await
/// here: a single `pump()` after `pumpWidget` needs to still catch
/// [archiveQueueProvider] mid-flight for the loading-state test below, and
/// an extra await inside `app()` -- between the data settling and the
/// widget actually mounting -- was observed to let every source resolve
/// before that one `pump()` returns, collapsing the loading state.
Widget app(FakeFirebaseFirestore db) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'c1', email: 'c1@isufst.edu.ph', isEmailVerified: true),
        ),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ArchiveQueueScreen()),
    ),
  );
}

/// A tall surface: matches the repo's own idiom, see
/// `defence_grades_screen_test.dart`.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('lists a passed thesis with a manuscript', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(
        verdict: 'pass', withManuscript: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('queueRow-t1')), findsOneWidget);
  });

  testWidgets('omits a thesis with no manuscript yet', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(
        verdict: 'pass', withManuscript: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('queueRow-t1')), findsNothing);
  });

  testWidgets('omits a thesis that failed its defence', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(
        verdict: 'fail', withManuscript: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('queueRow-t1')), findsNothing);
  });

  testWidgets('omits a thesis already in the archive', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(
        verdict: 'pass', withManuscript: true, alreadyArchived: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('queueRow-t1')), findsNothing);
  });

  testWidgets('publishing removes the row', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(
        verdict: 'pass', withManuscript: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('publish-t1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('queueRow-t1')), findsNothing);
  });

  testWidgets('an empty queue says so, and is not an error', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await emptyCoordinatorDb()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyQueue')), findsOneWidget);
  });

  testWidgets('shows a loading state before the queue resolves',
      (tester) async {
    await tester.pumpWidget(app(await seed(
        verdict: 'pass', withManuscript: true)));
    await tester.pump();

    expect(find.byKey(const Key('queueLoading')), findsOneWidget);
  });
}
