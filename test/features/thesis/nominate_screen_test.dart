import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/thesis/nominate_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<void> seedFaculty(FakeFirebaseFirestore db, List<String> names) async {
  for (final f in names) {
    await db.collection('facultyDirectory').doc(f).set(
        {'fullName': 'Dr. $f', 'role': 'faculty', 'college': 'CICT'});
  }
}

Future<void> seedExOfficio(FakeFirebaseFirestore db) async {
  await db.collection('facultyDirectory').doc('coord').set(
      {'fullName': 'Dr. Bito-onon', 'role': 'coordinator', 'college': 'CICT'});
  await db.collection('facultyDirectory').doc('dean').set(
      {'fullName': 'Dr. Siason', 'role': 'dean', 'college': 'CICT'});
}

Future<void> seedThesis(FakeFirebaseFirestore db,
    {String status = 'draft'}) async {
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': [],
    'adviserUid': null, 'memberNames': [], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027',
  });
}

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await seedFaculty(db, ['Armada', 'Diamante', 'Padojinog', 'Braganza']);
  await seedExOfficio(db);
  await seedThesis(db);
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: const MaterialApp(home: NominateScreen(thesisId: 't1')),
    );

/// The nomination form has more fields than fit in the default 800x600 test
/// surface, which would otherwise leave the submit button off-screen.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// `DropdownButtonFormField` does not expose its `items` as a readable
/// field (they are closed over by the constructor, not stored), so the only
/// way to inspect what a picker actually offers is to open its overlay and
/// read the `DropdownMenuItem` widgets Flutter mounts while it is open.
/// Dismisses the overlay again afterward so later taps in the same test
/// land on the base widget tree, not a stale open menu.
Future<List<String?>> openDropdownValues(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
  final values = tester
      .widgetList<DropdownMenuItem<String>>(
          find.byType(DropdownMenuItem<String>))
      .map((i) => i.value)
      .toList();
  await tester.tapAt(const Offset(5, 5)); // dismiss the overlay
  await tester.pumpAndSettle();
  return values;
}

