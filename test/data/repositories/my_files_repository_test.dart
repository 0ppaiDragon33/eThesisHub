import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MyFilesRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = MyFilesRepository(db);
  });

  Timestamp at(int day) => Timestamp.fromDate(DateTime(2026, 9, day));

  Future<void> seedCopy(String id, String? folderId) =>
      db.doc('users/u1/formCopies/$id').set({
        'formId': 'form1', 'name': id, 'overrides': <String, String>{},
        'folderId': folderId, 'createdAt': at(1), 'updatedAt': at(1),
      });

  Future<void> seedFile(String id, String? folderId, {int day = 1}) =>
      db.doc('users/u1/files/$id').set({
        'name': '$id.pdf', 'storagePath': 'personal/u1/$id/a.pdf',
        'contentType': 'application/pdf', 'sizeBytes': 10,
        'folderId': folderId, 'createdAt': at(day),
      });

  test('createFolder writes only a trimmed name and the time', () async {
    final id = await repo.createFolder(uid: 'u1', name: '  Group 3  ');
    final data = (await db.doc('users/u1/folders/$id').get()).data()!;
    expect(data.keys.toSet(), {'name', 'createdAt'});
    expect(data['name'], 'Group 3');
  });

  test('a folder name must be 1 to $kFolderNameMax characters', () {
    expect(() => repo.createFolder(uid: 'u1', name: ' '), throwsArgumentError);
    expect(() => repo.createFolder(uid: 'u1', name: 'x' * 61),
        throwsArgumentError);
  });

  test('watchFolders lists folders by name', () async {
    await repo.createFolder(uid: 'u1', name: 'b folder');
    await repo.createFolder(uid: 'u1', name: 'A folder');
    final folders = await repo.watchFolders('u1').first;
    expect(folders.map((f) => f.name), ['A folder', 'b folder']);
  });

  test('renameFolder changes only the name', () async {
    final id = await repo.createFolder(uid: 'u1', name: 'Old');
    await repo.renameFolder(uid: 'u1', folderId: id, name: 'New');
    expect((await db.doc('users/u1/folders/$id').get()).data()!['name'],
        'New');
  });

  test('deleting a folder moves its copies and files to the top level',
      () async {
    final keep = await repo.createFolder(uid: 'u1', name: 'Keep');
    final gone = await repo.createFolder(uid: 'u1', name: 'Gone');
    await seedCopy('c-in', gone);
    await seedCopy('c-other', keep);
    await seedFile('f-in', gone);
    await seedFile('f-other', keep);

    final moved = await repo.deleteFolder(uid: 'u1', folderId: gone);

    expect(moved, 2);
    expect((await db.doc('users/u1/folders/$gone').get()).exists, isFalse);
    expect((await db.doc('users/u1/formCopies/c-in').get())['folderId'],
        isNull);
    expect((await db.doc('users/u1/files/f-in').get())['folderId'], isNull);
    expect((await db.doc('users/u1/formCopies/c-other').get())['folderId'],
        keep, reason: 'another folder is left alone');
    expect((await db.doc('users/u1/files/f-other').get())['folderId'], keep);
  });

  test('addFile writes exactly the record the rules allow, under its id',
      () async {
    final id = repo.newFileId('u1');
    await repo.addFile(
      uid: 'u1', fileId: id, name: '  Photo.png ',
      storagePath: 'personal/u1/$id/x.png', contentType: 'image/png',
      sizeBytes: 1234, folderId: null,
    );
    final data = (await db.doc('users/u1/files/$id').get()).data()!;
    expect(data.keys.toSet(), {
      'name', 'storagePath', 'contentType', 'sizeBytes', 'folderId',
      'createdAt',
    });
    expect(data['name'], 'Photo.png');
    expect(data['sizeBytes'], 1234);
  });

  test('an uploaded file keeps a name the rules accept', () async {
    final long = repo.newFileId('u1');
    await repo.addFile(
      uid: 'u1', fileId: long, name: '${'x' * 250}.pdf',
      storagePath: 'personal/u1/$long/x.pdf', contentType: 'application/pdf',
      sizeBytes: 1,
    );
    expect(
        ((await db.doc('users/u1/files/$long').get())['name'] as String)
            .length,
        kFileNameMax);

    final blank = repo.newFileId('u1');
    await repo.addFile(
      uid: 'u1', fileId: blank, name: '   ',
      storagePath: 'personal/u1/$blank/x.pdf',
      contentType: 'application/pdf', sizeBytes: 1,
    );
    expect((await db.doc('users/u1/files/$blank').get())['name'], 'Untitled');
  });

  test('watchFiles lists newest first', () async {
    await seedFile('old', null, day: 1);
    await seedFile('new', null, day: 3);
    final files = await repo.watchFiles('u1').first;
    expect(files.map((f) => f.id), ['new', 'old']);
    expect(files.first, isA<PersonalFile>());
  });

  test('renameFile is strict; moveFile and deleteFileRecord work', () async {
    await seedFile('f1', null);
    await repo.renameFile(uid: 'u1', fileId: 'f1', name: ' Notes.pdf ');
    expect((await db.doc('users/u1/files/f1').get())['name'], 'Notes.pdf');
    expect(() => repo.renameFile(uid: 'u1', fileId: 'f1', name: ''),
        throwsArgumentError);

    await repo.moveFile(uid: 'u1', fileId: 'f1', folderId: 'fold');
    expect((await db.doc('users/u1/files/f1').get())['folderId'], 'fold');
    await repo.moveFile(uid: 'u1', fileId: 'f1', folderId: null);
    expect((await db.doc('users/u1/files/f1').get())['folderId'], isNull);

    await repo.deleteFileRecord(uid: 'u1', fileId: 'f1');
    expect((await db.doc('users/u1/files/f1').get()).exists, isFalse);
  });
}
