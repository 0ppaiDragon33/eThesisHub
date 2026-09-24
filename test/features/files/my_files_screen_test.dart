import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/files/my_files_screen.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

class FakeStorage implements StorageService {
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
  @override
  Future<String> signedUrl(String path) async => 'https://example.test/$path';
}

class FakeRemover implements PersonalFileRemover {
  final deleted = <String>[];
  @override
  Future<void> deletePersonal(String path) async => deleted.add(path);
}

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

class Harness {
  final db = FakeFirebaseFirestore();
  final storage = FakeStorage();
  final remover = FakeRemover();
  PickedDocument? nextPick;
  late GoRouter router;

  Timestamp at(int day) => Timestamp.fromDate(DateTime(2026, 9, day));

  Future<void> seedUser() => db.collection('users').doc('u1').set({
        'fullName': 'Test User', 'email': 't@isufst.edu.ph',
        'role': 'student', 'active': true,
      });

  Future<void> folder(String id, String name) =>
      db.doc('users/u1/folders/$id').set({'name': name, 'createdAt': at(1)});

  Future<void> copy(String id, String name, {String? folderId, int day = 1}) =>
      db.doc('users/u1/formCopies/$id').set({
        'formId': 'form1', 'name': name, 'overrides': <String, String>{},
        'folderId': folderId, 'createdAt': at(day), 'updatedAt': at(day),
      });

  Future<void> file(String id, String name, {String? folderId, int day = 1}) =>
      db.doc('users/u1/files/$id').set({
        'name': name, 'storagePath': 'personal/u1/$id/x.pdf',
        'contentType': 'application/pdf', 'sizeBytes': 2048,
        'folderId': folderId, 'createdAt': at(day),
      });

  Future<void> pump(WidgetTester tester, {String location = '/files'}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<PickedDocument?> picker({required Set<String> allowed}) async =>
        nextPick;

    router = GoRouter(initialLocation: location, routes: [
      GoRoute(
        path: '/files',
        builder: (_, s) => Scaffold(
          body: MyFilesScreen(
            folderId: s.uri.queryParameters['folder'],
            pickDocument: picker,
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
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'u1', email: 't@isufst.edu.ph', isEmailVerified: true),
        )),
        storageServiceProvider.overrideWithValue(storage),
        personalFileRemoverProvider.overrideWithValue(remover),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }
}

/// Fake Firestore writes finish on the real event loop.
Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pumpAndSettle();
}

Future<void> chooseFromMenu(WidgetTester tester, String id, String label) async {
  await tester.tap(find.byKey(Key('itemMenu-$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.seedUser();
  });

  testWidgets('an empty My files says what to do', (tester) async {
    await h.pump(tester);
    expect(find.byKey(const Key('myFilesEmpty')), findsOneWidget);
  });

  testWidgets('the top level lists folders, then loose copies and files',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.copy('c-top', 'Loose copy');
    await h.file('f-top', 'Loose.pdf');
    await h.file('f-in', 'Inside.pdf', folderId: 'fo1');
    await h.copy('c-orphan', 'Orphan copy', folderId: 'gone');
    await h.pump(tester);

    expect(find.byKey(const Key('folder-fo1')), findsOneWidget);
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-c-top')), findsOneWidget);
    expect(find.byKey(const Key('item-f-top')), findsOneWidget);
    expect(find.byKey(const Key('item-f-in')), findsNothing,
        reason: 'inside a folder, not at the top');
    expect(find.byKey(const Key('item-c-orphan')), findsOneWidget,
        reason: 'a missing folder never hides an item');
  });

  testWidgets('New folder makes a folder', (tester) async {
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('newFolder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('copyNameField')), 'Group 5');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    final folders = await h.db.collection('users/u1/folders').get();
    expect(folders.docs.single.data()['name'], 'Group 5');
    expect(find.text('Group 5'), findsOneWidget);
  });

  testWidgets('opening a folder shows only its items, and All files returns',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.file('f-in', 'Inside.pdf', folderId: 'fo1');
    await h.file('f-top', 'Loose.pdf');
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('folder-fo1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-f-in')), findsOneWidget);
    expect(find.byKey(const Key('item-f-top')), findsNothing);
    expect(find.byKey(const Key('newFolder')), findsNothing,
        reason: 'folders are one level deep');

    await tester.tap(find.byKey(const Key('backToAllFiles')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-f-top')), findsOneWidget);
  });

  testWidgets('uploading inside a folder stores the file in that folder',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.pump(tester, location: '/files?folder=fo1');
    h.nextPick = PickedDocument(
      name: 'Scan.png', bytes: Uint8List.fromList(png), extension: 'png',
      contentType: 'image/png',
    );

    await tester.tap(find.byKey(const Key('uploadFile')));
    await settleReal(tester);

    expect(h.storage.uploads.single, startsWith('personal/u1/'));
    final files = await h.db.collection('users/u1/files').get();
    expect(files.docs.single.data()['folderId'], 'fo1');
    expect(files.docs.single.data()['name'], 'Scan.png');
    expect(find.text('Added Scan.png.'), findsOneWidget);
  });

