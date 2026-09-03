import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/defence/defences_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<void> _seedDefence(
  FakeFirebaseFirestore db, {
  required String id,
  required String adviserUid,
  DateTime? scheduledAt,
  String status = 'scheduled',
}) async {
  await db.collection('defenses').doc(id).set({
    'thesisId': 't-$id',
    'type': 'preOral',
    'scheduledAt': scheduledAt == null ? null : Timestamp.fromDate(scheduledAt),
    'venue': 'Room $id',
    'panelUids': const <String>[],
    'adviserUid': adviserUid,
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
  });
}

Future<FakeFirebaseFirestore> _seedUser(String uid) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'Faculty $uid',
    'email': '$uid@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  return db;
}

Widget _wrap(FakeFirebaseFirestore db, {required String uid}) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: const MaterialApp(home: Scaffold(body: DefencesScreen())),
    );

/// PageShell scrolls, but the default 800x600 test surface still leaves
/// calendar cells (below the grid AND the day panel) below the fold, so a
/// plain tap misses them -- see `tester.view.physicalSize` used the same
/// way in `page_shell_test.dart` and `title_defence_screen_test.dart`.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Steps the calendar from whatever month it opened on (the real "today")
/// to September 2026, the month every fixture in this file schedules into.
Future<void> _gotoSeptember2026(WidgetTester tester) async {
  final now = DateTime.now();
  var months = (2026 - now.year) * 12 + (9 - now.month);
  while (months > 0) {
    await tester.tap(find.byKey(const Key('calendarNextMonth')));
    await tester.pump();
    months--;
  }
  while (months < 0) {
    await tester.tap(find.byKey(const Key('calendarPrevMonth')));
    await tester.pump();
    months++;
  }
}

void main() {
  testWidgets('defaults to the list view, with a calendar toggle available',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(db,
        id: 'd1', adviserUid: 'f1', scheduledAt: DateTime(2026, 9, 15, 9));

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    // One SegmentedButton, not two separate buttons -- see
    // faculty_mode_switch.dart's facultyModeSegmented for the pattern this
    // follows: the control is keyed, its segments are found by label.
    expect(find.byKey(const Key('defencesViewToggle')), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
  });

  testWidgets(
      'toggling to Calendar shows the same defence, and back again '
      '(single-defence smoke test)', (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(db,
        id: 'd1', adviserUid: 'f1', scheduledAt: DateTime(2026, 9, 15, 9));

    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceCalendar')), findsOneWidget);
    await _gotoSeptember2026(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendarCell-2026-09-15')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    expect(find.byKey(const Key('defenceCalendar')), findsNothing);
  });

  testWidgets(
      'the same full set of defences is reachable in both views -- '
      'across days, a cancelled one, and one with no confirmed date',
      (tester) async {
    final db = await _seedUser('f1');
    // Two on the same day (one of them cancelled -- must stay visible, not
    // filtered out by either view), one on a different day, and one with a
    // null scheduledAt, which a bucketing bug could drop from the calendar
    // entirely instead of routing it to the awaiting-a-date line. If the
    // list and the calendar ever read from different sources, or one of
    // them silently filters cancelled or dateless defences, this is the
    // test that catches the divergence -- a single-defence toggle smoke
    // test cannot.
    await _seedDefence(db,
        id: 'd1', adviserUid: 'f1', scheduledAt: DateTime(2026, 9, 15, 9));
    await _seedDefence(db,
        id: 'd2',
        adviserUid: 'f1',
        scheduledAt: DateTime(2026, 9, 15, 14),
        status: 'cancelled');
    await _seedDefence(db,
        id: 'd3', adviserUid: 'f1', scheduledAt: DateTime(2026, 9, 20, 9));
    await _seedDefence(db, id: 'd4', adviserUid: 'f1');

    _useTallSurface(tester);
    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    // The list shows all four.
    for (final id in ['d1', 'd2', 'd3', 'd4']) {
      expect(find.byKey(Key('defenceRow-$id')), findsOneWidget,
          reason: 'list view is missing $id');
    }

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await _gotoSeptember2026(tester);
    await tester.pumpAndSettle();

    // d4 (no confirmed date) is reachable via the awaiting-a-date line,
    // without tapping into any day at all.
    expect(find.byKey(const Key('defenceRow-d4')), findsOneWidget,
        reason: 'the dateless defence must sit in the awaiting-a-date line');

    // Day 15 carries both d1 and the cancelled d2.
    await tester.tap(find.byKey(const Key('calendarCell-2026-09-15')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    expect(find.byKey(const Key('defenceRow-d2')), findsOneWidget,
        reason: 'a cancelled defence must stay visible in the day panel');
    // d4's row is still present (the awaiting section never disappears),
    // but d3 (a different day) must not leak onto day 15's panel.
    expect(find.byKey(const Key('defenceRow-d3')), findsNothing);

    // Day 20 carries only d3.
    await tester.tap(find.byKey(const Key('calendarCell-2026-09-20')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d3')), findsOneWidget);
    expect(find.byKey(const Key('defenceRow-d1')), findsNothing);
    expect(find.byKey(const Key('defenceRow-d2')), findsNothing);

    // Every id the list showed is reachable somewhere in the calendar
    // presentation too -- the same set, not a subset.
    expect(find.byKey(const Key('defenceRow-d4')), findsOneWidget);
  });
}
