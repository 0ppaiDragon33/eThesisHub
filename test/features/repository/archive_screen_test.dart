import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/repository/archive_screen.dart';
import 'package:ethesishub/providers/archive_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<void> _put(
  FakeFirebaseFirestore db,
  String id, {
  required String title,
  List<String> members = const ['Santos, J.'],
  String college = 'CICT',
  String program = 'BSIT',
  String year = '2026-2027',
  DateTime? archivedAt,
}) {
  return db.collection('archive').doc(id).set({
    'title': title,
    'memberNames': members,
    'abstract': 'Fish were counted.',
    'college': college,
    'program': program,
    'academicYear': year,
    'adviserName': 'Dr. Zamora',
    'panelNames': <String>['Dr. Reyes'],
    'manuscriptUrl': 'https://example.test/$id.pdf',
    'manuscriptPath': 'p/$id.pdf',
    'finalDefenceId': 'd9',
    'uploadedBy': 'l1',
    'archivedBy': 'c1',
    'archivedAt':
        Timestamp.fromDate(archivedAt ?? DateTime(2026, 9, 30)),
  });
}

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await _put(db, 't1',
      title: 'A Study of Coastal Fisheries in Barotac Nuevo');
  await _put(db, 't2',
      title: 'Machine Learning for Rice Yield',
      members: const ['Bautista, M.'],
      program: 'BSCS');
  await _put(db, 't3',
      title: 'Water Quality in Iloilo',
      members: const ['Lim, K.'],
      college: 'COED',
      year: '2025-2026');
  return db;
}

/// [overrides] lets a test replace one of the screen's providers -- the
/// failed-read test drives [archiveProvider] into an error state, which
/// cannot be produced through `fake_cloud_firestore` at all: it enforces
/// no rules, so nothing there can be denied.
Widget app(FakeFirebaseFirestore db, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 's1')),
      ),
      ...overrides,
    ],
    child: const MaterialApp(home: Scaffold(body: ArchiveScreen())),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('lists every published thesis', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveCard-t1')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t2')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t3')), findsOneWidget);
  });

  // THE test for D54. Firestore matches prefixes only; this is the whole
  // reason search runs on the client.
  testWidgets('search matches mid-title, not just the first word',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('archiveSearch')), 'fisheries');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveCard-t1')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t2')), findsNothing);
  });

  testWidgets('search covers author names', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('archiveSearch')), 'Bautista');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveCard-t2')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t1')), findsNothing);
  });

  testWidgets('a college filter narrows the list', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-college-COED')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveCard-t3')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t1')), findsNothing);
  });

  // Strengthened over the brief's version: that one picked college CICT and
  // searched "Rice", but t1 and t3 both fail matches('Rice') on their own,
  // so the assertions passed identically whether or not the college
  // predicate was even in the .where() chain -- only the
  // ignore-the-search direction was actually caught. Here the search term
  // ("Coral") matches entries in TWO colleges, so dropping either
  // predicate wrongly admits a different decoy: dropping the college
  // filter admits a2 (COED); dropping the search admits a3 (CICT, but no
  // "Coral" in its title). Confirmed both failure modes by commenting out
  // each predicate in turn -- see the fix report.
  testWidgets('a filter and a search combine', (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await _put(db, 'a1', title: 'Coral Reef Study', members: const ['Cruz, A.']);
    await _put(db, 'a2',
        title: 'Coral Bleaching Patterns',
        members: const ['Domingo, B.'],
        college: 'COED');
    await _put(db, 'a3',
        title: 'Rice Farming Methods', members: const ['Enriquez, C.']);
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-college-CICT')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('archiveSearch')), 'Coral');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveCard-a1')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-a2')), findsNothing);
    expect(find.byKey(const Key('archiveCard-a3')), findsNothing);
  });

  // D-something-new: retracting the last entry in a filtered-on college
  // must not strand the reader behind a vanished chip. Reachable in the
  // real app: ArchiveRepository.retract deletes the doc, archiveProvider
  // is a live stream, and a student can have COED selected when the
  // Coordinator retracts Iloilo's only COED thesis.
  testWidgets(
      'a filter whose entries all disappear from the live stream clears '
      'itself, rather than stranding the reader', (tester) async {
    useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-college-COED')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('archiveCard-t3')), findsOneWidget);

    // t3 is the only COED entry -- retract it, as the Coordinator would.
    await db.collection('archive').doc('t3').delete();
    await tester.pumpAndSettle();

    // The vanished chip must not leave the reader stuck on `noMatches`
    // with no way back: the stale selection self-prunes, so the
    // remaining entries (t1, t2) are visible again.
    expect(find.byKey(const Key('filter-college-COED')), findsNothing);
    expect(find.byKey(const Key('noMatches')), findsNothing);
    expect(find.byKey(const Key('archiveCard-t1')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t2')), findsOneWidget);
  });

  testWidgets('a search matching nothing says so, and is not an error',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('archiveSearch')), 'zzzznothing');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('noMatches')), findsOneWidget);
  });

  // An empty archive and a failed read must never look the same.
  testWidgets('an empty archive says so', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('emptyArchive')), findsOneWidget);
    expect(find.byKey(const Key('noMatches')), findsNothing);
  });

  // The other half of "an empty archive and a failed read must never look
  // the same" (spec section 6). The empty case above is what a student
  // sees constantly in the early days; this is what they must see instead
  // when the truth is a denial, and the two must not be confusable.
  testWidgets('a failed read surfaces, and is not an empty archive',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(
      await seed(),
      overrides: [
        archiveProvider.overrideWith((ref) => Stream.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('errorCode')), findsOneWidget);
    expect(find.text('[permission-denied]'), findsOneWidget);
    expect(find.byKey(const Key('emptyArchive')), findsNothing);
    expect(find.byKey(const Key('noMatches')), findsNothing);
    expect(find.byKey(const Key('archiveCard-t1')), findsNothing);
  });

  // pump() once, NOT pumpAndSettle -- settling resolves the stream first
  // and the assertion becomes vacuous.
  testWidgets('shows a loading state before the archive resolves',
      (tester) async {
    await tester.pumpWidget(app(await seed()));
    await tester.pump();

    expect(find.byKey(const Key('archiveLoading')), findsOneWidget);
  });
}
