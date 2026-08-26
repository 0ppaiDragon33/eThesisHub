import 'package:cloud_firestore/cloud_firestore.dart';
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
    testWidgets(
        'shows only Overview and Thesis before the title is approved',
        (tester) async {
      // Overview lands ahead of Thesis in this milestone, so the bar now
      // has two destinations (index 0 and 1) even before Chapters unlocks
      // -- it is Chapters and Defences, at indices 2 and 3, that stay gated
      // on approval. Chapters would lead straight to "Chapters are not
      // open yet".
      final db = FakeFirebaseFirestore();
      await db
          .collection('theses')
          .doc('t1')
          .set(thesis(status: 'titlePendingDefence'));

      await tester.pumpWidget(await wrap(const StudentDashboard(), db,
          uid: 'l1', role: 'student'));
      await tester.pumpAndSettle();

      // Two destinations is at the bar's own threshold, so it shows rather
      // than hides -- unlike the pre-Overview shape, where Thesis alone
      // was one destination and the bar stayed hidden.
      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Overview')),
          findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Thesis')),
          findsOneWidget);
      // Scoped to the bar, not the whole tree: the Overview body's own
      // ProgressRail spells out every lifecycle stage -- Chapters among
      // them -- as the road ahead regardless of whether it has unlocked
      // yet, so an unscoped `find.text('Chapters')` would find that label
      // and misreport the destination as present.
      expect(find.descendant(of: bar, matching: find.text('Chapters')),
          findsNothing);
      expect(find.descendant(of: bar, matching: find.text('Defences')),
          findsNothing);
    });

    testWidgets('gets a Chapters destination once the title is approved',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis());

      await tester.pumpWidget(await wrap(const StudentDashboard(), db,
          uid: 'l1', role: 'student'));
      await tester.pumpAndSettle();

      // Scoped to the bar: the Overview body's own ProgressRail also spells
      // out "Chapters" as one of the six lifecycle stages, so an unscoped
      // finder would see two matches rather than the one destination.
      final bar = find.byType(NavigationBar);
      final chaptersDestination =
          find.descendant(of: bar, matching: find.text('Chapters'));
      expect(chaptersDestination, findsOneWidget);

      await tester.tap(chaptersDestination);
      await tester.pumpAndSettle();

      // The real chapter list, not a placeholder — and only one app bar,
      // because a nested Scaffold would stack a second one with a back
      // button that goes nowhere.
      expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('faculty', () {
    testWidgets('a panelist-only member has no switch, and can reach Panels',
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

      // Overview is destination 0 now, so this member no longer lands on
      // Panels directly -- but the destination is still there, and no
      // switch renders since they hold no adviser position.
      final bar = find.byType(NavigationBar);
      expect(find.descendant(of: bar, matching: find.text('Panels')),
          findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Advisees')),
          findsNothing);
      expect(find.byType(SegmentedButton<Object?>), findsNothing);

      await tester.tap(find.descendant(of: bar, matching: find.text('Panels')));
      await tester.pumpAndSettle();
      expect(find.text('My panels'), findsOneWidget);
    });

    testWidgets('an adviser reaches Advisees and Nominations from Overview',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

      await tester.pumpWidget(await wrap(const FacultyDashboard(), db,
          uid: 'a1', role: 'faculty'));
      await tester.pumpAndSettle();

      // Overview is the landing destination (index 0) now, ahead of the
      // mode's own list.
      expect(find.byKey(const Key('facultyOverview')), findsOneWidget);

      final bar = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: bar, matching: find.text('Advisees')));
      await tester.pumpAndSettle();
      expect(find.text('My advisees'), findsOneWidget);

      await tester.tap(find.descendant(of: bar, matching: find.text('Nominations')));
      await tester.pumpAndSettle();

      // The destinations genuinely swap content. Rendering both at once is
      // what made the old single page read as a broken tab.
      expect(find.byKey(const Key('goToInbox')), findsOneWidget);
      expect(find.text('My advisees'), findsNothing);
    });
  });

  group('dean and coordinator', () {
    testWidgets('the dean gets four destinations that each swap the body',
        (tester) async {
      // Titles and Defences are separate jobs: approving a candidate title
      // set is not attending a scheduled defence. Stacked together, the
      // usually-empty title queue sat above the rooms that had content.
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(
          await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
      await tester.pumpAndSettle();

      expect(find.text('Nomination approvals'), findsOneWidget);

      await tester.tap(find.text('Titles'));
      await tester.pumpAndSettle();
      expect(find.text('Title defences'), findsOneWidget);
      expect(find.text('Nomination approvals'), findsNothing);

      await tester.tap(find.text('Defences'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduled defences'), findsOneWidget);
      expect(find.text('Title defences'), findsNothing);

      await tester.tap(find.text('Readiness'));
      await tester.pumpAndSettle();
      expect(find.text('Defence readiness'), findsOneWidget);
      expect(find.text('Scheduled defences'), findsNothing);
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

    testWidgets('the coordinator reaches Titles and Defences separately',
        (tester) async {
      // Faculty is a jump to another screen rather than a panel, and it sits
      // last — so inserting Titles moved its index. An off-by-one there
      // sends the coordinator to the wrong place and nothing else would
      // notice.
      final db = FakeFirebaseFirestore();
      await tester.pumpWidget(await wrap(const CoordinatorDashboard(), db,
          uid: 'c1', role: 'coordinator'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Titles'));
      await tester.pumpAndSettle();
      expect(find.text('Title defences'), findsOneWidget);

      await tester.tap(find.text('Defences'));
      await tester.pumpAndSettle();
      expect(find.text('Scheduled defences'), findsOneWidget);
      expect(find.text('Title defences'), findsNothing);
    });
  });

  group('adviser attending a defence', () {
    testWidgets('an adviser in adviser mode can reach their advisee\'s defence',
        (tester) async {
      // The gap this closes: DefencesList lived only in the panelist-mode
      // body, so a faculty member who advises a group and sits on no panels
      // was clamped to adviser mode and had NO route to any defence -- not
      // even the ones they advise, where they are the only person who can
      // release the consolidation to the group.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));
      await db.collection('defenses').doc('d1').set({
        'thesisId': 't1',
        'type': 'preOral',
        'scheduledAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 2))),
        'venue': 'CICT AVR',
        'panelUids': <String>[],
        'adviserUid': 'a1',
        'leaderUid': 'l1',
        'status': 'scheduled',
        'createdBy': 'c1',
      });

      await tester.pumpWidget(await wrap(const FacultyDashboard(), db,
          uid: 'a1', role: 'faculty'));
      await tester.pumpAndSettle();

      // Overview lands first now; tap into Advisees explicitly.
      final bar = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: bar, matching: find.text('Advisees')));
      await tester.pumpAndSettle();
      expect(find.text('My advisees'), findsOneWidget);

      // Defences are their own destination in both modes now, rather than a
      // section stacked under the mode's own list.
      await tester.tap(find.descendant(of: bar, matching: find.text('Defences')));
      await tester.pumpAndSettle();

      expect(find.text('My defences'), findsOneWidget);
      expect(find.byKey(const Key('goToDefence-d1')), findsOneWidget);
      // The destinations genuinely swap content.
      expect(find.text('My advisees'), findsNothing);
    });

    testWidgets('the adviser attends only — no coordinator controls',
        (tester) async {
      // Scheduling and driving the lifecycle stay with the coordinator, of
      // whom there are two, so one is always present. A control that is
      // visible and always denied is worse than no control.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

      await tester.pumpWidget(await wrap(const FacultyDashboard(), db,
          uid: 'a1', role: 'faculty'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scheduleDefence')), findsNothing);
      expect(find.byKey(const Key('openDefence')), findsNothing);
      expect(find.byKey(const Key('cancelDefence')), findsNothing);
    });
  });

  group('Defences as its own destination', () {
    testWidgets('a panelist reaches Defences without wading past the queue',
        (tester) async {
      // Stacked under Panels, the title-defence queue came FIRST -- so an
      // empty "No defences waiting" was the first thing a panelist saw, and
      // their actual schedule sat underneath it. Two unrelated lists whose
      // widgets are even named alike.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'other'));
      await db
          .collection('theses/t1/nominations')
          .doc('p1')
          .set({'nomineeUid': 'p1', 'conformeStatus': 'accepted'});
      await db.collection('defenses').doc('d1').set({
        'thesisId': 't1', 'type': 'final',
        'scheduledAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
        'venue': 'AVR', 'panelUids': <String>['p1'], 'adviserUid': 'other',
        'leaderUid': 'l1', 'status': 'scheduled', 'createdBy': 'c1',
      });

      await tester.pumpWidget(await wrap(const FacultyDashboard(), db,
          uid: 'p1', role: 'faculty'));
      await tester.pumpAndSettle();

      // Overview lands first now; tap into Panels explicitly.
      final bar = find.byType(NavigationBar);
      await tester.tap(find.descendant(of: bar, matching: find.text('Panels')));
      await tester.pumpAndSettle();
      expect(find.text('My panels'), findsOneWidget);

      await tester.tap(find.descendant(of: bar, matching: find.text('Defences')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('goToDefence-d1')), findsOneWidget);
      expect(find.text('My panels'), findsNothing);
    });

    testWidgets('the student gets Defences only once the title is approved',
        (tester) async {
      // A defence is only ever scheduled for an approved thesis, so before
      // then the tab would lead to a permanently empty page -- the
      // control-that-does-nothing this scaffold hides its bar to avoid.
      final db = FakeFirebaseFirestore();
      await db
          .collection('theses')
          .doc('t1')
          .set(thesis(status: 'titlePendingDefence'));

      await tester.pumpWidget(await wrap(const StudentDashboard(), db,
          uid: 'l1', role: 'student'));
      await tester.pumpAndSettle();

      expect(find.text('Defences'), findsNothing);
    });

    testWidgets('the student reaches Defences after approval', (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis());
      await db.collection('defenses').doc('d1').set({
        'thesisId': 't1', 'type': 'preOral',
        'scheduledAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
        'venue': 'AVR', 'panelUids': <String>[], 'adviserUid': 'a1',
        'leaderUid': 'l1', 'status': 'scheduled', 'createdBy': 'c1',
      });

      await tester.pumpWidget(await wrap(const StudentDashboard(), db,
          uid: 'l1', role: 'student'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Defences'));
      await tester.pumpAndSettle();

      expect(find.text('My defences'), findsOneWidget);
      expect(find.byKey(const Key('goToDefence-d1')), findsOneWidget);
    });
  });
}
