import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';

Future<ProviderContainer> containerFor(String uid) async {
  final mockUser = MockUser(uid: uid, isEmailVerified: true, email: 'test@example.com');
  final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
  final firestore = FakeFirebaseFirestore();
  final container = ProviderContainer(overrides: [
    firebaseAuthProvider.overrideWithValue(auth),
    firestoreProvider.overrideWithValue(firestore),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('nominationLifecycleDetectorProvider', () {
    test('a pending Conforme writes a conformeRequested item', () async {
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'nominationPendingConforme',
        'panelistUids': ['faculty1'],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('nominations')
          .doc('faculty1')
          .set({
        'nomineeUid': 'faculty1',
        'nomineeName': 'Dr. Reyes',
        'position': 'panelist',
        'exOfficio': false,
        'conformeStatus': 'pending',
      });

      container.read(nominationLifecycleDetectorProvider);
      await container.read(notificationsProvider.future);
      // Let the detector's own listen callback (which awaits a Firestore
      // write) finish before asserting.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items, isNotEmpty);
      expect(items.first.type.name, 'conformeRequested');
      expect(items.first.thesisId, 't1');
    });

    test('a thesis the reader leads with a recommendation writes nominationRecommended', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'nominationPendingDean',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'coordinatorRecommendedAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
        'coordinatorRecommendedBy': 'coord1',
      });

      container.read(nominationLifecycleDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'nominationRecommended'), isTrue);
    });
  });
}
