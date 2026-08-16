import 'dart:typed_data';

import 'package:ethesishub/data/services/storage_service.dart';

/// A file the user chose, held in memory.
///
/// Bytes rather than a path, because `dart:io` does not exist on Web and this
/// app targets Web as well as Android.
class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final String extension;
  final String contentType;
}

const kJustificationTypes = {'pdf', 'doc', 'docx'};
const kJustificationMaxBytes = 10 * 1024 * 1024;

const kPresentationTypes = {'pptx', 'ppt', 'pdf'};
const kPresentationMaxBytes = 25 * 1024 * 1024;

/// Returns an error message, or null when the file may be uploaded.
///
/// Enforced here because the Supabase bucket is public and enforces nothing:
/// there is no server-side check between this and the object store.
String? validateDocument(
  PickedDocument file, {
  required Set<String> allowed,
  required int maxBytes,
}) {
  if (!allowed.contains(file.extension.toLowerCase())) {
    final names = allowed.map((e) => e.toUpperCase()).join(', ');
    return 'Choose a $names file.';
  }
  if (file.bytes.length > maxBytes) {
    final mb = (maxBytes / (1024 * 1024)).round();
    return 'That file is larger than $mb MB.';
  }
  return null;
}

/// Uploads to Supabase and returns where it landed.
///
/// The path carries a UUID and NOT the original filename: the bucket is
/// public, so anything guessable is readable by anyone.
Future<StoredFile> uploadDocument({
  required StorageService storage,
  required PickedDocument file,
  required String thesisId,
  required String documentId,
}) {
  final path = StoragePaths.thesisDocument(
    thesisId: thesisId,
    documentId: documentId,
    extension: file.extension.toLowerCase(),
  );
  return storage.upload(
      bytes: file.bytes, path: path, contentType: file.contentType);
}
