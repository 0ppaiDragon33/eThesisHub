import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/features/defence/redefence_notice.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Defence failed({PassFail? verdict = PassFail.fail, String? redefenceOf}) =>
    Defence(
      id: 'f1', thesisId: 't1', type: DefenceType.preOral, venue: 'AVR',
      panelUids: const ['p1'], adviserUid: 'a1', leaderUid: 'l1',
      status: DefenceStatus.completed, createdBy: 'c1',
      panelVerdict: verdict, redefenceOf: redefenceOf,
    );

Future<void> pump(WidgetTester tester, Defence d,
    {String uid = 'c1', String role = 'coordinator',
    bool alreadyRedefended = false}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'U', 'email': '$uid@isufst.edu.ph', 'role': role,
    'active': true,
  });
  if (alreadyRedefended) {
    await db.doc('defenses/f1_redefence').set({
      'thesisId': 't1', 'type': 'preOral',
      'scheduledAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      'venue': 'AVR', 'panelUids': ['p1'], 'adviserUid': 'a1',
      'leaderUid': 'l1', 'status': 'scheduled', 'createdBy': 'c1',
      'redefenceOf': 'f1',
    });
  }
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: MaterialApp(home: Scaffold(body: RedefenceNotice(defence: d))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Coordinator is offered the re-defence of a Fail',
      (tester) async {
    await pump(tester, failed());
    expect(find.byKey(const Key('scheduleRedefence')), findsOneWidget);
  });

  testWidgets('the adviser is told a re-defence is to be scheduled',
      (tester) async {
    await pump(tester, failed(), uid: 'a1', role: 'faculty');
    expect(find.byKey(const Key('scheduleRedefence')), findsNothing);
    expect(find.byKey(const Key('redefencePending')), findsOneWidget);
  });

  testWidgets('nothing once the re-defence exists', (tester) async {
    await pump(tester, failed(), alreadyRedefended: true);
    expect(find.byKey(const Key('scheduleRedefence')), findsNothing);
    expect(find.byKey(const Key('redefencePending')), findsNothing);
  });

  testWidgets('nothing for a pass, no verdict, or a failed re-defence',
      (tester) async {
    for (final d in [
      failed(verdict: PassFail.pass),
      failed(verdict: null),
      failed(redefenceOf: 'f0'),
    ]) {
      await pump(tester, d);
      expect(find.byKey(const Key('scheduleRedefence')), findsNothing);
      expect(find.byKey(const Key('redefencePending')), findsNothing);
    }
  });
}
