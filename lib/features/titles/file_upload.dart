import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:ethesishub/data/services/storage_service.dart';

/// Picks one document, or null if the user cancelled.
typedef DocumentPicker = Future<PickedDocument?> Function({
  required Set<String> allowed,
});

/// The real picker, backing a screen's own `pickDocument` by default.
/// `file_picker` has no test seam of its own, so this is the one call a
/// screen makes that a widget test cannot reach without injection.
///
/// Was private and duplicated per screen; moved here so the titles and
/// documents features share one definition instead of two copies drifting.
Future<PickedDocument?> realPicker({required Set<String> allowed}) async {
  // `allowed` used to be accepted and dropped on the floor, so the OS dialog
  // offered every file on the machine and the student learned their .zip was
  // wrong only after picking it. `validateDocument` still runs afterwards --
  // this narrows the dialog, it does not replace the check.
  final result = await FilePicker.platform.pickFiles(
    withData: true,
    type: FileType.custom,
    allowedExtensions: allowed.toList(),
  );
  final picked = result?.files.single;
  if (picked == null || picked.bytes == null) return null;
  final extension = (picked.extension ?? '').toLowerCase();
  return PickedDocument(
    name: picked.name,
    bytes: picked.bytes!,
    extension: extension,
    contentType: contentTypeFor(extension),
  );
}

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

/// A chapter carries figures and tables, so the cap is above M1b's 10 MB
/// justification limit and below the bucket's 50 MB ceiling.
const kChapterTypes = {'pdf', 'doc', 'docx'};
const kChapterMaxBytes = 15 * 1024 * 1024;

/// What My files accepts: documents, slides and photos (spec §6.3).
const kPersonalFileTypes = {
  'pdf', 'doc', 'docx', 'ppt', 'pptx', 'png', 'jpg', 'jpeg',
};

/// The same cap as a presentation, under the bucket's 50 MB ceiling.
const kPersonalFileMaxBytes = 25 * 1024 * 1024;

/// The MIME type a stored object should carry, from its extension.
///
/// Everything used to be uploaded as `application/octet-stream`, which tells
/// a browser only "unknown binary" — so the download links on the title
/// defence screen would force a save dialog instead of opening the PDF the
/// panel is trying to read mid-defence. `octet-stream` remains the fallback
/// for anything unrecognised, which is the honest answer for a file whose
/// type we do not know.
String contentTypeFor(String extension) {
  return switch (extension.toLowerCase()) {
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    _ => 'application/octet-stream',
  };
}

/// Returns an error message, or null when the file may be uploaded.
///
/// Enforced here because the Supabase bucket is public and enforces nothing:
/// there is no server-side check between this and the object store.
// File signatures ("magic bytes"), so a validated document is actually the
// kind of file its extension claims. The bucket is served to a defence panel
// and the college; an extension check alone accepts a renamed executable or
// a corrupt file that only fails when someone tries to open it in the room.
const _pdfSig = [0x25, 0x50, 0x44, 0x46]; // "%PDF"
const _zipSig = [0x50, 0x4B, 0x03, 0x04]; // "PK\x03\x04" — docx/pptx are zips
const _oleSig = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]; // legacy Office
const _pngSig = [0x89, 0x50, 0x4E, 0x47]; // "\x89PNG"
const _jpegSig = [0xFF, 0xD8, 0xFF]; // JPEG start-of-image marker

bool _startsWith(List<int> bytes, List<int> signature) {
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// Whether [bytes] carries the signature its [extension] implies. Extensions
/// outside the allow-list never reach here; unknown ones pass rather than
/// guess.
bool contentMatchesExtension(String extension, List<int> bytes) {
  return switch (extension) {
    'pdf' => _startsWith(bytes, _pdfSig),
    'docx' || 'pptx' => _startsWith(bytes, _zipSig),
    'doc' || 'ppt' => _startsWith(bytes, _oleSig),
    'png' => _startsWith(bytes, _pngSig),
    'jpg' || 'jpeg' => _startsWith(bytes, _jpegSig),
    _ => true,
  };
}

String? validateDocument(
  PickedDocument file, {
  required Set<String> allowed,
  required int maxBytes,
}) {
  final ext = file.extension.toLowerCase();
  if (!allowed.contains(ext)) {
    final names = allowed.map((e) => e.toUpperCase()).join(', ');
    return 'Choose a $names file.';
  }
  if (file.bytes.length > maxBytes) {
    final mb = (maxBytes / (1024 * 1024)).round();
    return 'That file is larger than $mb MB.';
  }
  // Content check last: the cheap extension and size checks reject the common
  // mistakes first, and this catches the file that lies about what it is.
  if (!contentMatchesExtension(ext, file.bytes)) {
    return 'That file does not look like a real ${ext.toUpperCase()} — it '
        'may have been renamed or is damaged. Choose the original file.';
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
