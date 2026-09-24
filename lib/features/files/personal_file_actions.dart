import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

/// A picked file My files will not take, with the sentence to show.
class PersonalFileRejected implements Exception {
  const PersonalFileRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Adds a picked file to [uid]'s My files, into [folderId] or the top
/// level. Returns the new record's id.
///
/// Checks first (type, size, real content, not empty), so a bad file never
/// reaches storage. Then the bytes go up, then the record. If the record
/// cannot be written, the uploaded object is removed again: without a record
/// it would sit invisible and still use storage.
Future<String> uploadPersonalFile({
  required StorageService storage,
  required PersonalFileRemover remover,
  required MyFilesRepository repo,
  required String uid,
  required PickedDocument file,
  String? folderId,
}) async {
  if (file.bytes.isEmpty) {
    throw const PersonalFileRejected('That file is empty.');
  }
  final problem = validateDocument(
    file,
    allowed: kPersonalFileTypes,
    maxBytes: kPersonalFileMaxBytes,
  );
  if (problem != null) throw PersonalFileRejected(problem);

  final extension = file.extension.toLowerCase();
  // From the extension, not the picker: the rules accept only the types
  // this app itself names.
  final contentType = contentTypeFor(extension);
  final fileId = repo.newFileId(uid);
  final path = StoragePaths.personalFile(
    uid: uid,
    fileId: fileId,
    extension: extension,
  );

  await storage.upload(bytes: file.bytes, path: path, contentType: contentType);
  try {
    await repo.addFile(
      uid: uid,
      fileId: fileId,
      name: file.name,
      storagePath: path,
      contentType: contentType,
      sizeBytes: file.bytes.length,
      folderId: folderId,
    );
  } catch (_) {
    try {
      await remover.deletePersonal(path);
    } catch (_) {
      // Best effort: the record failure below is what the person needs to
      // see, not a second failure about cleaning up after it.
    }
    rethrow;
  }
  return fileId;
}

/// Deletes one of [uid]'s files: the stored object first (through the
/// server function), then the record. If the object cannot be deleted the
/// record stays, so the file is still listed and the person can try again.
Future<void> deletePersonalFile({
  required PersonalFileRemover remover,
  required MyFilesRepository repo,
  required String uid,
  required PersonalFile file,
}) async {
  await remover.deletePersonal(file.storagePath);
  await repo.deleteFileRecord(uid: uid, fileId: file.id);
}
