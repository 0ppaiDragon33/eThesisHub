import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/features/dashboard/overview_screen.dart';
import 'package:ethesishub/features/dashboard/student_overview.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

// Copied from navigation_test.dart -- see that file's own copy for the note
// on why each test file keeps its own rather than sharing one.
Map<String, dynamic> thesis({
  String leaderUid = 'l1',
  String adviserUid = 'a1',
  String status = 'titleApproved',
}) =>
    {
      'leaderUid': leaderUid,
      'adviserUid': adviserUid,
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': 'A Working Title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

Future<Widget> wrap(
  Widget dashboard,
  FakeFirebaseFirestore db, {
  required String uid,
  required String role,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test User',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: MaterialApp(home: dashboard),
  );
}

void main() {
  testWidgets('lands on the overview, not on a work list', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));
    // Chapters live under `theses/{id}/documents`, keyed by the full
    // ChapterId name -- not `theses/{id}/chapters` keyed by a roman
    // numeral. See document_repository.dart:14-15 and ChapterId.fromString,
    // which throws on any id that is not one of the enum's own names.
    const ids = [
      'chapterI',
      'chapterII',
      'chapterIII',
      'chapterIV',
      'chapterV',
    ];
    for (final id in ids) {
      await db.collection('theses/t1/documents').doc(id).set({
        'currentVersion': 1,
        'status': id == 'chapterI' || id == 'chapterII'
            ? 'approved'
            : 'submitted',
      });
    }

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    // The complaint that started this milestone: a student opened the app
    // onto "My thesis" and had to work out for themselves where things
    // stood.
    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
  });

  testWidgets('counts approved chapters out of five', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));
    const ids = [
      'chapterI',
      'chapterII',
      'chapterIII',
      'chapterIV',
      'chapterV',
    ];
    for (final id in ids) {
      await db.collection('theses/t1/documents').doc(id).set({
        'currentVersion': 1,
        'status': id == 'chapterI' || id == 'chapterII'
            ? 'approved'
            : 'submitted',
      });
    }

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsWidgets);
    expect(find.text('/ 5'), findsOneWidget);
  });

  testWidgets('a returned chapter appears in the queue', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));
    await db.collection('theses/t1/documents').doc('chapterIII').set({
      'currentVersion': 2,
      'status': 'revise',
    });

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chapter III'), findsOneWidget);
    expect(find.text('Revise'), findsOneWidget);
  });

  testWidgets('the greeting survives a missing profile document',
      (tester) async {
    // M2 shipped a leader lockout by gating on the profile doc. Nothing on
    // an overview may depend on `users/{uid}` existing.
    //
    // Pumped as [StudentOverview] rather than through [OverviewScreen],
    // which is the widget whose whole job is to pick an overview BY role
    // and which correctly renders nothing once the role has settled as
    // unknown — a signed-in account with no profile is routed to
    // /no-profile now, not left on an overview (spec D25). Routing it
    // through the role dispatcher would therefore assert the opposite of
    // what the app is supposed to do. The property under test is this
    // overview's own: none of its panels may gate on `users/{uid}`. That
    // it is reached at all is asserted at the router level, in
    // test/core/routing/shell_routes_test.dart.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesis(leaderUid: 'l1'));

    await tester.pumpWidget(await wrap(
      const StudentOverview(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    // Remove the profile the helper wrote.
    await db.collection('users').doc('l1').delete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('studentOverview')), findsOneWidget);
    expect(find.textContaining('Good'), findsOneWidget);
  });

  testWidgets('the progress rail marks the current stage', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(leaderUid: 'l1', status: 'titleApproved'));

    await tester.pumpWidget(await wrap(
      const OverviewScreen(),
      db,
      uid: 'l1',
      role: 'student',
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('railStep-chapters')), findsOneWidget);
    expect(find.byKey(const Key('railCurrent-chapters')), findsOneWidget);
  });
}
