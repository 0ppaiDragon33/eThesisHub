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
  for (final verdict in [null, 'fail']) {
    testWidgets(
        'Chapter IV cannot be uploaded while the pre-oral has '
        '${verdict == null ? 'no verdict' : 'failed'}', (tester) async {
      await tester.pumpWidget(wrap(await seed(verdict: verdict),
          const ChapterDetailScreen(
              thesisId: 't1', chapter: ChapterId.chapterIV)));
      await tester.pumpAndSettle();

      expect(uploadButton(tester).onPressed, isNull);
      expect(
          find.text('Chapters IV and V open once the panel has passed your '
              'pre-oral defence.'),
          findsOneWidget);
    });
  }

  testWidgets('Chapter IV can be uploaded once the pre-oral passed',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(verdict: 'pass'),
        const ChapterDetailScreen(
            thesisId: 't1', chapter: ChapterId.chapterIV)));
    await tester.pumpAndSettle();

    expect(uploadButton(tester).onPressed, isNotNull);
  });

  testWidgets('Chapter III is never held back by the pre-oral',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(),
        const ChapterDetailScreen(
            thesisId: 't1', chapter: ChapterId.chapterIII)));
    await tester.pumpAndSettle();

    expect(uploadButton(tester).onPressed, isNotNull);
  });

  testWidgets('the chapters list marks IV and V locked until the pass',
      (tester) async {
    await tester
        .pumpWidget(wrap(await seed(), const ChaptersScreen(thesisId: 't1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chapterLocked-chapterIV')), findsOneWidget);
    expect(find.byKey(const Key('chapterLocked-chapterV')), findsOneWidget);
    expect(find.byKey(const Key('chapterLocked-chapterIII')), findsNothing);

    await tester.pumpWidget(wrap(
        await seed(verdict: 'pass'), const ChaptersScreen(thesisId: 't1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chapterLocked-chapterIV')), findsNothing);
  });
}
