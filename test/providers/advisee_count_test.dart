import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// An adviser's count toward the limit: the theses they advise that are not
/// archived, plus adviser nominations they have not declined on theses that
/// have no adviser yet.
Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  await db.doc('users/f1').set({
    'fullName': 'Dr. Armada',
    'email': 'f1@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  return db;
}

Future<void> thesis(
  FakeFirebaseFirestore db,
  String id, {
  String? adviserUid,
  String status = 'titleApproved',
}) =>
    db.doc('theses/$id').set({
      'leaderUid': 'l-$id',
      'adviserUid': adviserUid,
      'status': status,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': id,
      'college': 'CICI',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
    });

Future<void> nominated(
  FakeFirebaseFirestore db,
  String thesisId, {
  String position = 'adviser',
  String status = 'pending',
}) =>
    db.doc('theses/$thesisId/nominations/f1').set({
      'nomineeUid': 'f1',
      'nomineeName': 'Dr. Armada',
      'position': position,
      'exOfficio': false,
      'conformeStatus': status,
      'respondedAt': null,
      'declineReason': null,
    });

Future<int> countFor(FakeFirebaseFirestore db) async {
  final container = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser:
          MockUser(uid: 'f1', email: 'f1@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
  addTearDown(container.dispose);
  container.listen(myAdviseeCountProvider, (_, _) {});
  // Let sign-in settle; the count is worked out again once it has.
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return container.read(myAdviseeCountProvider.future);
}

void main() {
  test('advised theses count, archived ones do not', () async {
    final db = await world();
    await thesis(db, 'a', adviserUid: 'f1');
    await thesis(db, 'b', adviserUid: 'f1', status: 'nominationApproved');
    await thesis(db, 'c', adviserUid: 'f1', status: 'archived');
    expect(await countFor(db), 2);
  });

  test('a pending or accepted adviser nomination on a thesis in nomination '
      'counts; a declined one does not', () async {
    final db = await world();
    await thesis(db, 'n1', status: 'nominationPendingConforme');
    await nominated(db, 'n1');
    await thesis(db, 'n2', status: 'nominationPendingDean');
    await nominated(db, 'n2', status: 'accepted');
    await thesis(db, 'n3', status: 'nominationPendingConforme');
    await nominated(db, 'n3', status: 'declined');
    expect(await countFor(db), 2);
  });

  test('a panel nomination does not count', () async {
    final db = await world();
    await thesis(db, 'p1', status: 'nominationPendingConforme');
    await nominated(db, 'p1', position: 'panelist');
    expect(await countFor(db), 0);
  });

  test('an approved thesis is counted once, not twice', () async {
    final db = await world();
    await thesis(db, 'a', adviserUid: 'f1');
    await nominated(db, 'a', status: 'accepted');
    expect(await countFor(db), 1);
  });

  test('a thesis whose adviser changed to someone else is not counted',
      () async {
    final db = await world();
    await thesis(db, 'moved', adviserUid: 'someone-else');
    await nominated(db, 'moved', status: 'accepted');
    expect(await countFor(db), 0);
  });

  test('the directory entry reads full at five', () {
    FacultyDirectoryEntry e(int n) => FacultyDirectoryEntry(
        uid: 'x', fullName: 'X', role: 'faculty', adviseeCount: n);
    expect(e(4).adviserFull, isFalse);
    expect(e(5).adviserFull, isTrue);
    expect(e(6).adviserFull, isTrue);
    expect(FacultyDirectoryEntry.fromMap('x', {'fullName': 'X'}).adviseeCount,
        0);
  });

  test('the faculty member\'s own sync writes the count to the directory',
      () async {
    final db = await world();
    await thesis(db, 'a', adviserUid: 'f1');
    await thesis(db, 'n1', status: 'nominationPendingConforme');
    await nominated(db, 'n1');
    final container = ProviderContainer(overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'f1', email: 'f1@isufst.edu.ph', isEmailVerified: true),
      )),
    ]);
    addTearDown(container.dispose);
    container.listen(ownDirectoryEntrySyncProvider, (_, _) {});
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final entry = (await db.doc('facultyDirectory/f1').get()).data()!;
    expect(entry['adviseeCount'], 2);
    expect(entry['fullName'], 'Dr. Armada');
  });
}
