import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/files/personal_file_actions.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

class FakeStorage implements StorageService {
  final uploads = <String>[];
  final contentTypes = <String>[];
  bool fail = false;

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    if (fail) {
      throw const StorageFailure('Storage is down.', code: 'storage-failed');
    }
    uploads.add(path);
    contentTypes.add(contentType);
    return StoredFile(path: path, url: 'https://example.test/$path');
  }

  @override
  Future<void> delete(String path) async {}

  @override
  Future<String> signedUrl(String path) async => 'https://example.test/$path';
}

class FakeRemover implements PersonalFileRemover {
  final deleted = <String>[];
  bool fail = false;

  @override
  Future<void> deletePersonal(String path) async {
    if (fail) {
      throw const StorageFailure('Refused.', code: 'storage-forbidden');
    }
    deleted.add(path);
  }
}

class FailingRecordRepo extends MyFilesRepository {
  FailingRecordRepo(super.db);

  @override
  Future<void> addFile({
    required String uid,
    required String fileId,
    required String name,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
    String? folderId,
  }) =>
      Future.error(StateError('permission-denied'));
}

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

PickedDocument picked(String name, String ext, List<int> bytes) =>
    PickedDocument(
      name: name,
      bytes: Uint8List.fromList(bytes),
      extension: ext,
      // Deliberately wrong: the flow must derive the type from the extension.
      contentType: 'application/octet-stream',
    );

void main() {
  late FakeFirebaseFirestore db;
  late MyFilesRepository repo;
  late FakeStorage storage;
  late FakeRemover remover;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = MyFilesRepository(db);
    storage = FakeStorage();
    remover = FakeRemover();
  });

  test('uploads under the owner\'s area and records it under the same id',
      () async {
    final id = await uploadPersonalFile(
      storage: storage, remover: remover, repo: repo, uid: 'u1',
      file: picked('My Photo.png', 'png', png), folderId: 'fold',
    );

    expect(storage.uploads, hasLength(1));
    final path = storage.uploads.single;
    expect(path, startsWith('personal/u1/$id/'));
    expect(storage.contentTypes.single, 'image/png');

    final data = (await db.doc('users/u1/files/$id').get()).data()!;
    expect(data['name'], 'My Photo.png');
    expect(data['storagePath'], path);
    expect(data['contentType'], 'image/png');
    expect(data['sizeBytes'], png.length);
    expect(data['folderId'], 'fold');
  });

  test('a file that fails the checks is refused before anything is stored',
      () async {
    for (final file in [
      picked('run.exe', 'exe', [0x4D, 0x5A]),
      picked('fake.png', 'png', [0x25, 0x50, 0x44, 0x46]),
      picked('empty.png', 'png', const []),
    ]) {
      await expectLater(
        uploadPersonalFile(
            storage: storage, remover: remover, repo: repo, uid: 'u1',
            file: file),
        throwsA(isA<PersonalFileRejected>()),
        reason: file.name,
      );
    }
    expect(storage.uploads, isEmpty);
    expect((await db.collection('users/u1/files').get()).docs, isEmpty);
  });

  test('an empty file is refused with its own message', () async {
    await expectLater(
      uploadPersonalFile(
          storage: storage, remover: remover, repo: repo, uid: 'u1',
          file: picked('empty.png', 'png', const [])),
      throwsA(isA<PersonalFileRejected>()
          .having((e) => e.message, 'message', 'That file is empty.')),
    );
  });

  test('if storage fails, no record is written', () async {
    storage.fail = true;
    await expectLater(
      uploadPersonalFile(
          storage: storage, remover: remover, repo: repo, uid: 'u1',
          file: picked('a.png', 'png', png)),
      throwsA(isA<StorageFailure>()),
    );
    expect((await db.collection('users/u1/files').get()).docs, isEmpty);
    expect(remover.deleted, isEmpty);
  });

  test('if the record fails, the uploaded object is removed again', () async {
    await expectLater(
      uploadPersonalFile(
          storage: storage, remover: remover,
          repo: FailingRecordRepo(db), uid: 'u1',
          file: picked('a.png', 'png', png)),
      throwsA(isA<StateError>()),
    );
    expect(remover.deleted, storage.uploads,
        reason: 'the orphan is cleaned up');
  });

  test('deleting removes the stored object, then the record', () async {
    await db.doc('users/u1/files/f1').set({
      'name': 'a.png', 'storagePath': 'personal/u1/f1/x.png',
      'contentType': 'image/png', 'sizeBytes': 8, 'folderId': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });
    final file = PersonalFile.fromMap(
        'f1', (await db.doc('users/u1/files/f1').get()).data()!);

    await deletePersonalFile(
        remover: remover, repo: repo, uid: 'u1', file: file);

    expect(remover.deleted, ['personal/u1/f1/x.png']);
    expect((await db.doc('users/u1/files/f1').get()).exists, isFalse);
  });

  test('if the stored object cannot be deleted, the record is kept',
      () async {
    await db.doc('users/u1/files/f1').set({
      'name': 'a.png', 'storagePath': 'personal/u1/f1/x.png',
      'contentType': 'image/png', 'sizeBytes': 8, 'folderId': null,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
    });
    final file = PersonalFile.fromMap(
        'f1', (await db.doc('users/u1/files/f1').get()).data()!);
    remover.fail = true;

    await expectLater(
      deletePersonalFile(remover: remover, repo: repo, uid: 'u1', file: file),
      throwsA(isA<StorageFailure>()),
    );
    expect((await db.doc('users/u1/files/f1').get()).exists, isTrue,
        reason: 'the person can try again');
  });
}
