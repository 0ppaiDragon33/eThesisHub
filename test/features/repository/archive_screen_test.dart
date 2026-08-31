import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/repository/archive_screen.dart';
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

Widget app(FakeFirebaseFirestore db) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 's1')),
      ),
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

  testWidgets('a filter and a search combine', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('filter-college-CICT')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('archiveSearch')), 'Rice');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('archiveCard-t2')), findsOneWidget);
    expect(find.byKey(const Key('archiveCard-t1')), findsNothing);
    expect(find.byKey(const Key('archiveCard-t3')), findsNothing);
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

  // pump() once, NOT pumpAndSettle -- settling resolves the stream first
  // and the assertion becomes vacuous.
  testWidgets('shows a loading state before the archive resolves',
      (tester) async {
    await tester.pumpWidget(app(await seed()));
    await tester.pump();

    expect(find.byKey(const Key('archiveLoading')), findsOneWidget);
  });
}
