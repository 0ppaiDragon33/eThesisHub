import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/features/titles/submit_titles_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// Records every path it is asked to store, so a test can assert nothing
/// was uploaded (the refusal case) or count what landed (the success case)
/// without touching Supabase.
class _FakeStorage implements StorageService {
  final uploads = <String>[];

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    uploads.add(path);
    return StoredFile(path: path, url: 'https://example.test/$path');
  }

  @override
  Future<void> delete(String path) async {}
}

PickedDocument _validDoc([String name = 'doc.pdf']) => PickedDocument(
      name: name,
      bytes: Uint8List(10),
      extension: 'pdf',
      contentType: 'application/octet-stream',
    );

Future<FakeFirebaseFirestore> seeded({
  String status = 'nominationApproved',
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': <String>[],
    'adviserUid': 'a1', 'memberNames': <String>[], 'workingTitle': 'T',
    'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
    'academicYear': '2026-2027', 'titleRound': 0,
  });
  return db;
}

Widget wrap(
  FakeFirebaseFirestore db, {
  DocumentPicker? pickDocument,
  StorageService? storage,
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1', email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
        if (storage != null) storageServiceProvider.overrideWithValue(storage),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/thesis/titles',
          routes: [
            GoRoute(
              path: '/thesis/titles',
              builder: (_, _) => SubmitTitlesScreen(
                thesisId: 't1',
                pickDocument: pickDocument,
              ),
            ),
            GoRoute(
              path: '/thesis',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('status', key: Key('landedOnStatus'))),
              ),
            ),
          ],
        ),
      ),
    );

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opens with three candidate slots', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('titleText0')), findsOneWidget);
    expect(find.byKey(const Key('titleText1')), findsOneWidget);
    expect(find.byKey(const Key('titleText2')), findsOneWidget);
  });

  testWidgets('refuses to submit with a blank title', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    // Full-string match: 'title' alone also appears in the next
    // validation's message ('Attach a justification for every candidate
    // title.'), so a substring check on 'title' would still pass with the
    // blank-title check deleted entirely.
    expect(error.data, 'Give every candidate a title.');
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
  });

  testWidgets('refuses to submit without a justification for every title',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byKey(Key('titleText$i')), 'Candidate $i');
    }
    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('justification'));
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
  });

  testWidgets('caps the candidates and says why', (tester) async {
    // Ten is a rules constraint, not a preference: each candidate costs a
    // get() and M1a measured that a batch of 20 is denied.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    for (var i = 3; i < 10; i++) {
      await tester.tap(find.byKey(const Key('addCandidate')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('titleText9')), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byKey(const Key('addCandidate')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('candidateCapReason')), findsOneWidget);
  });

  testWidgets('refuses when the thesis is not ready for a submission',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded(status: 'draft')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notReady')), findsOneWidget);
    expect(find.byKey(const Key('submitTitles')), findsNothing);
  });

  testWidgets(
      'submits, uploads every document, and navigates to the thesis status '
      'screen', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    final storage = _FakeStorage();

    await tester.pumpWidget(wrap(
      db,
      storage: storage,
      pickDocument: ({required allowed}) async => _validDoc(),
    ));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byKey(Key('titleText$i')), 'Candidate $i');
      await tester.tap(find.byKey(Key('pickJustification$i')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('pickPresentation')));
    await tester.pumpAndSettle();

    // As in nominate_screen_test.dart: FakeFirebaseFirestore's batch commit
    // is not driven by pumpAndSettle's fake clock, so runAsync gives the
    // real event loop a turn to let it land.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('submitTitles')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsNothing);

    // The point of this test: a successful submission must navigate away,
    // not leave the leader on this screen where its own thesis stream would
    // eventually re-render "not ready" over a submission that just
    // succeeded — the defect this project has shipped twice already.
    expect(find.byKey(const Key('landedOnStatus')), findsOneWidget);
    expect(find.byKey(const Key('submitTitlesScreen')), findsNothing);

    final candidates =
        await db.collection('theses/t1/candidateTitles').get();
    expect(candidates.docs.length, 3);

    final thesis = await db.collection('theses').doc('t1').get();
    expect(thesis.data()!['status'], 'titlePendingDefence');

    // 3 justifications + 1 presentation.
    expect(storage.uploads.length, 4);
  });

  testWidgets('a cancelled pick changes nothing', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    final storage = _FakeStorage();

    await tester.pumpWidget(wrap(
      db,
      storage: storage,
      pickDocument: ({required allowed}) async => null,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pickJustification0')));
    await tester.pumpAndSettle();

    final button =
        tester.widget<TextButton>(find.byKey(const Key('pickJustification0')));
    expect((button.child! as Text).data, 'Attach justification');
    expect(find.byKey(const Key('error')), findsNothing);
    expect(storage.uploads, isEmpty);
  });

  testWidgets('an oversized file is refused before it is ever uploaded',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    final storage = _FakeStorage();
    final tooBig = PickedDocument(
      name: 'huge.pdf',
      bytes: Uint8List(kJustificationMaxBytes + 1),
      extension: 'pdf',
      contentType: 'application/octet-stream',
    );

    await tester.pumpWidget(wrap(
      db,
      storage: storage,
      pickDocument: ({required allowed}) async => tooBig,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pickJustification0')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('MB'));
    final button =
        tester.widget<TextButton>(find.byKey(const Key('pickJustification0')));
    expect((button.child! as Text).data, 'Attach justification');
    expect(storage.uploads, isEmpty,
        reason: 'validation must run before any upload is attempted');
  });

  testWidgets('a storage outage says so, instead of "please try again"',
      (tester) async {
    // This happened for real: the Supabase project's hostname stopped
    // resolving, the browser threw an XMLHttpRequest error, and the generic
    // handler told the student to retry — for a condition retrying could
    // never fix. The failure now names storage and carries its code, since
    // there are no server-side logs for anyone to consult instead.
    useTallSurface(tester);
    final db = await seeded();

    await tester.pumpWidget(wrap(
      db,
      storage: _UnreachableStorage(),
      pickDocument: ({required allowed}) async => _validDoc(),
    ));
    await tester.pumpAndSettle();

    for (var i = 0; i < 3; i++) {
      await tester.enterText(find.byKey(Key('titleText$i')), 'Candidate $i');
      await tester.tap(find.byKey(Key('pickJustification$i')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('pickPresentation')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submitTitles')));
    await tester.pumpAndSettle();

    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('Could not reach file storage'));
    expect(error.data, contains('storage-unreachable'),
        reason: 'the code is the only diagnostic that reaches anyone');
    expect(error.data, isNot(contains('try again')),
        reason: 'retrying cannot fix an unreachable host, and saying so '
            'sends the student chasing their own connection');

    // Uploads precede the batch, so a storage failure must leave Firestore
    // untouched rather than half-written.
    expect((await db.collection('theses/t1/candidateTitles').get()).docs,
        isEmpty);
    final thesis = (await db.collection('theses').doc('t1').get()).data()!;
    expect(thesis['status'], 'nominationApproved',
        reason: 'the thesis must not move into the defence');
  });
}

/// Fails the way a paused or deleted Supabase project does.
class _UnreachableStorage implements StorageService {
  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    throw classifyStorageError(
        Exception('ClientException: XMLHttpRequest error.'));
  }

  @override
  Future<void> delete(String path) async {}
}
