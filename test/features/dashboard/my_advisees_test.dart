import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

/// Seeds two theses: one advised by `a1`, one advised by `other`. Each has
/// the fields `Thesis.fromMap` requires, matching the shape written by
/// `ThesisRepository.approve` in production.
Future<FakeFirebaseFirestore> _seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('mine').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'My Advised Thesis', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  await db.collection('theses').doc('notMine').set({
    'leaderUid': 'l2', 'adviserUid': 'other', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'Someone Elses Thesis', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
  });
  return db;
}

/// Without this, `FirebaseAuth.instance` throws `[core/no-app]` because no
/// app is initialised in a widget test, `authStateProvider` settles into
/// AsyncError, and any uid read off it is silently null forever. See
/// adviser_review_test.dart's `_wrap` for the same pattern. sharedPrefsProvider
/// must also be overridden -- facultyModeProvider reads it on every build,
/// and it throws UnimplementedError unless a value is supplied.
Future<Widget> _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
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
    child: const MaterialApp(home: FacultyDashboard()),
  );
}

void main() {
  testWidgets('an adviser sees only the theses they advise', (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    // Overview is destination 0 now; the advisee list sits at destination 1.
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Advisees')));
    await tester.pumpAndSettle();

    expect(find.text('My Advised Thesis'), findsOneWidget);
    expect(find.text('Someone Elses Thesis'), findsNothing);
  });

  testWidgets('the placeholder copy is gone', (tester) async {
    final db = await _seed();
    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Advisees')));
    await tester.pumpAndSettle();

    // Shipped for two milestones, promising a list that could not exist
    // until the adviser arm on `allow list` (theses) landed. This test is
    // what stops the sentence outliving the feature it was standing in for.
    expect(find.textContaining('Coming with the documents module'),
        findsNothing);
  });

  testWidgets('a member with no positions lands on Panels, not an empty '
      'Advisees list', (tester) async {
    // The reported failure: FacultyMode.fromString(null) resolves to
    // adviser, so a newly invited faculty member landed on an empty
    // Advisees list -- and could not leave, because the mode switch hides
    // itself precisely when you hold no adviser position. The effective
    // mode is now clamped to the positions actually held.
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(await _wrap(db, uid: 'lonely'));
    await tester.pumpAndSettle();

    // Overview is destination 0 regardless of position; it is the
    // destination AFTER it -- the mode's own work -- that must be Panels,
    // not an empty Advisees list.
    final bar = find.byType(NavigationBar);
    expect(find.descendant(of: bar, matching: find.text('Panels')),
        findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Advisees')),
        findsNothing);
    expect(find.byType(ErrorWidget), findsNothing);

    await tester.tap(find.descendant(of: bar, matching: find.text('Panels')));
    await tester.pumpAndSettle();
    expect(find.text('My panels'), findsOneWidget);
    expect(find.text('My advisees'), findsNothing);
  });

  testWidgets('the advisee list is loading before the first snapshot arrives',
      (tester) async {
    final db = await _seed();
    // The mode is resolved up front so this test isolates the stream it is
    // actually about. Without it the dashboard-level mode gate renders its
    // own spinner first and the assertion would target the wrong one.
    await tester.pumpWidget(await _wrap(db, uid: 'a1', overrides: [
      effectiveFacultyModeProvider
          .overrideWith((ref) async => FacultyMode.adviser),
      // A stream that never emits, so the loading branch is genuinely
      // observable. fake_cloud_firestore resolves inside a single pump, so
      // a real query cannot hold this frame open long enough to assert on.
      myAdviseesProvider.overrideWith((ref) => StreamController<List<Thesis>>().stream),
    ]));
    // One pump resolves the (overridden, already-settled) effective mode
    // and mounts the NavigationBar at Overview; tapping into Advisees is
    // what actually starts watching the stuck `myAdviseesProvider` stream.
    // `myAdviseesProvider` itself never emits regardless of how many more
    // frames pass, so this tap-and-pump does not risk settling past the
    // state under test.
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Advisees')));
    // Deliberately NOT pumpAndSettle from here: asserts the loading branch
    // renders before the stream's first snapshot, rather than the
    // empty-list branch. Collapsing loading into an empty data(const [])
    // list would make "still loading" and "no advisees" indistinguishable
    // -- a bug this project has already shipped four times (see the
    // comment on adviseesAsync.when in faculty_dashboard.dart).
    await tester.pump();

    // The whole dashboard waits on the effective mode, because the mode
    // decides which destinations exist -- defaulting while it resolves
    // would show a panelist the Advisees tab and swap it out from under
    // them on every launch. So one spinner, and no resolved content.
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('My Advised Thesis'), findsNothing);
    expect(find.text('No advisees yet'), findsNothing);
  });

  testWidgets('an advisee row shows a count of chapters awaiting review',
      (tester) async {
    final db = await _seed();
    await db
        .collection('theses/mine/documents')
        .doc('chapterI')
        .set({'currentVersion': 1, 'status': 'submitted'});
    await db
        .collection('theses/mine/documents')
        .doc('chapterII')
        .set({'currentVersion': 1, 'status': 'submitted'});
    await db
        .collection('theses/mine/documents')
        .doc('chapterIII')
        .set({'currentVersion': 1, 'status': 'approved'});

    await tester.pumpWidget(await _wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Advisees')));
    await tester.pumpAndSettle();

    expect(find.text('2 chapters awaiting review'), findsOneWidget);
  });

  testWidgets(
      'the awaiting-review count is NOT shown as "0" while its stream is '
      'still loading', (tester) async {
    // Deliberately bare pump()s, never pumpAndSettle: this must observe
    // the chapter stream's loading branch, not its settled state. "0
    // awaiting" and "still loading" are indistinguishable to a reader, and
    // collapsing the two is the single most repeated bug in this codebase.
    // Two pumps, same reasoning as the analogous case in
    // defence_readiness_list_test.dart: the first resolves the outer
    // myAdviseesProvider stream (mounting the advisee's own card), the
    // second lets that card's chaptersProvider start -- but its stream has
    // not emitted yet, so the card's own loading branch is what should show.
    final db = await _seed();
    // The mode is resolved up front so this test isolates the stream it is
    // actually about. Without it the dashboard-level mode gate renders its
    // own spinner first and the assertion would target the wrong one.
    await tester.pumpWidget(await _wrap(db, uid: 'a1', overrides: [
      effectiveFacultyModeProvider
          .overrideWith((ref) async => FacultyMode.adviser),
      // A chapter stream that never emits, so the card's own loading branch
      // is genuinely observable -- fake_cloud_firestore settles inside a
      // pump, which is why the previous two-pump timing no longer holds.
      chaptersProvider('mine')
          .overrideWith((ref) => StreamController<List<ThesisChapter>>().stream),
    ]));
    // An extra pump-and-tap to reach the mode body at destination 1 (Overview
    // now sits at 0), then the same two-pump timing as before: the first
    // resolves myAdviseesProvider (mounting the advisee's own card), the
    // second lets that card's chaptersProvider start -- but its stream has
    // not emitted yet, so the card's own loading branch is what should show.
    await tester.pump();
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Advisees')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Awaiting review: still loading…'), findsOneWidget);
    expect(find.textContaining('0 chapters awaiting review'), findsNothing);
    expect(find.text('Nothing awaiting review'), findsNothing);
  });
}
