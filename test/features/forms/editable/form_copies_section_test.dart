import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';
import 'package:ethesishub/features/forms/editable/form_copies_section.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// A repository whose `create` does not resolve until [gate] completes, so
/// a test can observe the state while a create is still in flight -- which
/// [FakeFirebaseFirestore]'s own `set()` resolves too quickly to catch.
class _SlowCreateRepo extends FormCopyRepository {
  _SlowCreateRepo(super.db, this.gate);

  final Completer<void> gate;

  @override
  Future<String> create({
    required String uid,
    required String formId,
    required String name,
  }) async {
    await gate.future;
    return super.create(uid: uid, formId: formId, name: name);
  }
}

Future<FakeFirebaseFirestore> seeded() async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('u1').set({
    'fullName': 'Test User',
    'email': 't@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  return db;
}

Future<void> seedCopy(FakeFirebaseFirestore db, String uid, String id,
    String formId, String name, DateTime updated) {
  final at = Timestamp.fromDate(updated);
  return db.doc('users/$uid/formCopies/$id').set({
    'formId': formId,
    'name': name,
    'overrides': <String, String>{},
    'folderId': null,
    'createdAt': at,
    'updatedAt': at,
  });
}

Future<GoRouter> pumpSection(
    WidgetTester tester, FakeFirebaseFirestore db,
    {List<Override> extraOverrides = const []}) async {
  final router = GoRouter(
    initialLocation: '/forms',
    routes: [
      GoRoute(
        path: '/forms',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(
            child: FormCopiesSection(
                formId: 'form1', defaultName: 'Form 1 copy'),
          ),
        ),
      ),
      GoRoute(
        path: '/forms/:formId/copies/:copyId',
        builder: (_, s) => Scaffold(
          body: Text('editor ${s.pathParameters['copyId']}',
              key: const Key('editorStub')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'u1', email: 't@isufst.edu.ph', isEmailVerified: true),
      )),
      ...extraOverrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('New copy asks for a name, creates the copy and opens it',
      (tester) async {
    final db = await seeded();
    final router = await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('copyNameField')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('copyNameField')), 'Group 3 – Santos');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    final copies = await db.collection('users/u1/formCopies').get();
    expect(copies.docs, hasLength(1));
    final copy = copies.docs.single;
    expect(copy.data()['name'], 'Group 3 – Santos');
    expect(copy.data()['formId'], 'form1');
    // go_router 17.5.0's `currentConfiguration.uri` deliberately excludes
    // ImperativeRouteMatch entries (pushed routes) — see RouteMatchList.uri's
    // doc comment in package:go_router/src/match.dart. A `context.push` is
    // therefore checked on the match list itself, not `.uri.path`.
    expect(
        router.routerDelegate.currentConfiguration.matches.last
            .matchedLocation,
        '/forms/form1/copies/${copy.id}');
    expect(find.byKey(const Key('editorStub')), findsOneWidget);
    expect(find.text('editor ${copy.id}'), findsOneWidget);
  });

  testWidgets('cancelling New copy creates nothing', (tester) async {
    final db = await seeded();
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect((await db.collection('users/u1/formCopies').get()).docs, isEmpty);
  });

  testWidgets('an empty name cannot be confirmed', (tester) async {
    await pumpSection(tester, await seeded());
    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('copyNameField')), '   ');
    await tester.pump();
    final confirm = tester.widget<FilledButton>(
        find.byKey(const Key('copyNameConfirm')));
    expect(confirm.onPressed, isNull);
  });

  testWidgets('My copies lists only this person\'s copies of this form',
      (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await seedCopy(db, 'u1', 'b', 'form1', 'Group 5', DateTime(2026, 9, 2));
    await seedCopy(db, 'u1', 'c', 'form3', 'A Form 3', DateTime(2026, 9, 3));
    await seedCopy(db, 'u2', 'd', 'form1', 'Not mine', DateTime(2026, 9, 4));
    await pumpSection(tester, db);

    expect(find.text('My copies (2)'), findsOneWidget);
    expect(find.text('Group 3'), findsOneWidget);
    expect(find.text('Group 5'), findsOneWidget);
    expect(find.text('A Form 3'), findsNothing);
    expect(find.text('Not mine'), findsNothing);
  });

  testWidgets('with no copies there is no My copies list', (tester) async {
    await pumpSection(tester, await seeded());
    expect(find.byKey(const Key('form1MyCopies')), findsNothing);
    expect(find.byKey(const Key('form1NewCopy')), findsOneWidget);
  });

  testWidgets('Open goes to the editor for that copy', (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('openCopy-a')));
    await tester.pumpAndSettle();
    expect(find.text('editor a'), findsOneWidget);
  });

  testWidgets('Rename changes the name', (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('renameCopy-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('copyNameField')), 'Renamed');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    expect((await db.doc('users/u1/formCopies/a').get()).data()!['name'],
        'Renamed');
    expect(find.text('Renamed'), findsOneWidget);
  });

  testWidgets(
      'New copy is disabled while a create is pending, so it cannot make '
      'duplicates', (tester) async {
    final db = await seeded();
    final gate = Completer<void>();
    await pumpSection(tester, db, extraOverrides: [
      formCopyRepositoryProvider
          .overrideWithValue(_SlowCreateRepo(db, gate)),
    ]);

    await tester.tap(find.byKey(const Key('form1NewCopy')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('copyNameField')), 'Group 3 – Santos');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('form1NewCopy')));
    expect(button.onPressed, isNull,
        reason: 'a second tap here must not start a second create');

    gate.complete();
    await settleReal(tester);
    expect((await db.collection('users/u1/formCopies').get()).docs,
        hasLength(1));
  });

  testWidgets('a stream error under New copy shows a short inline message',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/forms',
      routes: [
        GoRoute(
          path: '/forms',
          builder: (_, _) => const Scaffold(
            body: FormCopiesSection(
                formId: 'form1', defaultName: 'Form 1 copy'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myFormCopiesProvider('form1').overrideWith(
            (ref) => Stream<List<FormCopy>>.error('permission-denied')),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form1CopiesError')), findsOneWidget);
    expect(find.text('Could not load your copies.'), findsOneWidget);
  });

  testWidgets('Delete asks first, then deletes', (tester) async {
    final db = await seeded();
    await seedCopy(db, 'u1', 'a', 'form1', 'Group 3', DateTime(2026, 9, 1));
    await pumpSection(tester, db);

    await tester.tap(find.byKey(const Key('deleteCopy-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmDeleteCopy')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteCopy')));
    await settleReal(tester);

    expect((await db.doc('users/u1/formCopies/a').get()).exists, isFalse);
    expect(find.text('Group 3'), findsNothing);
  });
}
