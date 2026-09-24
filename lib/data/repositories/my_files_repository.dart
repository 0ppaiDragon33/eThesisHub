import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/models/personal_folder.dart';

/// The longest folder name `firestore.rules` accepts.
const int kFolderNameMax = 60;

/// The longest file name `firestore.rules` accepts.
const int kFileNameMax = 200;

/// One person's My files: folders and uploaded-file records under
/// `users/{uid}`. Form copies live beside them (`formCopies`) and are
/// handled by `FormCopyRepository`, except that deleting a folder moves them
/// too.
class MyFilesRepository {
  MyFilesRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _folders(String uid) =>
      _db.collection('users').doc(uid).collection('folders');

  CollectionReference<Map<String, dynamic>> _files(String uid) =>
      _db.collection('users').doc(uid).collection('files');

  CollectionReference<Map<String, dynamic>> _copies(String uid) =>
      _db.collection('users').doc(uid).collection('formCopies');

  /// Folders by name, ignoring case.
  Stream<List<PersonalFolder>> watchFolders(String uid) =>
      _folders(uid).snapshots().map((s) => [
            for (final d in s.docs) PersonalFolder.fromMap(d.id, d.data()),
          ]..sort((a, b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  Future<String> createFolder({
    required String uid,
    required String name,
  }) async {
    final ref = _folders(uid).doc();
    await ref.set({
      'name': _checked(name, kFolderNameMax),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> renameFolder({
    required String uid,
    required String folderId,
    required String name,
  }) =>
      _folders(uid)
          .doc(folderId)
          .update({'name': _checked(name, kFolderNameMax)});

  /// Moves every copy and file in the folder to the top level, then deletes
  /// the folder, in one batch. Nothing inside is deleted. Returns how many
  /// items moved.
  ///
  /// A copy's move also stamps `updatedAt`: the form-copy rules require it
  /// on every update.
  Future<int> deleteFolder({
    required String uid,
    required String folderId,
  }) async {
    final copies =
        await _copies(uid).where('folderId', isEqualTo: folderId).get();
    final files =
        await _files(uid).where('folderId', isEqualTo: folderId).get();
    final batch = _db.batch();
    for (final d in copies.docs) {
      batch.update(d.reference, {
        'folderId': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    for (final d in files.docs) {
      batch.update(d.reference, {'folderId': null});
    }
    batch.delete(_folders(uid).doc(folderId));
    await batch.commit();
    return copies.size + files.size;
  }

  /// Uploaded files, newest first. A record not yet stamped by the server
  /// counts as newest.
  Stream<List<PersonalFile>> watchFiles(String uid) =>
      _files(uid).snapshots().map((s) {
        final files = [
          for (final d in s.docs) PersonalFile.fromMap(d.id, d.data()),
        ];
        files.sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return -1;
          if (bt == null) return 1;
          return bt.compareTo(at);
        });
        return files;
      });

  /// A fresh record id, reserved before the upload so the storage path and
  /// the record carry the same id (the rules require it).
  String newFileId(String uid) => _files(uid).doc().id;

  /// Records an uploaded file under [fileId]. The person's filename is kept
  /// as given but trimmed, cut to [kFileNameMax], and "Untitled" if blank, so
  /// an unusual filename never blocks an upload that already happened.
  Future<void> addFile({
    required String uid,
    required String fileId,
    required String name,
    required String storagePath,
    required String contentType,
    required int sizeBytes,
    String? folderId,
  }) {
    var shown = name.trim();
    if (shown.isEmpty) shown = 'Untitled';
    if (shown.length > kFileNameMax) shown = shown.substring(0, kFileNameMax);
    return _files(uid).doc(fileId).set({
      'name': shown,
      'storagePath': storagePath,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'folderId': folderId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> renameFile({
    required String uid,
    required String fileId,
    required String name,
  }) =>
      _files(uid).doc(fileId).update({'name': _checked(name, kFileNameMax)});

  Future<void> moveFile({
    required String uid,
    required String fileId,
    String? folderId,
  }) =>
      _files(uid).doc(fileId).update({'folderId': folderId});

  Future<void> deleteFileRecord({
    required String uid,
    required String fileId,
  }) =>
      _files(uid).doc(fileId).delete();

  static String _checked(String name, int max) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > max) {
      throw ArgumentError.value(name, 'name', 'must be 1 to $max characters');
    }
    return trimmed;
  }
}
