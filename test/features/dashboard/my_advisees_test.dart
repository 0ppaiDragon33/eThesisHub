import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Seeds two theses: one advised by `a1`, one advised by `other`. Each has
/// the fields `Thesis.fromMap` requires, matching the shape written by
/// `ThesisRepository.approve` in production.
Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('mine').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'My Advised Thesis', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  await db.collection('theses').doc('notMine').set({
    'leaderUid': 'l2', 'adviserUid': 'other', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'Someone Elses Thesis', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
  });
  return db;
}

/// Without this, `FirebaseAuth.instance` throws `[core/no-app]` because no
/// app is initialised in a widget test, `authStateProvider` settles into
/// AsyncError, and any uid read off it is silently null forever. See
/// adviser_review_test.dart's `_wrap` for the same pattern. sharedPrefsProvider
/// must also be overridden -- facultyModeProvider reads it on every build,
/// and it throws UnimplementedError unless a value is supplied.
Future<Widget> _wrap(FakeFirebaseFirestore db, {required String uid}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: const MaterialApp(home: FacultyDashboard()),
  );
}

void main() {
  testWidgets('an adviser sees only the theses they advise', (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('My Advised Thesis'), findsOneWidget);
    expect(find.text('Someone Elses Thesis'), findsNothing);
  });

  testWidgets('the placeholder copy is gone', (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    // Shipped for two milestones, promising a list that could not exist
    // until the adviser arm on `allow list` (theses) landed. This test is
    // what stops the sentence outliving the feature it was standing in for.
    expect(find.textContaining('Coming with the documents module'),
        findsNothing);
  });

  testWidgets('an adviser with no advisees sees an empty state, not an error',
      (tester) async {
    // No theses at all are seeded for 'lonely' -- an empty query result,
    // not a permission refusal.
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(await _wrap(db, uid: 'lonely'));
    await tester.pumpAndSettle();

    expect(find.text('No advisees yet'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('the advisee list is loading before the first snapshot arrives',
      (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    // Deliberately NOT pumpAndSettle: asserts the loading branch renders
    // before the stream's first snapshot, rather than the empty-list
    // branch. Collapsing loading into an empty data(const []) list would
    // make "still loading" and "no advisees" indistinguishable -- a bug
    // this project has already shipped four times (see the comment on
    // adviseesAsync.when in faculty_dashboard.dart).
    await tester.pump();

    // Both the advisee list and the nomination summary are loading at
    // once, so two spinners are expected -- what matters is that neither
    // has resolved to data or to the empty state yet.
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    expect(find.text('My Advised Thesis'), findsNothing);
    expect(find.text('No advisees yet'), findsNothing);
  });

  testWidgets('an advisee row shows a count of chapters awaiting review',
      (tester) async {
    final db = await _seed();
    await db
        .collection('theses/mine/documents')
        .doc('chapterI')
        .set({'currentVersion': 1, 'status': 'submitted'});
    await db
        .collection('theses/mine/documents')
        .doc('chapterII')
        .set({'currentVersion': 1, 'status': 'submitted'});
    await db
        .collection('theses/mine/documents')
        .doc('chapterIII')
        .set({'currentVersion': 1, 'status': 'approved'});

    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.text('2 chapters awaiting review'), findsOneWidget);
  });

  testWidgets(
      'the awaiting-review count is NOT shown as "0" while its stream is '
      'still loading', (tester) async {
    // Deliberately bare pump()s, never pumpAndSettle: this must observe
    // the chapter stream's loading branch, not its settled state. "0
    // awaiting" and "still loading" are indistinguishable to a reader, and
    // collapsing the two is the single most repeated bug in this codebase.
    // Two pumps, same reasoning as the analogous case in
    // defence_readiness_list_test.dart: the first resolves the outer
    // myAdviseesProvider stream (mounting the advisee's own card), the
    // second lets that card's chaptersProvider start -- but its stream has
    // not emitted yet, so the card's own loading branch is what should show.
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Awaiting review: still loading…'), findsOneWidget);
    expect(find.textContaining('0 chapters awaiting review'), findsNothing);
    expect(find.text('Nothing awaiting review'), findsNothing);
  });
}
