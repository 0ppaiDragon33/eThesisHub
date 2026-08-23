import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/features/dashboard/coordinator_dashboard.dart';
import 'package:ethesishub/features/dashboard/dean_dashboard.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/features/dashboard/student_dashboard.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

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

/// A destination is only worth declaring if selecting it actually shows
/// something. `ResponsiveScaffold` hides its bar below two destinations for
/// exactly this reason: a control that does nothing when tapped reads as a
/// broken app rather than an unfinished one.
void main() {
  group('student', () {
    testWidgets('gets no bar before the title is approved', (tester) async {
      final db = FakeFirebaseFirestore();
      await db
          .collection('theses')
          .doc('t1')
          .set(thesis(status: 'titlePendingDefence'));

      await tester.pumpWidget(await wrap(const StudentDashboard(), db,
          uid: 'l1', role: 'student'));
      await tester.pumpAndSettle();

      // Chapters would lead straight to "Chapters are not open yet".
      expect(find.text('Chapters'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('gets a Chapters destination once the title is approved',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis());

      await tester.pumpWidget(await wrap(const StudentDashboard(), db,
          uid: 'l1', role: 'student'));
      await tester.pumpAndSettle();

      expect(find.text('Chapters'), findsOneWidget);

      await tester.tap(find.text('Chapters'));
      await tester.pumpAndSettle();

      // The real chapter list, not a placeholder — and only one app bar,
      // because a nested Scaffold would stack a second one with a back
      // button that goes nowhere.
      expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('faculty', () {
    testWidgets('a panelist-only member sees Panels first, and no switch',
        (tester) async {
      // The reported bug: they landed on an empty Advisees list and could
      // not leave, because the switch hides itself precisely when you hold
      // no adviser position.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'other'));
      await db
          .collection('theses/t1/nominations')
          .doc('p1')
          .set({'nomineeUid': 'p1', 'conformeStatus': 'accepted'});

      await tester.pumpWidget(await wrap(const FacultyDashboard(), db,
          uid: 'p1', role: 'faculty'));
      await tester.pumpAndSettle();

      expect(find.text('Panels'), findsWidgets);
      expect(find.text('Advisees'), findsNothing);
      expect(find.byType(SegmentedButton<Object?>), findsNothing);
    });

    testWidgets('an adviser sees Advisees first and can reach Nominations',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

      await tester.pumpWidget(await wrap(const FacultyDashboard(), db,
          uid: 'a1', role: 'faculty'));
      await tester.pumpAndSettle();

      expect(find.text('Advisees'), findsWidgets);
      expect(find.text('My advisees'), findsOneWidget);

      await tester.tap(find.text('Nominations'));
      await tester.pumpAndSettle();

      // The destinations genuinely swap content. Rendering both at once is
      // what made the old single page read as a broken tab.
      expect(find.byKey(const Key('goToInbox')), findsOneWidget);
      expect(find.text('My advisees'), findsNothing);
    });
  });

  group('dean and coordinator', () {
    testWidgets('the dean gets three destinations that each swap the body',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
          await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
      await tester.pumpAndSettle();

      expect(find.text('Nomination approvals'), findsOneWidget);

      await tester.tap(find.text('Defences'));
      await tester.pumpAndSettle();
      expect(find.text('Title defences'), findsOneWidget);
      expect(find.text('Nomination approvals'), findsNothing);

      await tester.tap(find.text('Readiness'));
      await tester.pumpAndSettle();
      expect(find.text('Defence readiness'), findsOneWidget);
      expect(find.text('Title defences'), findsNothing);
    });

    testWidgets('the coordinator keeps Faculty as a jump, not a panel',
        (tester) async {
      // Invites are a different job from reviewing theses, and they have
      // their own screen already.
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(await wrap(const CoordinatorDashboard(), db,
          uid: 'c1', role: 'coordinator'));
      await tester.pumpAndSettle();

      expect(find.text('Nomination recommendations'), findsOneWidget);

      await tester.tap(find.text('Readiness'));
      await tester.pumpAndSettle();
      expect(find.text('Defence readiness'), findsOneWidget);
      expect(find.text('Nomination recommendations'), findsNothing);
    });
  });
}
