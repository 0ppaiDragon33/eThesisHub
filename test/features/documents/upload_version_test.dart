import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// Fails only the write [addVersion] makes, while every read (chapters,
/// versions, feedback streams) still goes through the real repository so
/// the rest of the screen renders normally around the failure.
class _FailingWriteRepository extends DocumentRepository {
  _FailingWriteRepository(super.db);

  @override
  Future<void> addVersion({
    required String thesisId,
    required ChapterId chapter,
    required String storagePath,
    required String fileUrl,
    required String mimeType,
    required int sizeBytes,
    required String uploadedBy,
  }) {
    throw FirebaseException(
        plugin: 'cloud_firestore', code: 'permission-denied');
  }
}

class _FakeStorage implements StorageService {
  _FakeStorage({this.failWith});
  final Object? failWith;
  final deleted = <String>[];
  int uploads = 0;

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    uploads++;
    if (failWith != null) throw failWith!;
    return StoredFile(path: path, url: 'https://example.test/$path');
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

PickedDocument doc() => PickedDocument(
      name: 'chapter1.pdf',
      bytes: Uint8List.fromList(List.filled(32, 0)),
      extension: 'pdf',
      contentType: 'application/pdf',
    );

Future<FakeFirebaseFirestore> seed({String status = 'titleApproved'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': status,
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  // The upload control is now gated on `thesis.leaderUid == me.uid`, and
  // `me` comes from the leader's own `users/l1` profile document -- without
  // it, currentUserProvider yields null forever and the button this whole
  // file taps would never render.
  await db.collection('users').doc('l1').set({
    'fullName': 'Leader One', 'email': 'l1@isufst.edu.ph',
    'role': 'student', 'active': true,
  });
  return db;
}

// Without this, `FirebaseAuth.instance` throws `[core/no-app]` because no
// app is initialised in a widget test, `authStateProvider` settles into
// AsyncError, and the handler's uid read is silently null forever -- the
// upload would never even start. Every other screen that reads a uid off
// `authStateProvider` for a write (e.g. submit_titles_screen_test.dart)
// overrides this the same way.
Widget _wrap(FakeFirebaseFirestore db, _FakeStorage storage,
        {DocumentRepository? repository}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        storageServiceProvider.overrideWithValue(storage),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'l1', email: 'l@isufst.edu.ph', isEmailVerified: true),
        )),
        if (repository != null)
          documentRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: ChapterDetailScreen(
          thesisId: 't1',
          chapter: ChapterId.chapterI,
          pickDocument: ({required Set<String> allowed}) async => doc(),
        ),
      ),
    );

void main() {
  testWidgets('an upload creates version 1 and shows it', (tester) async {
    final db = await seed();
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrap(db, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(storage.uploads, 1);
    expect(find.byKey(const Key('versionRow-1')), findsOneWidget);
  });

  testWidgets('a storage outage says so instead of "try again"',
      (tester) async {
    final db = await seed();
    final storage = _FakeStorage(
      failWith: const StorageFailure('Storage is unreachable.',
          code: 'storage-unreachable'),
    );
    await tester.pumpWidget(_wrap(db, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(find.textContaining('storage-unreachable'), findsOneWidget);
  });

  testWidgets('a failed batch deletes the file it had already uploaded',
      (tester) async {
    // Otherwise the object is orphaned in a public bucket: unreferenced,
    // unguessable, harmless, and still real.
    final db = await seed(status: 'titlePendingDefence');
    final storage = _FakeStorage();
    await tester.pumpWidget(_wrap(db, storage));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(storage.uploads, 1);
    expect(storage.deleted, hasLength(1),
        reason: 'the uploaded object must not be left behind');
    expect(
        find.text(
            'Chapters can be uploaded once the title has been approved.'),
        findsOneWidget,
        reason: 'the original failure is reported, not the cleanup');
  });

  testWidgets(
      'a permission-denied write shows a specific message and deletes the '
      'orphaned file', (tester) async {
    final db = await seed();
    final storage = _FakeStorage();
    await tester.pumpWidget(
        _wrap(db, storage, repository: _FailingWriteRepository(db)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('uploadVersion')));
    await tester.pumpAndSettle();

    expect(find.textContaining('You do not have permission'), findsOneWidget);
    expect(storage.deleted, hasLength(1),
        reason: 'the uploaded object must not be left behind');
  });
}
