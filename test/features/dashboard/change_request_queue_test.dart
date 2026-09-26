import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/dashboard/change_request_queue.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Map<String, dynamic> signoffMap(List<String> roles) => {
  for (final r in roles)
    r: {'status': 'pending', 'respondedAt': null, 'reason': null},
};

Future<void> seedThesis(
  FakeFirebaseFirestore db,
  String id, {
  required String adviserUid,
  String title = 'A Study of Things',
}) => db.collection('theses').doc(id).set({
  'leaderUid': 'l1',
  'adviserUid': adviserUid,
  'status': 'titleApproved',
  'panelistUids': <String>[],
  'memberNames': <String>[],
  'workingTitle': title,
  'college': 'CICT',
  'program': 'BSIT',
  'semester': 'First',
  'academicYear': '2026-2027',
});

Widget _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  required bool asDean,
}) => ProviderScope(
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
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: ChangeRequestQueue(asDean: asDean)),
    ),
  ),
);

void main() {
  group('coordinator queue', () {
    testWidgets(
      'the coordinator recommends a pendingCoordinator request and it '
      'moves to pendingDean',
      (tester) async {
        final db = FakeFirebaseFirestore();
        await seedThesis(db, 't1', adviserUid: 'former1');
        await db.doc('theses/t1/changeRequests/adviser').set({
          'type': 'adviser',
          'stage': 'pendingCoordinator',
          'reasons': 'A good reason',
          'leaderUid': 'l1',
          'newAdviserUid': 'new1',
          'newAdviserName': 'Dr. New',
          'formerAdviserUid': 'former1',
          'formerAdviserName': 'Dr. Former',
          'signoffs': signoffMap([
            'newAdviser',
            'formerAdviser',
            'coordinator',
            'dean',
          ]),
        });

        await tester.pumpWidget(_wrap(db, uid: 'coord1', asDean: false));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('changeRequestQueue')), findsOneWidget);
        expect(
          find.byKey(const Key('recommendChangeRequest-t1-adviser')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('recommendChangeRequest-t1-adviser')),
        );
        await tester.pumpAndSettle();

        final saved = await db.doc('theses/t1/changeRequests/adviser').get();
        expect(saved.data()!['stage'], 'pendingDean');
        expect(saved.data()!['signoffs']['coordinator']['status'], 'accepted');
      },
    );

    testWidgets('a return requires a reason and sets stage returned', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seedThesis(db, 't1', adviserUid: 'former1');
      await db.doc('theses/t1/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingCoordinator',
        'reasons': 'A good reason',
        'leaderUid': 'l1',
        'newAdviserUid': 'new1',
        'newAdviserName': 'Dr. New',
        'formerAdviserUid': 'former1',
        'formerAdviserName': 'Dr. Former',
        'signoffs': signoffMap([
          'newAdviser',
          'formerAdviser',
          'coordinator',
          'dean',
        ]),
      });

      await tester.pumpWidget(_wrap(db, uid: 'coord1', asDean: false));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('startReturnChangeRequest-t1-adviser')),
      );
      await tester.pumpAndSettle();

      // Confirming with an empty reason must not touch the document.
      await tester.tap(find.byKey(const Key('returnChangeRequest-t1-adviser')));
      await tester.pumpAndSettle();

      var saved = await db.doc('theses/t1/changeRequests/adviser').get();
      expect(saved.data()!['stage'], 'pendingCoordinator');

      await tester.enterText(
        find.byKey(const Key('changeRequestReturnReason')),
        'Missing documentation',
      );
      await tester.tap(find.byKey(const Key('returnChangeRequest-t1-adviser')));
      await tester.pumpAndSettle();

      saved = await db.doc('theses/t1/changeRequests/adviser').get();
      expect(saved.data()!['stage'], 'returned');
      expect(saved.data()!['signoffs']['coordinator']['status'], 'declined');
      expect(
        saved.data()!['signoffs']['coordinator']['reason'],
        'Missing documentation',
      );
    });
  });

  group('dean queue', () {
    testWidgets('the dean approves a pendingDean adviser request: the thesis '
        'adviserUid changes and the request is approved', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedThesis(db, 't1', adviserUid: 'former1');
      await db.doc('theses/t1/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingDean',
        'reasons': 'A good reason',
        'leaderUid': 'l1',
        'newAdviserUid': 'new1',
        'newAdviserName': 'Dr. New',
        'formerAdviserUid': 'former1',
        'formerAdviserName': 'Dr. Former',
        'signoffs': signoffMap([
          'newAdviser',
          'formerAdviser',
          'coordinator',
          'dean',
        ]),
      });

      await tester.pumpWidget(_wrap(db, uid: 'dean1', asDean: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestQueue')), findsOneWidget);
      expect(
        find.byKey(const Key('approveChangeRequest-t1-adviser')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('approveChangeRequest-t1-adviser')),
      );
      await tester.pumpAndSettle();

      final savedRequest = await db
          .doc('theses/t1/changeRequests/adviser')
          .get();
      expect(savedRequest.data()!['stage'], 'approved');
      expect(savedRequest.data()!['signoffs']['dean']['status'], 'accepted');

      final savedThesis = await db.doc('theses/t1').get();
      expect(savedThesis.data()!['adviserUid'], 'new1');
    });

    testWidgets('a dean return sets stage returned with the reason', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seedThesis(db, 't1', adviserUid: 'former1');
      await db.doc('theses/t1/changeRequests/title').set({
        'type': 'title',
        'stage': 'pendingDean',
        'reasons': 'Scope changed',
        'leaderUid': 'l1',
        'newTitle': 'A New Working Title',
        'signoffs': signoffMap(['adviser', 'coordinator', 'dean']),
      });

      await tester.pumpWidget(_wrap(db, uid: 'dean1', asDean: true));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('startReturnChangeRequest-t1-title')),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('changeRequestReturnReason')),
        'Title too broad',
      );
      await tester.tap(find.byKey(const Key('returnChangeRequest-t1-title')));
      await tester.pumpAndSettle();

      final saved = await db.doc('theses/t1/changeRequests/title').get();
      expect(saved.data()!['stage'], 'returned');
      expect(saved.data()!['signoffs']['dean']['status'], 'declined');
      expect(saved.data()!['signoffs']['dean']['reason'], 'Title too broad');

      // The thesis is untouched by a return.
      final savedThesis = await db.doc('theses/t1').get();
      expect(savedThesis.data()!['workingTitle'], 'A Study of Things');
    });
  });

  testWidgets('no requests renders the empty state under the queue key', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(db, uid: 'coord1', asDean: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('changeRequestQueue')), findsOneWidget);
    expect(find.text('Nothing waiting'), findsOneWidget);
  });
}
