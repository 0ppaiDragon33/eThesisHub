import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/features/documents/chapters_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Leader l1 of thesis t1 (title approved), with a pre-oral whose panel
/// verdict is [verdict] (none at all when null).
Future<FakeFirebaseFirestore> seed({String? verdict}) async {
  final db = FakeFirebaseFirestore();
  await db.doc('users/l1').set({
    'fullName': 'Leader One',
    'email': 'l1@isufst.edu.ph',
    'role': 'student',
    'active': true,
  });
  await db.doc('theses/t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  await db.doc('defenses/po').set({
    'thesisId': 't1', 'type': 'preOral',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 1, 9)),
    'venue': 'AVR', 'panelUids': <String>['p1'], 'adviserUid': 'a1',
    'leaderUid': 'l1', 'status': 'completed', 'createdBy': 'c1',
    'panelVerdict': ?verdict,
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db, Widget screen) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'l1', email: 'l1@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: MaterialApp(home: Scaffold(body: screen)),
    );

FilledButton uploadButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('uploadVersion')));

void main() {
  // The full manuscript, Chapters I-V, is the gated one: it waits for a
  // passed pre-oral.
  for (final verdict in [null, 'fail']) {
    testWidgets(
        'the Chapters I–V manuscript cannot be uploaded while the pre-oral '
        'has ${verdict == null ? 'no verdict' : 'failed'}', (tester) async {
      await tester.pumpWidget(wrap(await seed(verdict: verdict),
          const ChapterDetailScreen(
              thesisId: 't1', chapter: ChapterId.manuscriptFinal)));
      await tester.pumpAndSettle();

      expect(uploadButton(tester).onPressed, isNull);
      expect(
          find.text('The Chapters I–V manuscript opens once the panel has '
              'passed your pre-oral defense.'),
          findsOneWidget);
    });
  }

  testWidgets('the Chapters I–V manuscript can be uploaded once the pre-oral '
      'passed', (tester) async {
    await tester.pumpWidget(wrap(await seed(verdict: 'pass'),
        const ChapterDetailScreen(
            thesisId: 't1', chapter: ChapterId.manuscriptFinal)));
    await tester.pumpAndSettle();

    expect(uploadButton(tester).onPressed, isNotNull);
  });

  testWidgets('the Chapters I–III manuscript is never held back by the '
      'pre-oral', (tester) async {
    await tester.pumpWidget(wrap(await seed(),
        const ChapterDetailScreen(
            thesisId: 't1', chapter: ChapterId.manuscriptProposal)));
    await tester.pumpAndSettle();

    expect(uploadButton(tester).onPressed, isNotNull);
  });

  // Chapters IV and V, from before manuscripts, stay gated the same way.
  testWidgets('an old Chapter IV record is still held back by the pre-oral',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(),
        const ChapterDetailScreen(
            thesisId: 't1', chapter: ChapterId.chapterIV)));
    await tester.pumpAndSettle();

    expect(uploadButton(tester).onPressed, isNull);
  });

  testWidgets('the screen offers the Chapters I–III manuscript until the '
      'pass, then the Chapters I–V one', (tester) async {
    await tester
        .pumpWidget(wrap(await seed(), const ChaptersScreen(thesisId: 't1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chapterRow-manuscriptProposal')),
        findsOneWidget);
    expect(find.byKey(const Key('chapterRow-manuscriptFinal')), findsNothing);

    await tester.pumpWidget(wrap(
        await seed(verdict: 'pass'), const ChaptersScreen(thesisId: 't1')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('chapterRow-manuscriptFinal')), findsOneWidget);
    // The five chapters are never listed as rows of their own.
    for (final id in ['chapterI', 'chapterII', 'chapterIII', 'chapterIV',
                      'chapterV']) {
      expect(find.byKey(Key('chapterRow-$id')), findsNothing, reason: id);
    }
  });
}
