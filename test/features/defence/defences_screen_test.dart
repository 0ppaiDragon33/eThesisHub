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
  required DateTime scheduledAt,
}) async {
  await db.collection('defenses').doc(id).set({
    'thesisId': 't-$id',
    'type': 'preOral',
    'scheduledAt': Timestamp.fromDate(scheduledAt),
    'venue': 'Room $id',
    'panelUids': const <String>[],
    'adviserUid': adviserUid,
    'leaderUid': 'l1',
    'status': 'scheduled',
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

void main() {
  testWidgets('defaults to the list view, with a calendar toggle available',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(db,
        id: 'd1', adviserUid: 'f1', scheduledAt: DateTime(2026, 9, 15, 9));

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    expect(find.byKey(const Key('defencesViewCalendar')), findsOneWidget);
  });

  testWidgets('toggling to Calendar shows the same defence, and back again',
      (tester) async {
    final db = await _seedUser('f1');
    await _seedDefence(db,
        id: 'd1', adviserUid: 'f1', scheduledAt: DateTime(2026, 9, 15, 9));

    await tester.pumpWidget(_wrap(db, uid: 'f1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('defencesViewCalendar')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceCalendar')), findsOneWidget);
    // The same defence exists somewhere in the calendar presentation too --
    // either on its cell (once navigated to) or, at minimum, the calendar
    // must not silently drop it. Navigate to its day directly.
    var months =
        (2026 - DateTime.now().year) * 12 + (9 - DateTime.now().month);
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendarCell-2026-09-15')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('defencesViewList')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('defenceRow-d1')), findsOneWidget);
    expect(find.byKey(const Key('defenceCalendar')), findsNothing);
  });
}
