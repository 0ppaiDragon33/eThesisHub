import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/routing/app_router.dart';
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

Future<ProviderContainer> containerFor(
  FakeFirebaseFirestore db, {
  required String uid,
  required String role,
  // Both default `true` -- a missing designation reads as fully nominable
  // (spec §6) -- so a scenario that means "panelist only" or "adviser only"
  // must say so explicitly now that designation feeds the mode switch, not
  // rely on holding just the one position the way it did before Task 8.
  bool? nominableAsAdviser,
  bool? nominableAsPanelist,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test User',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
    'nominableAsAdviser': ?nominableAsAdviser,
    'nominableAsPanelist': ?nominableAsPanelist,
  });
  return ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    sharedPrefsProvider.overrideWithValue(prefs),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
          uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
    )),
  ]);
}

/// Wide enough (1000px) for the shell to draw its rail rather than hide the
/// destinations behind a hamburger. The narrow shape has its own coverage
/// in test/core/widgets/app_shell_test.dart and
/// test/core/routing/shell_routes_test.dart.
Future<void> pumpApp(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const EThesisHubApp()));
  await tester.pumpAndSettle();
}

/// The labels the sidebar is offering, read off the rail itself rather than
/// off the page, so a heading that happens to use the same word cannot
/// stand in for a destination that is not there.
List<String?> railLabels(WidgetTester tester) => tester
    .widget<NavigationRail>(find.byType(NavigationRail))
    .destinations
    .map((d) => (d.label as Text).data)
    .toList();

Future<void> tapDestination(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationRail), matching: find.text(label)));
  await tester.pumpAndSettle();
}

