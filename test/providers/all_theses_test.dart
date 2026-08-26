import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Map<String, dynamic> thesisDoc(String title, String status) => {
      'leaderUid': 'l1',
      'adviserUid': 'a1',
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': title,
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

void main() {
  test('returns every thesis regardless of status', () async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesisDoc('Alpha', 'draft'));
    await db
        .collection('theses')
        .doc('t2')
        .set(thesisDoc('Beta', 'titleApproved'));
    await db
        .collection('theses')
        .doc('t3')
        .set(thesisDoc('Gamma', 'nominationPendingDean'));

    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'coord',
          email: 'coord@isufst.edu.ph',
          isEmailVerified: true,
        ),
      )),
    ]);
    addTearDown(container.dispose);

    final all = await container.read(allThesesProvider.future);
    expect(all, hasLength(3));
    expect(
      all.map((t) => t.workingTitle).toSet(),
      {'Alpha', 'Beta', 'Gamma'},
    );
  });
}
