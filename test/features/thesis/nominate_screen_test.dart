import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/features/thesis/nominate_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Rejects every submission with `permission-denied`, as the real security
/// rules would when a nominee's `users/{uid}` designation disagrees with
/// the (client-written, self-maintained) `facultyDirectory` mirror the
/// picker actually reads — the sync window spec §4.2.1 describes.
class PermissionDeniedThesisRepository extends ThesisRepository {
  PermissionDeniedThesisRepository(super.db);

  @override
  Future<void> submitNominations({
    required String thesisId,
    required FacultyDirectoryEntry adviser,
    required List<FacultyDirectoryEntry> panelists,
    required List<FacultyDirectoryEntry> exOfficio,
  }) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}

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

Widget wrap(FakeFirebaseFirestore db,
        {List<Override> extraOverrides = const []}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
        ...extraOverrides,
      ],
      // A router rather than a bare home, because a successful submission
      // navigates to the thesis status screen. Staying put used to leave the
      // leader looking at "Nominations can only be submitted while this
      // thesis is still a draft" — a refusal message, immediately after the
      // submission succeeded.
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/thesis/nominate',
          routes: [
            GoRoute(
              path: '/thesis/nominate',
              // the app shell supplies the Scaffold in the real app.
              builder: (_, _) =>
                  const Scaffold(body: NominateScreen(thesisId: 't1')),
            ),
            GoRoute(
              path: '/thesis',
              builder: (_, _) => const Scaffold(
                body: Center(
                    child: Text('status', key: Key('landedOnStatus'))),
              ),
            ),
          ],
        ),
      ),
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

  testWidgets('shows the form on first arrival, not the draft-only refusal',
      (tester) async {
    // Reported from the running app: tapping "Nominate adviser and panel"
    // showed the "only while this thesis is still a draft" message, and the
    // form only appeared after a refresh.
    //
    // The screen watched `myThesisProvider`, which reads
    // `authStateProvider.value?.uid` and returns `Stream.value(null)` when
    // that is null — so while auth was still settling it resolved to
    // `data(null)`, not loading, and the screen read a missing thesis as a
    // thesis that had left draft. A refresh "fixed" it only because auth
    // was warm the second time.
    //
    // Holding auth unsettled here reproduces that first arrival exactly.
    useTallSurface(tester);
    final db = await seeded();
    final authController = StreamController<User?>();
    addTearDown(authController.close);

    await tester.pumpWidget(wrap(db, extraOverrides: [
      authStateProvider.overrideWith((ref) => authController.stream),
    ]));
    await tester.pump();

    // Auth has not emitted. The thesis is a draft, so the form must show —
    // the screen was handed a thesis id and does not need to know who is
    // signed in to render it.
    expect(find.byKey(const Key('notDraft')), findsNothing,
        reason: 'a still-settling auth stream is not a thesis that has '
            'moved past draft');
    expect(find.byKey(const Key('adviser')), findsOneWidget);

    authController.add(MockUser(
        uid: 'leader-1', email: 'l@isufst.edu.ph', isEmailVerified: true));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adviser')), findsOneWidget);
  });

  testWidgets('a person chosen in one slot is not offered in the others',
      (tester) async {
    // The nomination documents are keyed by uid, so picking the same person
    // twice is not two seats — the second write overwrites the first. Left
    // unfiltered, the same name could fill the adviser slot and every panel
    // slot, and the only complaint came at submit: "Choose at least three
    // panel members" while three dropdowns visibly held names, because
    // `chosenUids` is a Set and the duplicates had collapsed.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Armada — CICT').last);
    await tester.pumpAndSettle();

    // `openDropdownValues` sees every DropdownMenuItem mounted at the time,
    // which is the opened menu PLUS the item each other picker renders to
    // display its own current selection. So a chosen person still appears
    // once — as that chip — and the question is whether they appear a SECOND
    // time as an entry in this menu. Counting occurrences says exactly that;
    // `isNot(contains(...))` would be testing the chip, not the filter.
    final panel0 = await openDropdownValues(tester, const Key('panel0'));
    expect(panel0.where((v) => v == 'Armada'), hasLength(1),
        reason: 'the adviser chip only — Armada must not also be offered '
            'as a panel member');
    expect(panel0, contains('Diamante'));

    await tester.tap(find.byKey(const Key('panel0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Diamante — CICT').last);
    await tester.pumpAndSettle();

    // A second panel slot now excludes both the adviser and panel 1 — two
    // chips, no menu entries.
    final panel1 = await openDropdownValues(tester, const Key('panel1'));
    expect(panel1.where((v) => v == 'Armada'), hasLength(1));
    expect(panel1.where((v) => v == 'Diamante'), hasLength(1));
    expect(panel1, contains('Padojinog'));

    // And the slot holding a pick must still offer that pick, or
    // DropdownButtonFormField asserts its value matches exactly one item:
    // its own menu entry plus its own chip.
    expect(await openDropdownValues(tester, const Key('panel0'))
        .then((v) => v.where((x) => x == 'Diamante')), hasLength(2));
  });

  testWidgets('an option with no college shows no dangling separator',
      (tester) async {
    // Nothing in the app fills college or specialization, so for a real
    // faculty account `subtitle` is empty and a hardcoded ' — ' rendered
    // every option as "Dr. Armada — ".
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('facultyDirectory').doc('bare').set(
        {'fullName': 'Dr. Bare', 'role': 'faculty'});
    await seedThesis(db);

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();

    expect(find.text('Dr. Bare'), findsWidgets);
    expect(find.textContaining('Dr. Bare —'), findsNothing);
  });

  testWidgets('an ex-officio office holder is labelled as one in the picker',
      (tester) async {
    // They stay nominable by name on purpose, but they also hold an
    // automatic seat, so picking one as a PANEL member adds nobody and is
    // refused at submit. The label is what makes that legible beforehand.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();

    // Assert the picker's FULL label, college included. The "Also on your
    // panel" card below renders '<name> — <role>' too, so the shorter string
    // matches whether or not the picker labels anything — this test passed
    // with the role suffix deleted until the college was added to it.
    // `findsWidgets`, not `findsOneWidget`: a closed DropdownButtonFormField
    // still builds its items offstage to size itself, so each picker on
    // screen contributes a copy.
    expect(find.text('Dr. Bito-onon — coordinator · CICT'), findsWidgets);
    expect(find.text('Dr. Siason — dean · CICT'), findsWidgets);
    // An ordinary faculty member gets no role suffix.
    expect(find.textContaining('Dr. Armada — faculty'), findsNothing);
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
      'a panel picker never offers an ex-officio office holder, but the '
      'adviser picker does', (tester) async {
    // Choosing a coordinator or the dean as a PANEL member adds nobody:
    // submitNominations collapses the pick into the automatic ex-officio seat
    // they already hold, so a panel of three would commit as two and the
    // thesis would wedge unrecoverably at approve(). The screen used to offer
    // the choice and then refuse it at submit; it no longer offers it.
    //
    // The adviser slot must still offer them. A coordinator or the dean can
    // genuinely advise a thesis — that position carries exOfficio: false,
    // needs their Conforme, and prints on Form 1 as Thesis Adviser.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    final adviser = await openDropdownValues(tester, const Key('adviser'));
    expect(adviser, contains('coord'));
    expect(adviser, contains('dean'));

    for (final slot in ['panel0', 'panel1', 'panel2']) {
      final panel = await openDropdownValues(tester, Key(slot));
      expect(panel, isNot(contains('coord')), reason: '$slot offered a coordinator');
      expect(panel, isNot(contains('dean')), reason: '$slot offered the dean');
      // The four ordinary faculty are all still there.
      expect(panel, containsAll(['Armada', 'Diamante', 'Padojinog', 'Braganza']));
    }
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

    // A successful submission navigates to the thesis status screen, where
    // the leader watches each Conforme arrive. Before this, the screen
    // stayed put and its own status stream replaced the form with
    // "Nominations can only be submitted while this thesis is still a
    // draft" — a refusal message shown immediately after success.
    expect(find.byKey(const Key('landedOnStatus')), findsOneWidget);
    expect(find.byKey(const Key('submitNomination')), findsNothing);
    expect(find.byKey(const Key('notDraft')), findsNothing,
        reason: 'the leader must never be shown the draft-only refusal as '
            'the outcome of a successful submission');

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

  testWidgets(
      'an adviser-only entry appears in the adviser picker and not the '
      'panel picker', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    // Designated for adviser only — a coordinator ticked one box and left
    // the other unticked on the Users screen.
    await db.collection('facultyDirectory').doc('Armada').update({
      'nominableAsAdviser': true,
      'nominableAsPanelist': false,
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final adviser = await openDropdownValues(tester, const Key('adviser'));
    expect(adviser, contains('Armada'));

    final panel = await openDropdownValues(tester, const Key('panel0'));
    expect(panel, isNot(contains('Armada')),
        reason: 'not designated as a panelist, so the panel picker must '
            'not offer them');
  });

  testWidgets(
      'a panelist-only entry appears in the panel picker and not the '
      'adviser picker', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    // Designated for panel only — the reverse of the case above.
    await db.collection('facultyDirectory').doc('Armada').update({
      'nominableAsAdviser': false,
      'nominableAsPanelist': true,
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final adviser = await openDropdownValues(tester, const Key('adviser'));
    expect(adviser, isNot(contains('Armada')),
        reason: 'not designated as an adviser, so the adviser picker must '
            'not offer them');

    final panel = await openDropdownValues(tester, const Key('panel0'));
    expect(panel, contains('Armada'));
  });

  testWidgets(
      'an entry with no designation fields at all is offered for both '
      'positions', (tester) async {
    // Every account predates these two fields, and the sync window in spec
    // §4.2.1 produces the same shape for a brand-new one: absence must
    // default to nominable, or the deploy would empty the picker of the
    // entire existing faculty. `seedFaculty` never sets either field, so
    // this is the ordinary case, asserted explicitly.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    final adviser = await openDropdownValues(tester, const Key('adviser'));
    expect(adviser, contains('Armada'));

    final panel = await openDropdownValues(tester, const Key('panel0'));
    expect(panel, contains('Armada'));
  });

  testWidgets(
      'an office holder narrowed out of adviser is absent from the adviser '
      'picker, and their panel-seat exemption is untouched', (tester) async {
    // D32 exempts the ex-officio SEAT, not the adviser slot. An office
    // holder chosen as ADVISER is written `exOfficio: false,
    // position: 'adviser'`, so `mayCreateNomination` checks their
    // `nominableAsAdviser` like anyone else's — offering them here would
    // hand the student a name the rules then refuse, which is D29's
    // "cannot disagree forwards" broken. D31's own motivating case: a
    // college coordinator who holds no advisees, narrowed by unticking
    // Adviser.
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('facultyDirectory').doc('coord').update({
      'nominableAsAdviser': false,
      'nominableAsPanelist': false,
    });
    await db.collection('facultyDirectory').doc('dean').update({
      'nominableAsAdviser': false,
      'nominableAsPanelist': false,
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final adviser = await openDropdownValues(tester, const Key('adviser'));
    expect(adviser, isNot(contains('coord')),
        reason: 'the adviser slot is not the ex-officio seat, so the '
            'nomination rule checks nominableAsAdviser and refuses');
    expect(adviser, isNot(contains('dean')));

    // Absent from the panel slot too, same as always — but that exclusion
    // is the pre-existing ex-officio-seat rule, not the designation
    // filter, which the next test proves by leaving designation alone.
    final panel = await openDropdownValues(tester, const Key('panel0'));
    expect(panel, isNot(contains('coord')));
    expect(panel, isNot(contains('dean')));
  });

  testWidgets(
      'an office holder still designated as an adviser is offered on the '
      'adviser slot', (tester) async {
    // The control for the test above: office holders are not excluded from
    // the adviser slot as a class — a Research Coordinator or Dean who
    // genuinely advises still appears. Without this, hiding every office
    // holder from the adviser picker would pass the test above too.
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('facultyDirectory').doc('coord').update({
      'nominableAsAdviser': true,
      'nominableAsPanelist': false,
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final adviser = await openDropdownValues(tester, const Key('adviser'));
    expect(adviser, contains('coord'));

    // And the panel slot still excludes them by office, regardless of the
    // panelist designation just written — D32's seat exemption intact.
    final panel = await openDropdownValues(tester, const Key('panel0'));
    expect(panel, isNot(contains('coord')));
  });

  testWidgets(
      'the refusal message names an office holder picked as adviser',
      (tester) async {
    // The other half of the same defect: when an office holder IS the
    // cause of the refusal, excluding them from the candidate list named
    // the three innocent panelists and told the student to replace the
    // wrong people. The adviser is always a candidate.
    useTallSurface(tester);
    final db = await seeded();

    await tester.pumpWidget(wrap(db, extraOverrides: [
      thesisRepositoryProvider
          .overrideWithValue(PermissionDeniedThesisRepository(db)),
    ]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adviser')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dr. Bito-onon — coordinator · CICT').last);
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

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('submitNomination')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('Dr. Bito-onon'),
        reason: 'the office holder in the adviser slot is exactly the '
            'nominee the rules check, so they must be named');
    expect(error.data, contains('adviser'));
  });

  testWidgets(
      'a permission-denied on submit names the person and the position, '
      'not a bare Firestore code', (tester) async {
    // Reproduces spec §4.2.1's sync window: the picker offers a nominee
    // because their directory entry carries no designation key (absence
    // reads as nominable), but `users/{uid}` — which the student cannot
    // read — says otherwise, and `firestore.rules` refuses the write. A
    // student who picked a name off a list this screen showed them must
    // not be handed a bare permission code and left to guess.
    useTallSurface(tester);
    final db = await seeded();

    await tester.pumpWidget(wrap(db, extraOverrides: [
      thesisRepositoryProvider
          .overrideWithValue(PermissionDeniedThesisRepository(db)),
    ]));
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

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('submitNomination')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // The point of this test: assert on the actual sentence, not merely
    // that some error appeared. A batched write does not report which
    // document a security rule refused, and a full submission always
    // carries an adviser plus at least three real panelists (the panel
    // picker never offers an ex-officio office holder in the first
    // place), so every one of those four is a named candidate here —
    // naming all of them, in plain language, is what the screen can
    // honestly say without guessing at a single culprit it cannot know.
    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, isNot(contains('permission-denied')),
        reason: 'the raw Firestore code must not leak into the sentence '
            'meant for a student');
    for (final name in ['Dr. Armada', 'Dr. Diamante', 'Dr. Padojinog',
        'Dr. Braganza']) {
      expect(error.data, contains(name));
    }
    expect(error.data, contains('adviser'));
    expect(error.data, contains('panelist'));
    expect(error.data, contains('this semester'));

    // And the Firestore code must still be visible underneath — it helps
    // whoever debugs this next, same as `ErrorState`.
    expect(find.byKey(const Key('errorCode')), findsOneWidget);
    final code = tester.widget<Text>(find.byKey(const Key('errorCode')));
    expect(code.data, '[permission-denied]');

    // And the submission must not have gone through.
    final noms = await db.collection('theses/t1/nominations').get();
    expect(noms.docs, isEmpty);
  });
}