/// A destination is only worth declaring if selecting it actually shows
/// something: the shell hides its navigation below two destinations for
/// exactly that reason, because a control that does nothing when tapped
/// reads as a broken app rather than an unfinished one.
///
/// Every case here drives the REAL router. The four dashboards these tests
/// used to pump directly are gone -- navigation is one shell around every
/// signed-in route now -- so there is no widget below the router that could
/// answer "which destinations does this role get, and does each one land
/// somewhere". Bodies are asserted by their screen Key rather than by
/// heading copy, because several destination labels and page headings are
/// now the same words ('Title defences' is both), and a text finder cannot
/// tell the sidebar from the page.
void main() {
  group('student', () {
    testWidgets(
        'shows only Overview and My thesis before the title is approved',
        (tester) async {
      // Chapters and Defences stay gated on the Dean approving a title:
      // before then Chapters leads straight to "Chapters are not open yet"
      // and no defence can have been scheduled.
      final db = FakeFirebaseFirestore();
      await db
          .collection('theses')
          .doc('t1')
          .set(thesis(status: 'titlePendingDefence'));

      final c = await containerFor(db, uid: 'l1', role: 'student');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      expect(railLabels(tester), ['Overview', 'My thesis']);
    });

    testWidgets('gets a Chapters destination once the title is approved',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis());

      final c = await containerFor(db, uid: 'l1', role: 'student');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      expect(railLabels(tester), contains('Chapters'));

      await tapDestination(tester, 'Chapters');

      // The real chapter list, not a placeholder -- and still exactly one
      // app bar, the shell's. A screen that kept its own Scaffold would
      // stack a second one with a back button that goes nowhere, which is
      // the failure the `embedded` flag used to work around.
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
      //
      // A missing designation now defaults to fully nominable (spec §6), so
      // holding only a panel position is no longer, on its own, enough to
      // make someone "panelist only" -- a coordinator's explicit narrowing
      // is what does that. Seeding `nominableAsAdviser: false` is what makes
      // this genuinely a panelist-only scenario under the new rule, rather
      // than one that happens to hold no adviser position today but could
      // still be designated for it.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'other'));
      await db
          .collection('theses/t1/nominations')
          .doc('p1')
          .set({'nomineeUid': 'p1', 'conformeStatus': 'accepted'});

      final c = await containerFor(
        db,
        uid: 'p1',
        role: 'faculty',
        nominableAsAdviser: false,
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      expect(railLabels(tester), contains('Panels'));
      expect(railLabels(tester), isNot(contains('Advisees')));
      expect(find.byType(SegmentedButton<Object?>), findsNothing);

      await tapDestination(tester, 'Panels');
      expect(find.byKey(const Key('panelsScreen')), findsOneWidget);
    });

    testWidgets('an adviser reaches Advisees and Nominations from Overview',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

      final c = await containerFor(db, uid: 'a1', role: 'faculty');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      // Overview is where every role lands, ahead of the mode's own list.
      expect(find.byKey(const Key('facultyOverview')), findsOneWidget);

      await tapDestination(tester, 'Advisees');
      expect(find.byKey(const Key('adviseesScreen')), findsOneWidget);

      await tapDestination(tester, 'Nominations');

      // The destinations genuinely swap content. Rendering both at once is
      // what made the old single page read as a broken tab.
      expect(find.byKey(const Key('nominationInboxScreen')), findsOneWidget);
      expect(find.byKey(const Key('adviseesScreen')), findsNothing);
    });

    testWidgets('the mode switch moves between Advisees and Panels',
        (tester) async {
      // The switch used to sit in the faculty dashboard's app bar and swap
      // a body index. Advisees and Panels are separate ROUTES now, so
      // flipping the mode has to carry the reader across -- leaving them
      // on '/advisees' in panelist mode would show a panelist a list the
      // sidebar no longer even offers.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'f3'));
      await db.collection('theses').doc('t2').set(thesis(adviserUid: 'other'));
      await db
          .collection('theses/t2/nominations')
          .doc('f3')
          .set({'nomineeUid': 'f3', 'conformeStatus': 'accepted'});

      final c = await containerFor(db, uid: 'f3', role: 'faculty');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      // f3 holds both positions, so the switch renders.
      await tapDestination(tester, 'Advisees');
      expect(find.byKey(const Key('adviseesScreen')), findsOneWidget);

      await tester.tap(find.text('Panelist'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('panelsScreen')), findsOneWidget);
      expect(find.byKey(const Key('adviseesScreen')), findsNothing);
      expect(railLabels(tester), contains('Panels'));
      expect(railLabels(tester), isNot(contains('Advisees')));
    });
  });

  group('dean and coordinator', () {
    testWidgets('the dean gets four destinations that each swap the body',
        (tester) async {
      // Title defences and Defences are separate jobs: approving a
      // candidate title set is not attending a scheduled defence. Stacked
      // together, the usually-empty title queue sat above the rooms that
      // had content.
      final db = FakeFirebaseFirestore();
      final c = await containerFor(db, uid: 'd1', role: 'dean');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      // Overview lands first, ahead of Approvals.
      expect(find.byKey(const Key('deanOverview')), findsOneWidget);
      expect(find.byKey(const Key('approvalsScreen')), findsNothing);

      await tapDestination(tester, 'Approvals');
      expect(find.byKey(const Key('approvalsScreen')), findsOneWidget);

      await tapDestination(tester, 'Title defences');
      expect(find.byKey(const Key('titleDefencesScreen')), findsOneWidget);
      expect(find.byKey(const Key('approvalsScreen')), findsNothing);

      await tapDestination(tester, 'Defences');
      expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
      expect(find.byKey(const Key('titleDefencesScreen')), findsNothing);

      await tapDestination(tester, 'Readiness');
      expect(find.byKey(const Key('readinessScreen')), findsOneWidget);
      expect(find.byKey(const Key('defencesScreen')), findsNothing);
    });

    testWidgets('the coordinator keeps Users as a jump, not a panel',
        (tester) async {
      // Account administration is a different job from reviewing theses,
      // and it has its own screen already.
      final db = FakeFirebaseFirestore();
      final c = await containerFor(db, uid: 'c1', role: 'coordinator');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      expect(find.byKey(const Key('coordinatorOverview')), findsOneWidget);
      expect(find.byKey(const Key('recommendationsScreen')), findsNothing);

      await tapDestination(tester, 'Recommendations');
      expect(find.byKey(const Key('recommendationsScreen')), findsOneWidget);

      await tapDestination(tester, 'Readiness');
      expect(find.byKey(const Key('readinessScreen')), findsOneWidget);
      expect(find.byKey(const Key('recommendationsScreen')), findsNothing);

      await tapDestination(tester, 'Users');
      // 'Users' lands on '/users' (Accounts), not '/invites' directly --
      // Invites is the destination's other tab, see users_screen.dart.
      expect(find.byKey(const Key('usersScreen')), findsOneWidget);
      expect(find.byKey(const Key('readinessScreen')), findsNothing);
    });

    testWidgets('the coordinator reaches Titles and Defences separately',
        (tester) async {
      // Two destinations a word apart, each with its own screen. Collapsing
      // them put an empty title queue above the rooms that had content.
      final db = FakeFirebaseFirestore();
      final c = await containerFor(db, uid: 'c1', role: 'coordinator');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      await tapDestination(tester, 'Title defences');
      expect(find.byKey(const Key('titleDefencesScreen')), findsOneWidget);

      await tapDestination(tester, 'Defences');
      expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
      expect(find.byKey(const Key('titleDefencesScreen')), findsNothing);
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

      final c = await containerFor(db, uid: 'a1', role: 'faculty');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      await tapDestination(tester, 'Advisees');
      expect(find.byKey(const Key('adviseesScreen')), findsOneWidget);

      // Defences is its own destination in both modes now, rather than a
      // section stacked under the mode's own list.
      await tapDestination(tester, 'Defences');

      expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
      expect(find.byKey(const Key('goToDefence-d1')), findsOneWidget);
      // The destinations genuinely swap content.
      expect(find.byKey(const Key('adviseesScreen')), findsNothing);
    });

    testWidgets('the adviser attends only — no coordinator controls',
        (tester) async {
      // Scheduling and driving the lifecycle stay with the coordinator, of
      // whom there are two, so one is always present. A control that is
      // visible and always denied is worse than no control.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis(adviserUid: 'a1'));

      final c = await containerFor(db, uid: 'a1', role: 'faculty');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      await tapDestination(tester, 'Defences');

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
      //
      // Explicitly panelist-only (see the identical note above): a missing
      // designation now defaults to fully nominable, so without narrowing
      // this member the stored preference's default (adviser) would win
      // and 'Panels' would never appear to tap.
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

      final c = await containerFor(
        db,
        uid: 'p1',
        role: 'faculty',
        nominableAsAdviser: false,
      );
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      await tapDestination(tester, 'Panels');
      expect(find.byKey(const Key('panelsScreen')), findsOneWidget);

      await tapDestination(tester, 'Defences');

      expect(find.byKey(const Key('goToDefence-d1')), findsOneWidget);
      expect(find.byKey(const Key('panelsScreen')), findsNothing);
    });

    testWidgets('the student gets Defences only once the title is approved',
        (tester) async {
      // A defence is only ever scheduled for an approved thesis, so before
      // then the destination would lead to a permanently empty page -- the
      // control-that-does-nothing the shell hides its navigation to avoid.
      final db = FakeFirebaseFirestore();
      await db
          .collection('theses')
          .doc('t1')
          .set(thesis(status: 'titlePendingDefence'));

      final c = await containerFor(db, uid: 'l1', role: 'student');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      expect(railLabels(tester), isNot(contains('Defences')));
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

      final c = await containerFor(db, uid: 'l1', role: 'student');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      await tapDestination(tester, 'Defences');

      expect(find.byKey(const Key('defencesScreen')), findsOneWidget);
      expect(find.byKey(const Key('goToDefence-d1')), findsOneWidget);
    });
  });

  group('the shell itself', () {
    testWidgets('a deep screen keeps the sidebar AND offers a way back',
        (tester) async {
      // The field report this milestone answers, stated once here at the
      // level a reader meets it: leaving a destination used to leave you
      // with no navigation at all.
      final db = FakeFirebaseFirestore();
      await db.collection('theses').doc('t1').set(thesis());

      final c = await containerFor(db, uid: 'l1', role: 'student');
      addTearDown(c.dispose);
      await pumpApp(tester, c);

      c.read(goRouterProvider).go('/thesis/chapters/chapterI?id=t1');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chapterDetailScreen')), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byKey(const Key('shellBack')), findsOneWidget);

      // And back rises to the destination that owns this location rather
      // than to a Navigator stack that `context.go` never built.
      await tester.tap(find.byKey(const Key('shellBack')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chaptersScreen')), findsOneWidget);
    });
  });
}
