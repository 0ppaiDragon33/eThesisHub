import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/change_request_providers.dart';

Thesis thesis({ThesisStatus status = ThesisStatus.titleApproved}) => Thesis(
  id: 't1',
  leaderUid: 'l1',
  memberNames: const [],
  workingTitle: 'A Working Title',
  college: 'CICT',
  program: 'BSIT',
  semester: 'First',
  academicYear: '2026-2027',
  status: status,
  panelistUids: const [],
  createdAt: DateTime.now(),
  adviserUid: 'a1',
);

Defence defence({
  DefenceStatus status = DefenceStatus.scheduled,
  DefenceType type = DefenceType.preOral,
  PassFail? verdict,
}) => Defence(
  id: 'd1',
  thesisId: 't1',
  type: type,
  venue: 'CICT AVR',
  panelUids: const ['p1', 'p2', 'p3'],
  adviserUid: 'a1',
  leaderUid: 'l1',
  status: status,
  createdBy: 'c1',
  panelVerdict: verdict,
);

Map<String, dynamic> signoffMap(List<String> roles) => {
  for (final r in roles)
    r: {'status': 'pending', 'respondedAt': null, 'reason': null},
};

Future<ProviderContainer> containerFor(
  FakeFirebaseFirestore db,
  String uid,
) async {
  final c = ProviderContainer(
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
  );
  addTearDown(c.dispose);
  return c;
}

/// The provider is synchronous over streams, so let it emit until it
/// settles on a value.
Future<List<({String thesisId, ChangeRequest request, String role})>> settle(
  ProviderContainer c,
) async {
  final sub = c.listen(mySignoffRequestsProvider, (_, _) {});
  addTearDown(sub.close);
  // MockFirebaseAuth resolves its auth state asynchronously, so the first
  // build can see a still-null signedInUidProvider and settle on an empty
  // list before the real uid arrives. pumpEventQueue (rather than a single
  // Duration.zero delay) flushes that chain before each check.
  for (var i = 0; i < 100; i++) {
    await pumpEventQueue();
    final v = c.read(mySignoffRequestsProvider);
    if (v.hasValue) return v.value!;
    if (v.hasError) throw v.error!;
  }
  fail('mySignoffRequestsProvider never settled');
}

void main() {
  group('canRequestAdviserChange', () {
    test('titleApproved with no defence is allowed', () {
      expect(canRequestAdviserChange(thesis(), const []), isTrue);
    });

    test('titleApproved with one scheduled pre-oral is refused', () {
      expect(canRequestAdviserChange(thesis(), [defence()]), isFalse);
    });

    test('titleApproved with only a cancelled defence is allowed', () {
      expect(
        canRequestAdviserChange(thesis(), [
          defence(status: DefenceStatus.cancelled),
        ]),
        isTrue,
      );
    });

    test('any other status is refused', () {
      expect(
        canRequestAdviserChange(
          thesis(status: ThesisStatus.titlePendingDefence),
          const [],
        ),
        isFalse,
      );
    });
  });

  group('canRequestTitleChange', () {
    test('titleApproved with no passed final is allowed', () {
      expect(canRequestTitleChange(thesis(), const []), isTrue);
    });

    test('titleApproved with a passed final defence is refused', () {
      expect(
        canRequestTitleChange(thesis(), [
          defence(type: DefenceType.final_, verdict: PassFail.pass),
        ]),
        isFalse,
      );
    });

    test(
      'titleApproved with a final defence and no verdict yet is allowed',
      () {
        expect(
          canRequestTitleChange(thesis(), [defence(type: DefenceType.final_)]),
          isTrue,
        );
      },
    );

    test('archived is refused', () {
      expect(
        canRequestTitleChange(thesis(status: ThesisStatus.archived), const []),
        isFalse,
      );
    });
  });

  group('mySignoffRequestsProvider', () {
    test('returns a request awaiting the signed-in new adviser, not one '
        'awaiting someone else -- filtered server-side by awaitingUids '
        '(Fix 1: an unfiltered collection-group scan is denied in '
        'production, so the query must do the filtering, not the client)',
        () async {
      final db = FakeFirebaseFirestore();
      await db.doc('theses/t1/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingAdvisers',
        'reasons': 'Because',
        'leaderUid': 'l1',
        'newAdviserUid': 'me',
        'newAdviserName': 'Dr. Me',
        'formerAdviserUid': 'other1',
        'formerAdviserName': 'Dr. Other1',
        'signoffs': signoffMap([
          'newAdviser',
          'formerAdviser',
          'coordinator',
          'dean',
        ]),
        'awaitingUids': ['me', 'other1'],
      });
      await db.doc('theses/t2/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingAdvisers',
        'reasons': 'Because',
        'leaderUid': 'l2',
        // 'me' is the new adviser here too, but has already answered and
        // dropped out of awaitingUids -- the field, not the uid match on
        // newAdviserUid, is what must gate this row out.
        'newAdviserUid': 'me',
        'newAdviserName': 'Dr. Me',
        'formerAdviserUid': 'other2',
        'formerAdviserName': 'Dr. Other2',
        'signoffs': signoffMap([
          'newAdviser',
          'formerAdviser',
          'coordinator',
          'dean',
        ]),
        'awaitingUids': ['other2'],
      });
      await db.doc('theses/t3/changeRequests/adviser').set({
        'type': 'adviser',
        'stage': 'pendingAdvisers',
        'reasons': 'Because',
        'leaderUid': 'l3',
        'newAdviserUid': 'someone-else',
        'newAdviserName': 'Dr. Else',
        'formerAdviserUid': 'other3',
        'formerAdviserName': 'Dr. Other3',
        'signoffs': signoffMap([
          'newAdviser',
          'formerAdviser',
          'coordinator',
          'dean',
        ]),
        'awaitingUids': ['someone-else', 'other3'],
      });

      final c = await containerFor(db, 'me');
      final result = await settle(c);

      expect(result.map((r) => r.thesisId), ['t1']);
      expect(result.single.role, 'newAdviser');
    });
  });
}
