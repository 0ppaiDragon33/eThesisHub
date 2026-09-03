import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
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

/// Seeds `users/{uid}` with [role] and AWAITS that write before returning
/// the widget — matching `defences_list_test.dart`'s idiom rather than
/// firing it unawaited. Without a profile document, `currentUserProvider`
/// silently takes the no-profile branch instead of the role it was meant to
/// exercise (D64's cautionary tale).
Future<Widget> app(
  FakeFirebaseFirestore db,
  String uid, {
  required String role,
  List<Override> overrides = const [],
}) async {
  await db
      .collection('users')
      .doc(uid)
      .set({'role': role, 'active': true});

  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
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
    await tester
        .pumpWidget(await app(await seed(), 's1', role: 'student'));
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
    await tester
        .pumpWidget(await app(await seed(), 's1', role: 'student'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('openManuscript')), findsOneWidget);
  });

  testWidgets('an entry that is not there says so, and is not an error',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
        await app(FakeFirebaseFirestore(), 's1', role: 'student'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('entryNotFound')), findsOneWidget);
  });

  testWidgets('shows a loading state before the entry resolves',
      (tester) async {
    await tester
        .pumpWidget(await app(await seed(), 's1', role: 'student'));
    await tester.pump();

    expect(find.byKey(const Key('entryLoading')), findsOneWidget);
  });

  testWidgets('a failed read is a distinct state from not-found',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(await app(
      await seed(),
      's1',
      role: 'student',
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
    await tester.pumpWidget(await app(db, 's1', role: 'student'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptMissing')), findsOneWidget);
    expect(find.byKey(const Key('openManuscript')), findsNothing);
  });

  // D64: the coordinator issues it, per §10b and the role table, and the
  // entry is the record it certifies.
  testWidgets('a coordinator is offered Form 8', (tester) async {
    useTallSurface(tester);
    await tester
        .pumpWidget(await app(await seed(), 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('downloadForm8')), findsOneWidget);
  });

  testWidgets('nobody else is offered it', (tester) async {
    useTallSurface(tester);
    for (final entry in {'l1': 'student', 'a1': 'faculty'}.entries) {
      await tester.pumpWidget(
          await app(await seed(), entry.key, role: entry.value));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('downloadForm8')), findsNothing,
          reason: entry.value);
      expect(find.byKey(const Key('form8RoleUnavailable')), findsNothing,
          reason: entry.value);
    }
  });

  // §6: "A certificate with a blank name is worse than no certificate,
  // because it looks official." The structural gate (you cannot reach this
  // button unless the thesis is archived) does not cover an ARCHIVED entry
  // with no members -- `ArchiveEntry.fromMap` defaults `memberNames` to
  // empty, which is why this screen renders 'Unknown authors' at all.
  testWidgets('Form 8 refuses for an entry with no members, and says why',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await _put(db, 't1',
        title: 'A Study of Coastal Fisheries', members: const []);

    await tester.pumpWidget(await app(db, 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();

    // The reader sees the entry itself, unknown-authored, and the button.
    expect(find.text('Unknown authors'), findsOneWidget);
    await tester.tap(find.byKey(const Key('downloadForm8')));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('this archive entry records no student names'),
      findsOneWidget,
    );
    expect(find.textContaining('cannot be issued'), findsOneWidget);
  });

  testWidgets('an entry with no title is refused too, naming that field',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await _put(db, 't1', title: '');

    await tester.pumpWidget(await app(db, 'c1', role: 'coordinator'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('downloadForm8')));
    await tester.pump();

    expect(find.textContaining('no thesis title'), findsOneWidget);
  });

  // The role gate has three states, not two. A failed profile read must not
  // be rendered as "you are not a coordinator" -- that is a transient fault
  // dressed up as an authorization answer.
  testWidgets('a failed profile read is not silence, and is not a refusal',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(await app(
      await seed(),
      'c1',
      role: 'coordinator',
      overrides: [
        currentUserProvider.overrideWith((ref) => Stream.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form8RoleUnavailable')), findsOneWidget);
    expect(find.byKey(const Key('downloadForm8')), findsNothing);
    // The entry itself still renders: a profile failure is not an entry
    // failure.
    expect(find.text('A Study of Coastal Fisheries in Barotac Nuevo'),
        findsOneWidget);
  });

  testWidgets('a profile still loading is distinct from both', (tester) async {
    useTallSurface(tester);
    final controller = StreamController<AppUser?>();
    addTearDown(controller.close);

    await tester.pumpWidget(await app(
      await seed(),
      'c1',
      role: 'coordinator',
      overrides: [
        currentUserProvider.overrideWith((ref) => controller.stream),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form8RoleLoading')), findsOneWidget);
    expect(find.byKey(const Key('form8RoleUnavailable')), findsNothing);
    expect(find.byKey(const Key('downloadForm8')), findsNothing);
  });
}
