import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_notification.dart';
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

      container.listen(nominationLifecycleDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
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

      container.listen(nominationLifecycleDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'nominationRecommended'), isTrue);
    });

    test('the recommendation and approval reach ONLY the group leader, not a '
        'faculty member with access to the thesis', () async {
      // The coordinator's recommendation and the dean's approval are the
      // student's news. A panelist (or adviser, coordinator, dean) who can
      // read the thesis is not the leader, so `myThesisProvider` yields them
      // nothing and neither notification is ever written to their feed.
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('faculty1').set({'role': 'faculty'});
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'nominationApproved',
        'panelistUids': ['faculty1'],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'coordinatorRecommendedAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
        'coordinatorRecommendedBy': 'coord1',
        'deanApprovedAt': Timestamp.fromDate(DateTime(2026, 2, 10)),
        'deanApprovedBy': 'dean1',
      });

      container.listen(nominationLifecycleDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container
          .read(notificationRepositoryProvider)
          .watchItems('faculty1')
          .first;
      expect(items.where((i) => i.type.name == 'nominationRecommended'), isEmpty);
      expect(items.where((i) => i.type.name == 'nominationApproved'), isEmpty);
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

      container.listen(chapterFeedbackDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
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

      container.listen(chapterFeedbackDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
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

      container.listen(chapterFeedbackDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
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
    // The panel's remarks are highlights now, and the group reads them once
    // the adviser releases. That release is what the group is told about.
    Future<ProviderContainer> releasedSetup(String reader,
        {bool released = true, List<String> panel = const []}) async {
      final container = await containerFor(reader);
      final firestore = container.read(firestoreProvider);
      await firestore
          .collection('users')
          .doc(reader)
          .set({'role': reader.startsWith('faculty') ? 'faculty' : 'student'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'preOral',
        'venue': 'Room 1',
        'panelUids': panel,
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'completed',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
        if (released)
          'consolidatedAt': Timestamp.fromDate(DateTime(2026, 5, 2)),
      });
      container.listen(defenceDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      return container;
    }

    test('releasing the highlights tells the group leader, linked to the '
        'defence', () async {
      final container = await releasedSetup('student1');
      final items = await container
          .read(notificationRepositoryProvider)
          .watchItems('student1')
          .first;
      final released =
          items.where((i) => i.type == NotificationType.highlightsReleased);
      expect(released, hasLength(1));
      expect(released.single.defenceId, 'd1');
      expect(released.single.message, contains('highlights'));
    });

    test('nothing is said before release, and the release arrives live',
        () async {
      final container = await releasedSetup('student1', released: false);
      var items = await container
          .read(notificationRepositoryProvider)
          .watchItems('student1')
          .first;
      expect(items.where((i) => i.type == NotificationType.highlightsReleased),
          isEmpty);

      await container.read(firestoreProvider).doc('defenses/d1').update(
          {'consolidatedAt': Timestamp.fromDate(DateTime(2026, 5, 2))});
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      items = await container
          .read(notificationRepositoryProvider)
          .watchItems('student1')
          .first;
      expect(items.where((i) => i.type == NotificationType.highlightsReleased),
          hasLength(1));
    });

    test('the release does NOT notify a faculty panelist -- only the group '
        'leader', () async {
      final container =
          await releasedSetup('faculty1', panel: const ['faculty1']);
      final items = await container
          .read(notificationRepositoryProvider)
          .watchItems('faculty1')
          .first;
      expect(items.where((i) => i.type == NotificationType.highlightsReleased),
          isEmpty);
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

      container.listen(defenceDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container
          .read(notificationRepositoryProvider)
          .watchItems('student1')
          .first;
      expect(items.any((i) => i.type.name == 'defenceScheduled'), isTrue);
      expect(
          items.firstWhere((i) => i.type.name == 'defenceScheduled').defenceId,
          'd1');
    });

    test('the scheduled message is worded for a panelist, not as a student',
        () async {
      // A panelist and the student group both get defenceScheduled, but the
      // sentence must not tell a faculty member "Your defence".
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('faculty1').set({'role': 'faculty'});
      await firestore.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 7',
        'panelUids': ['faculty1'],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'scheduled',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 9)),
      });

      container.listen(defenceDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container
          .read(notificationRepositoryProvider)
          .watchItems('faculty1')
          .first;
      final scheduled =
          items.firstWhere((i) => i.type.name == 'defenceScheduled');
      expect(scheduled.message, contains('on the panel for'));
      expect(scheduled.message, isNot(contains('Your defence')));
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

      container.listen(evaluationAwaitsDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items.any((i) => i.type.name == 'evaluationAwaits'), isTrue);
      expect(
          items.firstWhere((i) => i.type.name == 'evaluationAwaits').defenceId,
          'd1');
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

      container.listen(evaluationAwaitsDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
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

      container.listen(archivePublishedDetectorProvider, (_, _) {}); // kept alive, as AppShellHost does
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'archivePublished'), isTrue);
    });
  });
}
