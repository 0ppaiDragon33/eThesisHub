import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/defence/title_defence_stage.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Map<String, dynamic> thesis({
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titlePendingDefence',
  String? approvedTitleId,
}) => {
  'leaderUid': leaderUid,
  'adviserUid': adviserUid,
  'panelistUids': <String>[],
  'memberNames': <String>[],
  'workingTitle': 'A Working Title',
  'college': 'CICT',
  'program': 'BSIT',
  'semester': 'First',
  'academicYear': '2026-2027',
  'status': status,
  if (approvedTitleId != null) 'approvedTitleId': approvedTitleId,
};

Future<Widget> wrap(FakeFirebaseFirestore db, String uid, String role) async {
  await db.collection('users').doc(uid).set({
    'fullName': 'Test $uid',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: '$uid@isufst.edu.ph',
            isEmailVerified: true,
          ),
        ),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: TitleDefenceStage())),
    ),
  );
}

void main() {
  testWidgets('an adviser opens their advisee\'s title defence', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
    await tester.pumpWidget(await wrap(db, 'f1', 'faculty'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToDefence-t1')), findsOneWidget);
    expect(find.text('Open title defence'), findsOneWidget);
  });

  testWidgets('a panelist opens a title defence they sit on', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t2').set(thesis(adviserUid: 'a9'));
    await db.doc('theses/t2/nominations/f1').set({
      'nomineeUid': 'f1',
      'conformeStatus': 'accepted',
    });
    await tester.pumpWidget(await wrap(db, 'f1', 'faculty'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToDefence-t2')), findsOneWidget);
  });

  testWidgets('the Dean sees every title defence', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis());
    await db.collection('theses').doc('t2').set(thesis());
    await tester.pumpWidget(await wrap(db, 'd1', 'dean'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('goToDefence-t1')), findsOneWidget);
    expect(find.byKey(const Key('goToDefence-t2')), findsOneWidget);
  });

  testWidgets('a student reads where their titles stand, and cannot open '
      'the room', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 's1'));
    await tester.pumpWidget(await wrap(db, 's1', 'student'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your candidate titles are with the panel.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('goToDefence-t1')), findsNothing);

    await db.collection('theses').doc('t1').update({'status': 'titleRejected'});
    await tester.pumpAndSettle();
    expect(
      find.text('The panel returned your titles. Submit a new set.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('resubmitTitles')), findsOneWidget);
  });

  testWidgets('a student sees the title the panel approved', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(
          thesis(
            leaderUid: 's1',
            status: 'titleApproved',
            approvedTitleId: 'c1',
          ),
        );
    await db.doc('theses/t1/candidateTitles/c1').set({
      'titleText': 'Mangrove Carbon Stocks',
      'position': 0,
      'round': 1,
      'submittedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    });
    await tester.pumpWidget(await wrap(db, 's1', 'student'));
    await tester.pumpAndSettle();
    expect(find.text('Title approved: Mangrove Carbon Stocks'), findsOneWidget);
  });

  testWidgets('after an approved change of title, the student sees the new '
      'title, not the originally approved candidate', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      ...thesis(leaderUid: 's1', status: 'titleApproved', approvedTitleId: 'c1'),
      'approvedTitleText': 'Seagrass Carbon Stocks',
    });
    await db.doc('theses/t1/candidateTitles/c1').set({
      'titleText': 'Mangrove Carbon Stocks',
      'position': 0,
      'round': 1,
      'submittedAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    });
    await tester.pumpWidget(await wrap(db, 's1', 'student'));
    await tester.pumpAndSettle();
    expect(find.text('Title approved: Seagrass Carbon Stocks'), findsOneWidget);
    expect(find.text('Title approved: Mangrove Carbon Stocks'), findsNothing);
  });
}
