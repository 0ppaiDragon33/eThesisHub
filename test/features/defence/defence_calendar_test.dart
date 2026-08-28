import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_calendar.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Same seeding shape as `defences_list_test.dart`'s `_seedDefence`, kept
/// local: a null `scheduledAt` is central to this file's tests, and the
/// list's fixture helper requires a date.
Future<void> _seedDefence(
  FakeFirebaseFirestore db, {
  required String id,
  required String adviserUid,
  DateTime? scheduledAt,
  String status = 'scheduled',
  String type = 'preOral',
  List<String> panelUids = const [],
}) async {
  await db.collection('defenses').doc(id).set({
    'thesisId': 't-$id',
    'type': type,
    'scheduledAt': scheduledAt == null ? null : Timestamp.fromDate(scheduledAt),
    'venue': 'Room $id',
    'panelUids': panelUids,
    'adviserUid': adviserUid,
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
  });
}

Future<FakeFirebaseFirestore> _seedUser(String uid,
    {String role = 'faculty'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'Faculty $uid',
    'email': '$uid@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return db;
}

Widget _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  List<Override> overrides = const [],
  Size surfaceSize = const Size(800, 1200),
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
        )),
        ...overrides,
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: surfaceSize),
          child: const Scaffold(
              body: SingleChildScrollView(child: DefenceCalendar())),
        ),
      ),
    );

void main() {
  // Fixed "today" region: seed dates well inside a specific month so the
  // grid always lands on it regardless of when the suite runs -- the widget
  // opens on the CURRENT month, so tests navigate to September 2026 with the
  // next/prev arrows rather than assuming it is already shown.
  Future<void> gotoSeptember2026(WidgetTester tester) async {
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

  testWidgets('a defence appears on its scheduled day, not adjacent days',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(
      db,
      id: 'd1',
      adviserUid: 'f1',
      scheduledAt: DateTime(2026, 9, 15, 9),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();
    await gotoSeptember2026(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('calendarCell-2026-09-15')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('calendarCell-2026-09-14')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d1')), findsNothing);

    await tester.tap(find.byKey(const Key('calendarCell-2026-09-16')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d1')), findsNothing);
  });

  testWidgets(
      'a defence with no confirmed date appears in the awaiting-a-date '
      'line and on no day cell', (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(db, id: 'noDate', adviserUid: 'f1');
    await _seedDefence(
      db,
      id: 'dated',
      adviserUid: 'f1',
      scheduledAt: DateTime(2026, 9, 15, 9),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();
    await gotoSeptember2026(tester);
    await tester.pumpAndSettle();

    // Present in the awaiting line, un-conditionally (not behind a tap on
    // any particular day).
    expect(find.text('1 defence awaiting a date'), findsOneWidget);
    expect(find.byKey(const Key('defenceRow-noDate')), findsOneWidget);

    // Not on any day cell: every day in the grid, tapped, must not surface
    // it. Checked against the one day it could plausibly leak onto if a
    // null date fell back to the epoch or "day 1" -- the trap the spec
    // calls out explicitly.
    await tester.tap(find.byKey(const Key('calendarCell-2026-09-01')));
    await tester.pumpAndSettle();
    final panelNoDate = find.descendant(
      of: find.byKey(const Key('calendarDayPanel')),
      matching: find.byKey(const Key('defenceRow-noDate')),
    );
    expect(panelNoDate, findsNothing);
  });

  testWidgets('a cancelled defence is shown muted, not hidden',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(
      db,
      id: 'cancelled1',
      adviserUid: 'f1',
      scheduledAt: DateTime(2026, 9, 15, 9),
      status: 'cancelled',
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();
    await gotoSeptember2026(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('calendarCell-2026-09-15')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-cancelled1')), findsOneWidget);
  });

  testWidgets('the day panel lists a busy day in time order', (tester) async {
    final db = await _seedUser('f1');
    // Seeded out of time order on purpose.
    await _seedDefence(
      db,
      id: 'late',
      adviserUid: 'f1',
      scheduledAt: DateTime(2026, 9, 15, 15, 0),
    );
    await _seedDefence(
      db,
      id: 'early',
      adviserUid: 'f1',
      scheduledAt: DateTime(2026, 9, 15, 9, 0),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();
    await gotoSeptember2026(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('calendarCell-2026-09-15')));
    await tester.pumpAndSettle();

    final early = find.byKey(const Key('defenceRow-early'));
    final late = find.byKey(const Key('defenceRow-late'));
    expect(early, findsOneWidget);
    expect(late, findsOneWidget);
    expect(tester.getTopLeft(early).dy, lessThan(tester.getTopLeft(late).dy));
  });

  testWidgets('an empty month is distinguishable from a failed read',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(
      db,
      id: 'd1',
      adviserUid: 'f1',
      scheduledAt: DateTime(2026, 9, 15, 9),
    );

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();
    // Navigate far away from September so the visible month is empty, while
    // the underlying read plainly succeeded (the awaiting-a-date /
    // legend chrome is present, not an error box).
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('calendarNextMonth')));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Could not load your defences.'), findsNothing);
    expect(find.byKey(const Key('defenceCalendar')), findsOneWidget);
  });

  testWidgets('a genuinely failed read shows the error state, not an empty '
      'grid', (tester) async {
    final db = await _seedUser('f1');
    await tester.pumpWidget(_wrap(
      db,
      uid: 'f1',
      overrides: [
        myDefencesProvider.overrideWith(
            (ref) => Stream<List<Defence>>.error('boom')),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your defences.'), findsOneWidget);
    expect(find.byKey(const Key('calendarCell-2026-09-15')), findsNothing);
  });

  testWidgets(
      'no defences at all shows the empty state, not an empty grid, and '
      'not loading or error text', (tester) async {
    // Distinct from "an empty month is distinguishable from a failed
    // read" above: that test seeds a real defence and merely navigates to
    // a month with nothing in it, so the underlying dataset is non-empty
    // and the calendar chrome (legend, grid) renders. This is the OTHER
    // branch -- the account has no defences at all -- which
    // defence_calendar.dart handles with its own EmptyState, separate
    // from both the loading and the error branch.
    final db = await _seedUser('f1');

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noDefences')), findsOneWidget);
    expect(find.text('No defences scheduled'), findsOneWidget);
    expect(find.byKey(const Key('defenceCalendar')), findsNothing);
    expect(find.text('Loading your defences…'), findsNothing);
    expect(find.text('Could not load your defences.'), findsNothing);
  });

  testWidgets('a loading month is not shown as empty', (tester) async {
    final db = await _seedUser('f1');
    final neverDefences = StreamController<List<Defence>>();
    addTearDown(neverDefences.close);

    await tester.pumpWidget(_wrap(
      db,
      uid: 'f1',
      overrides: [
        myDefencesProvider.overrideWith((ref) => neverDefences.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading your defences…'), findsOneWidget);
    expect(find.byKey(const Key('defenceCalendar')), findsNothing);
  });

  testWidgets('the grid does not overflow at 360px width', (tester) async {
    final db = await _seedUser('f1');
    // Four defences on one day, to stress the dot row specifically.
    for (final s in ['a', 'b', 'c', 'd']) {
      await _seedDefence(
        db,
        id: 'd$s',
        adviserUid: 'f1',
        scheduledAt: DateTime(2026, 9, 15, 9),
      );
    }
    await _seedDefence(db, id: 'noDate', adviserUid: 'f1');

    await tester.pumpWidget(
        _wrap(db, uid: 'f1', surfaceSize: const Size(360, 800)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
