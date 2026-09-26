import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';

/// Lets every stream, listener and Firestore write in flight finish.
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> thesis({required String leaderUid}) => {
      'leaderUid': leaderUid,
      'adviserUid': 'adviser1',
      'memberNames': ['Santos, J.'],
      'workingTitle': 'A Study',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': '1',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
      'panelistUids': <String>[],
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    };

User user(String uid) =>
    MockUser(uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true);

void main() {
  // The reported sequence, in one app session: sign in as one account, sign
  // out, sign in as another. The detectors live for the whole session, so
  // anything they opened for the first account must not write into the
  // second account's feed.
  test('switching accounts never writes the previous account\'s '
      'notifications into the next account\'s feed', () async {
    final firestore = FakeFirebaseFirestore();
    for (final uid in ['studentA', 'freshB']) {
      await firestore.collection('users').doc(uid).set({
        'fullName': uid,
        'email': '$uid@isufst.edu.ph',
        'role': 'student',
        'active': true,
      });
    }
    // Account A leads tA, and its adviser left feedback on Chapter I.
    await firestore.collection('theses').doc('tA').set(
          thesis(leaderUid: 'studentA'),
        );
    await firestore.doc('theses/tA/documents/chapterI/feedback/f1').set({
      'version': 1,
      'reviewerUid': 'adviser1',
      'reviewerName': 'Dr. Reyes',
      'reviewerRole': 'Adviser',
      'body': 'Revise the scope.',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });

    final authEvents = StreamController<User?>.broadcast();
    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(firestore),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
      authStateProvider.overrideWith((ref) => authEvents.stream),
    ]);
    addTearDown(() {
      container.dispose();
      authEvents.close();
    });

    // Kept alive for the whole session, exactly as AppShellHost does.
    final keepAlive =
        container.listen(notificationDetectorsProvider, (_, _) {});
    addTearDown(keepAlive.close);
    final repo = container.read(notificationRepositoryProvider);

    authEvents.add(user('studentA'));
    await settle();
    expect(await repo.watchItems('studentA').first, isNotEmpty,
        reason: 'sanity: account A is notified of its own feedback');

    authEvents.add(null); // sign out
    await settle();
    authEvents.add(user('freshB')); // sign in as a fresh account
    await settle();

    final leaked = await repo.watchItems('freshB').first;
    expect(leaked, isEmpty,
        reason: 'account A\'s notifications were written into account B\'s '
            'feed: ${leaked.map((n) => n.message).toList()}');

    // The detectors rebuilt for B must still notify B of B's OWN events.
    await firestore.collection('theses').doc('tB').set(
          thesis(leaderUid: 'freshB'),
        );
    await firestore.doc('theses/tB/documents/chapterI/feedback/f2').set({
      'version': 1,
      'reviewerUid': 'adviser1',
      'reviewerName': 'Dr. Cruz',
      'reviewerRole': 'Adviser',
      'body': 'Tighten the objectives.',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 2)),
    });
    await settle();
    final own = await repo.watchItems('freshB').first;
    expect(own.map((n) => n.message),
        ['Dr. Cruz left feedback on Chapter I — Introduction.'],
        reason: 'B gets its own feedback, and still nothing of A\'s');
  });
}
