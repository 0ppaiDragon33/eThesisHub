import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/features/dashboard/dean_dashboard.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

// Same shape as navigation_test.dart's own copy -- every field
// `Thesis.fromMap` requires, so a seeded document reads back cleanly.
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
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test Dean',
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
      ...overrides,
    ],
    child: MaterialApp(home: dashboard),
  );
}

void main() {
  testWidgets('the dean lands on the overview, not the approvals list',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
        await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    // The complaint this task answers: the dean landed on the approvals
    // queue with nothing summarising the college around it.
    expect(find.byKey(const Key('deanOverview')), findsOneWidget);
    expect(find.text('Nomination approvals'), findsNothing);

    final bar = find.byType(NavigationBar);
    expect(find.descendant(of: bar, matching: find.text('Overview')),
        findsOneWidget);
  });

  testWidgets(
      'a thesis awaiting the dean\'s approval appears in the queue',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .collection('theses')
        .doc('t1')
        .set(thesis(status: 'nominationPendingDean'));

    await tester.pumpWidget(
        await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    expect(find.text('A Working Title'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('both college-wide chart panels are present', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
        await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    expect(find.text('Theses by stage'), findsOneWidget);
    expect(find.textContaining('Past 7 months'), findsOneWidget);
  });

  testWidgets('the four tiles render', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(
        await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
    await tester.pumpAndSettle();

    expect(find.text('Awaiting your approval'), findsOneWidget);
    expect(find.text('Title defences'), findsOneWidget);
    expect(find.text('Defences this week'), findsOneWidget);
    expect(find.text('Active theses'), findsOneWidget);
  });

  testWidgets('a loading queue is distinguishable from an empty one',
      (tester) async {
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(await wrap(
      const DeanDashboard(),
      db,
      uid: 'd1',
      role: 'dean',
      overrides: [
        // A stream that never emits, so the queue's own loading branch is
        // genuinely observable rather than settling into "All caught up".
        deanNeedsYouProvider.overrideWith(
            (ref) => StreamController<List<NeedsYouItem>>().stream),
      ],
    ));
    // Deliberately a single pump, never pumpAndSettle: this must catch the
    // loading branch before the (never-emitting) stream's first snapshot,
    // not the empty-list branch that a collapsed `data(const [])` would be
    // indistinguishable from.
    await tester.pump();

    expect(find.text('Checking what needs you…'), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
  });

  testWidgets('the greeting survives a missing profile document',
      (tester) async {
    // An earlier milestone shipped a lockout by gating on the profile doc.
    // Nothing on an overview may depend on `users/{uid}` existing.
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(
        await wrap(const DeanDashboard(), db, uid: 'd1', role: 'dean'));
    // Remove the profile the helper wrote.
    await db.collection('users').doc('d1').delete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('deanOverview')), findsOneWidget);
    expect(find.textContaining('Good'), findsOneWidget);
  });
}
