import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/nomination/change_request_inbox.dart';
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

Widget _wrap(FakeFirebaseFirestore db, {required String uid}) => ProviderScope(
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
    home: Scaffold(body: SingleChildScrollView(child: ChangeRequestInbox())),
  ),
);

void main() {
  group('adviser-type (pendingAdvisers) requests', () {
    testWidgets('a new adviser sees and accepts the request', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedThesis(db, 't1', adviserUid: 'former1');
      await db.doc('theses/t1/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingAdvisers',
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
        'awaitingUids': ['new1', 'former1'],
      });

      await tester.pumpWidget(_wrap(db, uid: 'new1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestInbox')), findsOneWidget);
      expect(
        find.byKey(const Key('acceptChangeRequest-t1-newAdviser')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('acceptChangeRequest-t1-newAdviser')),
      );
      await tester.pumpAndSettle();

      final saved = await db.doc('theses/t1/changeRequests/adviser').get();
      expect(saved.data()!['signoffs']['newAdviser']['status'], 'accepted');
      // Only one of the two advisers has accepted so far -- the stage
      // stays at pendingAdvisers until both have.
      expect(saved.data()!['stage'], 'pendingAdvisers');
      // The accepting adviser drops out of awaitingUids; the former
      // adviser is still awaited (Fix 1).
      expect(saved.data()!['awaitingUids'], ['former1']);
    });

    testWidgets('a decline requires a reason and returns the request', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      await seedThesis(db, 't1', adviserUid: 'former1');
      await db.doc('theses/t1/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingAdvisers',
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
        'awaitingUids': ['new1', 'former1'],
      });

      await tester.pumpWidget(_wrap(db, uid: 'new1'));
      await tester.pumpAndSettle();

      // Declining without opening the reason field first: the declining
      // panel is not shown yet, so tap "Decline" to reveal it.
      await tester.tap(
        find.byKey(const Key('startDeclineChangeRequest-t1-newAdviser')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('declineChangeRequest-t1-newAdviser')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('reason for declining'), findsOneWidget);
      var saved = await db.doc('theses/t1/changeRequests/adviser').get();
      expect(saved.data()!['stage'], 'pendingAdvisers');

      await tester.enterText(
        find.byKey(const Key('changeRequestDeclineReason')),
        'Not a good fit',
      );
      await tester.tap(
        find.byKey(const Key('declineChangeRequest-t1-newAdviser')),
      );
      await tester.pumpAndSettle();

      saved = await db.doc('theses/t1/changeRequests/adviser').get();
      expect(saved.data()!['stage'], 'returned');
      expect(saved.data()!['signoffs']['newAdviser']['status'], 'declined');
      expect(
        saved.data()!['signoffs']['newAdviser']['reason'],
        'Not a good fit',
      );
      expect(saved.data()!['awaitingUids'], isEmpty);
    });
  });

  group('title-type (pendingAdviser) requests', () {
    testWidgets('shown only to the faculty currently awaited', (
      tester,
    ) async {
      final db = FakeFirebaseFirestore();
      // t1 awaits 'me'; t2 awaits someone else. mySignoffRequestsProvider
      // now filters server-side by awaitingUids (Fix 1), so t2's row never
      // comes back for 'me' -- no client-side cross-filter needed.
      await seedThesis(db, 't1', adviserUid: 'me', title: 'My Advisee');
      await seedThesis(
        db,
        't2',
        adviserUid: 'someone-else',
        title: 'Not My Advisee',
      );
      await db.doc('theses/t1/changeRequests/title').set({
        'type': 'title',
        'stage': 'pendingAdviser',
        'reasons': 'Scope changed',
        'leaderUid': 'l1',
        'newTitle': 'A New Working Title',
        'signoffs': signoffMap(['adviser', 'coordinator', 'dean']),
        'awaitingUids': ['me'],
      });
      await db.doc('theses/t2/changeRequests/title').set({
        'type': 'title',
        'stage': 'pendingAdviser',
        'reasons': 'Scope changed',
        'leaderUid': 'l2',
        'newTitle': 'Another New Title',
        'signoffs': signoffMap(['adviser', 'coordinator', 'dean']),
        'awaitingUids': ['someone-else'],
      });

      await tester.pumpWidget(_wrap(db, uid: 'me'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('acceptChangeRequest-t1-adviser')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('acceptChangeRequest-t2-adviser')),
        findsNothing,
      );
    });

    testWidgets('the advising faculty can accept it', (tester) async {
      final db = FakeFirebaseFirestore();
      await seedThesis(db, 't1', adviserUid: 'me', title: 'My Advisee');
      await db.doc('theses/t1/changeRequests/title').set({
        'type': 'title',
        'stage': 'pendingAdviser',
        'reasons': 'Scope changed',
        'leaderUid': 'l1',
        'newTitle': 'A New Working Title',
        'signoffs': signoffMap(['adviser', 'coordinator', 'dean']),
        'awaitingUids': ['me'],
      });

      await tester.pumpWidget(_wrap(db, uid: 'me'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('acceptChangeRequest-t1-adviser')));
      await tester.pumpAndSettle();

      final saved = await db.doc('theses/t1/changeRequests/title').get();
      expect(saved.data()!['signoffs']['adviser']['status'], 'accepted');
      expect(saved.data()!['stage'], 'pendingCoordinator');
      expect(saved.data()!['awaitingUids'], isEmpty);
    });
  });

  testWidgets('no requests renders the empty state under the inbox key', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(db, uid: 'nobody'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('changeRequestInbox')), findsOneWidget);
    expect(find.text('No change requests waiting'), findsOneWidget);
  });
}
