import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Map<String, dynamic> thesis({
  String adviserUid = 'someone-else',
  List<String> panelistUids = const [],
  String status = 'titleApproved',
}) =>
    {
      'leaderUid': 'l1',
      'adviserUid': adviserUid,
      'panelistUids': panelistUids,
      'memberNames': <String>[],
      'workingTitle': 'T',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

/// A panel seat is detected through the nominations collection group, not
/// through `panelistUids` — `allow list` on `theses` has no panelist arm, so
/// that query is denied. Seeding the nomination is therefore what makes a
/// panel position real; seeding only `panelistUids` would leave the count at
/// zero and let a "panelist-only" test pass for the wrong reason.
Future<void> seatOnPanel(
  FakeFirebaseFirestore db,
  String thesisId,
  String uid,
) =>
    db
        .collection('theses')
        .doc(thesisId)
        .collection('nominations')
        .doc(uid)
        .set({'nomineeUid': uid, 'conformeStatus': 'accepted'});

Future<ProviderContainer> containerFor(
  FakeFirebaseFirestore db, {
  String uid = 'f1',
  String? storedMode,
}) async {
  SharedPreferences.setMockInitialValues(
      storedMode == null ? {} : {facultyModeKey: storedMode});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    sharedPrefsProvider.overrideWithValue(prefs),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: uid, email: '$uid@isufst.edu.ph'),
      ),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('adviserPositionCountProvider', () {
    test('counts the theses this faculty member actually advises', () async {
      // Shipped as `Provider<int>((ref) => 0)` with a comment saying M1 would
      // replace it. M1a and M1b came and went; it stayed 0, so the dashboard's
      // `if (holdsAdviserPositions)` was false for everyone and the
      // Adviser/Panelist switch never rendered for a single user. No test
      // overrode the provider either, so nothing caught it.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
      await db.collection('theses').doc('t2').set(thesis(adviserUid: 'f1'));
      await db.collection('theses').doc('t3').set(thesis());

      final container = await containerFor(db);
      await container.read(adviserPositionCountProvider.future);

      expect(container.read(adviserPositionCountProvider).valueOrNull, 2);
    });

    test('is zero for a faculty member who advises nothing', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis());

      final container = await containerFor(db);
      await container.read(adviserPositionCountProvider.future);

      expect(container.read(adviserPositionCountProvider).valueOrNull, 0);
    });
  });

  group('effectiveFacultyModeProvider', () {
    test('a panelist-only member is NOT left in adviser mode', () async {
      // The reported failure: FacultyMode.fromString(null) resolves to
      // adviser, so a newly invited panelist lands on an empty Advisees list
      // AND cannot leave, because the switch is hidden precisely when they
      // hold no adviser position. Stranded in a mode they never chose.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(
            thesis(panelistUids: const ['f1']),
          );
      await seatOnPanel(db, 't1', 'f1');

      final container = await containerFor(db); // no stored preference
      await container.read(effectiveFacultyModeProvider.future);

      expect(container.read(effectiveFacultyModeProvider).valueOrNull,
          FacultyMode.panelist);
    });

    test('a brand-new member with no positions lands on panelist', () async {
      // Both lists are empty either way, but Nominations sits beside Panels
      // and the Conforme request that prompted their invite is the one thing
      // actually waiting for them.
      final db = FakeFirebaseFirestore();

      final container = await containerFor(db);
      await container.read(effectiveFacultyModeProvider.future);

      expect(container.read(effectiveFacultyModeProvider).valueOrNull,
          FacultyMode.panelist);
    });

    test('an adviser-only member is held in adviser mode', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));

      // Stored preference says panelist, but they hold no panel position.
      final container = await containerFor(db, storedMode: 'panelist');
      await container.read(effectiveFacultyModeProvider.future);

      expect(container.read(effectiveFacultyModeProvider).valueOrNull,
          FacultyMode.adviser);
    });

    test('a member holding both positions keeps their stored preference',
        () async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f1'));
      await db.collection('theses').doc('t2').set(
            thesis(panelistUids: const ['f1']),
          );
      await seatOnPanel(db, 't2', 'f1');

      final container = await containerFor(db, storedMode: 'panelist');
      await container.read(effectiveFacultyModeProvider.future);

      expect(container.read(effectiveFacultyModeProvider).valueOrNull,
          FacultyMode.panelist);
    });

    test('clamping never overwrites the stored preference', () async {
      // Someone who advises nothing today is clamped to panelist, but if they
      // pick up an advisee next semester their old choice must start applying
      // again -- so the clamp reads the preference, it does not rewrite it.
      final db = FakeFirebaseFirestore();
      final container = await containerFor(db, storedMode: 'adviser');
      await container.read(effectiveFacultyModeProvider.future);

      expect(container.read(effectiveFacultyModeProvider).valueOrNull,
          FacultyMode.panelist);
      expect(container.read(facultyModeProvider), FacultyMode.adviser,
          reason: 'the stored preference is untouched');
    });
  });
}
