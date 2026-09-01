import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/repository/archive_entry_screen.dart';
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
  return db;
}

Widget app(FakeFirebaseFirestore db, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 's1')),
      ),
      ...overrides,
    ],
    child: const MaterialApp(
      home: Scaffold(body: ArchiveEntryScreen(thesisId: 't1')),
    ),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows the title, authors, abstract and panel', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    expect(find.text('A Study of Coastal Fisheries in Barotac Nuevo'),
        findsOneWidget);
    expect(find.textContaining('Santos, J.'), findsOneWidget);
    expect(find.textContaining('Fish were counted.'), findsOneWidget);
    expect(find.textContaining('Dr. Zamora'), findsOneWidget);
    expect(find.textContaining('Dr. Reyes'), findsOneWidget);
  });

  testWidgets('offers the manuscript', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('openManuscript')), findsOneWidget);
  });

  testWidgets('an entry that is not there says so, and is not an error',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('entryNotFound')), findsOneWidget);
  });

  testWidgets('shows a loading state before the entry resolves',
      (tester) async {
    await tester.pumpWidget(app(await seed()));
    await tester.pump();

    expect(find.byKey(const Key('entryLoading')), findsOneWidget);
  });

  testWidgets('a failed read is a distinct state from not-found',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(
      await seed(),
      overrides: [
        archiveEntryProvider('t1').overrideWith((ref) => Stream.error(
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
    expect(find.byKey(const Key('entryNotFound')), findsNothing);
  });

  testWidgets('an entry with no manuscript on file says so',
      (tester) async {
    useTallSurface(tester);
    final db = await seed();
    await db.collection('archive').doc('t1').update({'manuscriptUrl': ''});
    await tester.pumpWidget(app(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptMissing')), findsOneWidget);
    expect(find.byKey(const Key('openManuscript')), findsNothing);
  });
}
