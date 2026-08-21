import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Seeds a thesis at titleApproved, with its `documents` subcollection
/// holding chapter records. The `thesisId` param lets a second thesis be
/// seeded without duplicating this whole shape.
Future<void> _seedThesis(
  FakeFirebaseFirestore db,
  String id, {
  required String workingTitle,
  required Map<String, String> chapters,
}) async {
  await db.collection('theses').doc(id).set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': workingTitle, 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  for (final entry in chapters.entries) {
    await db
        .collection('theses')
        .doc(id)
        .collection('documents')
        .doc(entry.key)
        .set({'currentVersion': 1, 'status': entry.value});
  }
}

/// Without this, `FirebaseAuth.instance` throws `[core/no-app]` because no
/// app is initialised in a widget test, and `signedInUidProvider` (which
/// both `thesesByStatusProvider` and `chaptersProvider` rebuild on) settles
/// into null forever. See adviser_review_test.dart's `_wrap` for the same
/// pattern.
Widget _wrap(FakeFirebaseFirestore db) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'dean1', email: 'dean1@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: DefenceReadinessList())),
    ),
  );
}

void main() {
  testWidgets('a thesis with I-III approved shows pre-oral readiness',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await _seedThesis(db, 't1', workingTitle: 'Proposal Ready Thesis', chapters: {
      'chapterI': 'approved',
      'chapterII': 'approved',
      'chapterIII': 'approved',
    });
    await tester.pumpWidget(_wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('Proposal Ready Thesis'), findsOneWidget);
    expect(find.text('3 of 5 chapters approved'), findsOneWidget);
    expect(find.text('Ready for pre-oral'), findsOneWidget);
  });

  testWidgets('a thesis with nothing approved shows not ready, not vacuously '
      'ready', (tester) async {
    // Two of three approved is the exact case the brief warns a `some`
    // check would wrongly pass -- see the falsification in
    // defence_readiness_test.dart. Exercised here through the widget too.
    final db = FakeFirebaseFirestore();
    await _seedThesis(db, 't2', workingTitle: 'Not Ready Thesis', chapters: {
      'chapterI': 'approved',
      'chapterII': 'approved',
      'chapterIII': 'revise',
    });
    await tester.pumpWidget(_wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('Not Ready Thesis'), findsOneWidget);
    expect(find.text('2 of 5 chapters approved'), findsOneWidget);
    expect(find.text('Not ready'), findsOneWidget);
  });

  testWidgets('no theses at titleApproved shows an empty state, not an error',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('No theses with an approved title yet'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets(
      'a thesis whose chapters have not arrived yet says so, distinct from '
      'zero approved', (tester) async {
    final db = FakeFirebaseFirestore();
    // Seed the thesis but never write to its `documents` subcollection.
    // FakeFirebaseFirestore still emits an initial empty snapshot
    // synchronously, so without pumpAndSettle this asserts the row's own
    // loading branch, not a settled "0 of 5" -- the two would otherwise be
    // indistinguishable, exactly the bug this task's brief calls out.
    await db.collection('theses').doc('t3').set({
      'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'memberNames': <String>[],
      'workingTitle': 'Still Loading Thesis', 'college': 'CICT',
      'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    });
    await tester.pumpWidget(_wrap(db));
    // Two pumps, deliberately short of pumpAndSettle: the first resolves
    // the outer thesesByStatusProvider stream (mounting the per-thesis
    // row), the second lets that row's own chaptersProvider start -- but
    // its stream has not emitted yet, so the row's loading branch is what
    // should be showing.
    await tester.pump();
    await tester.pump();

    expect(find.text('Chapters still loading…'), findsOneWidget);
    expect(find.text('0 of 5 chapters approved'), findsNothing);
  });
}