void main() {
  testWidgets(
      'ex officio members are shown read-only, and are also selectable as '
      'ordinary nominees for the record', (tester) async {
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dr. Bito-onon'), findsOneWidget);
    expect(find.textContaining('Dr. Siason'), findsOneWidget);
    expect(find.textContaining('added automatically'), findsOneWidget);

    // 4 plain faculty + the coordinator + the dean = 6 selectable nominees.
    // Coordinators and the dean are never chosen for their automatic
    // ex-officio seat, but the project owner ruled they may still be
    // nominated by name "for the sake of records" — so they must appear
    // here too, not be excluded the way selectableFacultyProvider excludes
    // them from the ex-officio-seat calculation.
    final values = await openDropdownValues(tester, const Key('adviser'));
    expect(values.length, 6);
    expect(values, contains('coord'));
    expect(values, contains('dean'));
  });

  testWidgets('refuses fewer than three panel members', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitNomination')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('three panel members'));
  });

  testWidgets(
      'excludes the leader from every picker even if they appear in the '
      'directory', (tester) async {
    final db = await seeded();
    // Defense in depth: the directory is not expected to contain the
    // leader's own uid (students are never upserted into it), but if it
    // somehow did, the screen must still refuse to offer self-nomination.
    await db.collection('facultyDirectory').doc('leader-1').set(
        {'fullName': 'Self Nominee', 'role': 'faculty', 'college': 'CICT'});

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final values = await openDropdownValues(tester, const Key('adviser'));
    expect(values, isNot(contains('leader-1')));
  });

  testWidgets('caps panel selection at the computed maximum and explains why',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    // 7 plain faculty + coordinator + dean (2 ex officio) so the pool
    // (9 people) comfortably exceeds the cap of 8 - 2 = 6 panelists.
    await seedFaculty(db, [
      'Armada', 'Diamante', 'Padojinog', 'Braganza', 'Reyes', 'Cruz', 'Santos'
    ]);
    await seedExOfficio(db);
    await seedThesis(db);

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    // Falsifiability: with 2 ex-officio seats, maxPanelists = 8 - 2 = 6.
    // Starts with 3 slots; tapping "+ Add panel member" 3 more times reaches
    // the cap of 6, after which the button must disable itself and a reason
    // must be visible.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('addPanelist')));
      await tester.pumpAndSettle();
    }

    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(7));
    final addButton =
        tester.widget<TextButton>(find.byKey(const Key('addPanelist')));
    expect(addButton.onPressed, isNull,
        reason: 'the add-panelist button must disable itself once the '
            'computed cap is reached');
    expect(find.byKey(const Key('panelCapReason')), findsOneWidget);
    final reason =
        tester.widget<Text>(find.byKey(const Key('panelCapReason')));
    expect(reason.data, contains('6'));

    // Tapping again (if it were still wired) must not add a 7th panel
    // picker either.
    await tester.tap(find.byKey(const Key('addPanelist')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(7));
  });

  testWidgets('refuses to submit once the thesis has left draft',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await seedFaculty(db, ['Armada', 'Diamante', 'Padojinog', 'Braganza']);
    await seedExOfficio(db);
    await seedThesis(db, status: 'nominationPendingConforme');

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notDraft')), findsOneWidget);
    expect(find.byKey(const Key('submitNomination')), findsNothing);
  });

  testWidgets(
      'rejects a nominee that no longer resolves in the faculty directory',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Armada — CICT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panel0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Diamante — CICT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panel1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Padojinog — CICT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panel2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Braganza — CICT').last);
    await tester.pumpAndSettle();

    // The chosen adviser vanishes from the directory after selection but
    // before submit — e.g. removed between the picker loading and the tap.
    await db.collection('facultyDirectory').doc('Armada').delete();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitNomination')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('no longer in the faculty directory'));

    final noms = await db.collection('theses/t1/nominations').get();
    expect(noms.docs, isEmpty,
        reason: 'an unresolvable nominee must never reach the repository');
  });

  testWidgets(
      'refuses a panel of three that collapses to two because one pick '
      'already sits ex officio', (tester) async {
    useTallSurface(tester);
    final db = await seeded();

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Armada — CICT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panel0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Diamante — CICT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('panel1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Padojinog — CICT').last);
    await tester.pumpAndSettle();

    // Third pick is the Research Coordinator, who is deliberately still
    // offered in the picker ("for the sake of records") but already holds an
    // automatic ex-officio seat. submitNominations collapses this pick into
    // that seat, so the panel would commit with TWO real members — and the
    // thesis would then wedge unrecoverably at approve().
    await tester.tap(find.byKey(const Key('panel2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Bito-onon — CICT').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitNomination')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    // The raw count is 3, so a naive `chosenUids.length >= 3` accepts this.
    // The message must name the person and say what it leaves them with,
    // otherwise the user cannot tell why three picks were refused.
    expect(error.data, contains('Dr. Bito-onon'));
    expect(error.data, contains('ex officio'));
    expect(error.data, contains('that leaves only 2'));

    final noms = await db.collection('theses/t1/nominations').get();
    expect(noms.docs, isEmpty,
        reason: 'a submission that would wedge the thesis must never reach '
            'the repository');
  });

  testWidgets('accepts three panel picks that survive the ex-officio collapse',
      (tester) async {
    // Falsifiability control for the deny above: the same screen, the same
    // taps, the same submit — with a third pick who is NOT an office holder
    // — must go through. Otherwise the refusal above could be any unrelated
    // validation failing.
    useTallSurface(tester);
    final db = await seeded();

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Armada — CICT').last);
    await tester.pumpAndSettle();

    for (final pick in [
      ('panel0', 'Dr. Diamante — CICT'),
      ('panel1', 'Dr. Padojinog — CICT'),
      ('panel2', 'Dr. Braganza — CICT'),
    ]) {
      await tester.tap(find.byKey(Key(pick.$1)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pick.$2).last);
      await tester.pumpAndSettle();
    }

    // Unlike the deny case above, this one actually reaches
    // `submitNominations`, whose batch commit is not driven by
    // `testWidgets`' fake clock — `pumpAndSettle` alone returns with `_busy`
    // still true and neither message rendered. `runAsync` gives the real
    // event loop a turn so the commit lands. Same pattern as the Task 11
    // review-queue tests.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('submitNomination')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsNothing);

    // The submission moves the thesis out of `draft`, so the screen's own
    // status stream immediately swaps the form for its "no longer draft"
    // state — the success message and the submit button go with it. That is
    // the correct behaviour (the leader continues on the status screen), so
    // the proof that this selection was ACCEPTED is the roster it committed,
    // not a message that is gone by the time we can look for it.
    expect(find.byKey(const Key('submitNomination')), findsNothing);

    // 1 adviser + 3 panelists + 2 ex-officio seats. This is the assertion
    // that distinguishes acceptance from the deny case above, where the
    // subcollection stays empty.
    final noms = await db.collection('theses/t1/nominations').get();
    expect(noms.docs.length, 6);

    // And the point of the control: three REAL panel members survived, so
    // `approve` will clear the Dean's `panelistUids.size() >= 3` floor.
    final panel = noms.docs.where((d) =>
        d.data()['position'] == 'panelist' && d.data()['exOfficio'] == false);
    expect(panel, hasLength(3));
  });
}