  testWidgets('a file My files will not take is refused with a reason',
      (tester) async {
    await h.pump(tester);
    h.nextPick = PickedDocument(
      name: 'run.exe', bytes: Uint8List.fromList([0x4D, 0x5A]),
      extension: 'exe', contentType: 'application/octet-stream',
    );

    await tester.tap(find.byKey(const Key('uploadFile')));
    await settleReal(tester);

    expect(h.storage.uploads, isEmpty);
    expect(find.textContaining('Choose a'), findsOneWidget);
  });

  testWidgets('Move to puts a file in a folder and a copy back at the top',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.file('f1', 'Notes.pdf');
    await h.copy('c1', 'A copy', folderId: 'fo1');
    await h.pump(tester);

    await chooseFromMenu(tester, 'f1', 'Move to…');
    await tester.tap(find.byKey(const Key('moveTo-fo1')));
    await settleReal(tester);
    expect((await h.db.doc('users/u1/files/f1').get())['folderId'], 'fo1');

    await tester.tap(find.byKey(const Key('folder-fo1')));
    await tester.pumpAndSettle();
    await chooseFromMenu(tester, 'c1', 'Move to…');
    await tester.tap(find.byKey(const Key('moveTo-top')));
    await settleReal(tester);
    expect((await h.db.doc('users/u1/formCopies/c1').get())['folderId'],
        isNull);
  });

  testWidgets('Rename changes a file\'s name', (tester) async {
    await h.file('f1', 'Notes.pdf');
    await h.pump(tester);

    await chooseFromMenu(tester, 'f1', 'Rename');
    await tester.enterText(
        find.byKey(const Key('copyNameField')), 'Chapter notes.pdf');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copyNameConfirm')));
    await settleReal(tester);

    expect((await h.db.doc('users/u1/files/f1').get())['name'],
        'Chapter notes.pdf');
  });

  testWidgets('deleting a file asks, then removes the object and the record',
      (tester) async {
    await h.file('f1', 'Notes.pdf');
    await h.pump(tester);

    await chooseFromMenu(tester, 'f1', 'Delete');
    expect(find.byKey(const Key('confirmDeleteItem')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteItem')));
    await settleReal(tester);

    expect(h.remover.deleted, ['personal/u1/f1/x.pdf']);
    expect((await h.db.doc('users/u1/files/f1').get()).exists, isFalse);
  });

  testWidgets('deleting a folder asks, then moves its items to the top',
      (tester) async {
    await h.folder('fo1', 'Group 3');
    await h.file('f-in', 'Inside.pdf', folderId: 'fo1');
    await h.copy('c-in', 'In copy', folderId: 'fo1');
    await h.pump(tester);

    await tester.tap(find.byKey(const Key('folder-fo1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteFolder')));
    await tester.pumpAndSettle();
    expect(find.textContaining('The 2 items in it move to the top level'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteFolder')));
    await settleReal(tester);

    expect((await h.db.doc('users/u1/folders/fo1').get()).exists, isFalse);
    expect((await h.db.doc('users/u1/files/f-in').get())['folderId'], isNull);
    expect(find.byKey(const Key('item-f-in')), findsOneWidget,
        reason: 'back at the top level, still there');
  });

  testWidgets('opening a form copy goes to its editor', (tester) async {
    await h.copy('c1', 'A copy');
    await h.pump(tester);
    await tester.tap(find.byKey(const Key('item-c1')));
    await tester.pumpAndSettle();
    expect(find.text('editor c1'), findsOneWidget);
  });

  testWidgets('a folder that no longer exists says so', (tester) async {
    await h.pump(tester, location: '/files?folder=gone');
    expect(find.byKey(const Key('folderMissing')), findsOneWidget);
  });
}
