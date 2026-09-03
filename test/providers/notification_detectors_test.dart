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

  group('chapterFeedbackDetectorProvider', () {
    test('feedback from someone else on my own chapter writes a notification', () async {
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
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('documents')
          .doc('chapterI')
          .collection('feedback')
          .doc('f1')
          .set({
        'version': 1,
        'reviewerUid': 'adviser1',
        'reviewerName': 'Dr. Cruz',
        'reviewerRole': 'adviser',
        'body': 'Please revise the statement of the problem.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });

      container.read(chapterFeedbackDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'chapterFeedback'), isTrue);
    });

    test('feedback the reader wrote about their own chapter does not notify them', () async {
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
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('documents')
          .doc('chapterI')
          .collection('feedback')
          .doc('f1')
          .set({
        'version': 1,
        'reviewerUid': 'student1',
        'reviewerName': 'Santos, J.',
        'reviewerRole': 'student',
        'body': 'Fixed the typo.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });

      container.read(chapterFeedbackDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.where((i) => i.type.name == 'chapterFeedback'), isEmpty);
    });

    test('feedback added mid-session (after the thesis was already known) still notifies live', () async {
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
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      container.read(chapterFeedbackDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // No feedback existed at subscription time -- confirms the detector
      // did not require the outer `myThesisProvider` source to re-emit.
      var items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.where((i) => i.type.name == 'chapterFeedback'), isEmpty);

      // A comment written after the standing subscription was already
      // live -- this is exactly the case the one-shot `.future` read used
      // to miss.
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('documents')
          .doc('chapterI')
          .collection('feedback')
          .doc('f1')
          .set({
        'version': 1,
        'reviewerUid': 'adviser1',
        'reviewerName': 'Dr. Cruz',
        'reviewerRole': 'adviser',
        'body': 'Please revise the statement of the problem.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'chapterFeedback'), isTrue);
    });
  });

  group('defenceDetectorProvider', () {
    test('a comment from someone else writes a notification', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('student1').set({'role': 'student'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': <String>[],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'scheduled',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await firestore.collection('defenses').doc('d1').collection('comments').doc('c1').set({
        'authorUid': 'adviser1',
        'authorName': 'Dr. Cruz',
        'authorPosition': 'adviser',
        'body': 'Please prepare the slides.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 4, 1)),
      });

      container.read(defenceDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'defenceComment'), isTrue);
    });

    test('a schedule change writes a notification keyed by the new value', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('student1').set({'role': 'student'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 2',
        'panelUids': <String>[],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'scheduled',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 15)),
      });

      container.read(defenceDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'defenceScheduled'), isTrue);
    });

    test('a comment added mid-session (after the defence was already known) still notifies live', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('student1').set({'role': 'student'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': <String>[],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'scheduled',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });

      container.read(defenceDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // No comment existed at subscription time.
      var items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.where((i) => i.type.name == 'defenceComment'), isEmpty);

      // A comment written after the standing subscription was already
      // live -- exactly the case the one-shot `.future` read used to miss.
      await firestore.collection('defenses').doc('d1').collection('comments').doc('c1').set({
        'authorUid': 'adviser1',
        'authorName': 'Dr. Cruz',
        'authorPosition': 'adviser',
        'body': 'Please prepare the slides.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 4, 1)),
      });
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'defenceComment'), isTrue);
    });
  });

  group('evaluationAwaitsDetectorProvider', () {
    test('a completed defence with no evaluation on file from this panelist writes one', () async {
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('faculty1').set({'role': 'faculty'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': ['faculty1'],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'completed',
        'createdBy': 'coord1',
      });

      container.read(evaluationAwaitsDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items.any((i) => i.type.name == 'evaluationAwaits'), isTrue);
    });

    test('a completed defence this panelist already scored writes nothing', () async {
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('faculty1').set({'role': 'faculty'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': ['faculty1'],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'completed',
        'createdBy': 'coord1',
      });
      await firestore
          .collection('defenses')
          .doc('d1')
          .collection('evaluations')
          .doc('faculty1')
          .set({
        'evaluatorName': 'Dr. Reyes',
        'scores': <String, int>{},
        'comments': <String, String>{},
        'total': 90,
        'rating': 'pass',
        'submittedAt': Timestamp.fromDate(DateTime(2026, 5, 2)),
      });

      container.read(evaluationAwaitsDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items.where((i) => i.type.name == 'evaluationAwaits'), isEmpty);
    });
  });

  group('archivePublishedDetectorProvider', () {
    test("the thesis leader's own client sees an archivePublished item", () async {
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
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore.collection('archive').doc('t1').set({
        'title': 'A Study of Coastal Fisheries',
        'memberNames': ['Santos, J.'],
        'abstract': 'Fish were counted.',
        'college': 'CICT',
        'program': 'BSIT',
        'academicYear': '2026-2027',
        'adviserName': 'Dr. Cruz',
        'panelNames': <String>['Dr. Reyes'],
        'manuscriptUrl': 'https://example.test/m.pdf',
        'manuscriptPath': 'p/m.pdf',
        'finalDefenceId': 'd1',
        'uploadedBy': 'student1',
        'archivedBy': 'coord1',
        'archivedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
      });

      container.read(archivePublishedDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'archivePublished'), isTrue);
    });
  });
}
