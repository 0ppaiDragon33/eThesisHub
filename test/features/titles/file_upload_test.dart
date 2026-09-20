import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

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

  @override
  Future<String> signedUrl(String path) async =>
      'https://example.test/signed/$path';
}

/// The file signature a real file of [ext] would begin with. `doc` embeds it
/// so a document that is genuinely the type its extension claims passes the
/// content check; [overrideBytes] writes something else, to stand in for a
/// renamed or damaged file.
List<int> _sigFor(String ext) => switch (ext.toLowerCase()) {
      'pdf' => const [0x25, 0x50, 0x44, 0x46],
      'docx' || 'pptx' => const [0x50, 0x4B, 0x03, 0x04],
      'doc' || 'ppt' => const [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1],
      _ => const [],
    };

PickedDocument doc(String name, int bytes, String ext,
    {List<int>? overrideBytes}) {
  final buf = Uint8List(bytes);
  final sig = overrideBytes ?? _sigFor(ext);
  for (var i = 0; i < sig.length && i < buf.length; i++) {
    buf[i] = sig[i];
  }
  return PickedDocument(
    name: name,
    bytes: buf,
    extension: ext,
    contentType: 'application/octet-stream',
  );
}

void main() {
  test('accepts an allowed type inside the size limit', () {
    expect(
      validateDocument(doc('just.pdf', 1000, 'pdf'),
          allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes),
      isNull,
    );
  });

  test('refuses a type that is not allowed, naming what is', () {
    final error = validateDocument(doc('notes.txt', 10, 'txt'),
        allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes);
    expect(error, isNotNull);
    expect(error, contains('PDF'));
  });

  test('refuses a file over the limit, naming the limit', () {
    // The bucket is public and will not enforce this, so the client must.
    final error = validateDocument(
        doc('huge.pdf', kJustificationMaxBytes + 1, 'pdf'),
        allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes);
    expect(error, isNotNull);
    expect(error, contains('10'));
  });

  test('extension matching ignores case', () {
    expect(
      validateDocument(doc('JUST.PDF', 10, 'PDF'),
          allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes),
      isNull,
    );
  });

  test('refuses a file whose content does not match its extension', () {
    // A renamed file: .pdf on the outside, not a PDF inside.
    final error = validateDocument(
        doc('renamed.pdf', 1000, 'pdf', overrideBytes: const [0, 0, 0, 0]),
        allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes);
    expect(error, isNotNull);
    expect(error, contains('PDF'));
    expect(error, contains('renamed'));
  });

  test('accepts a real docx by its zip signature', () {
    expect(
      validateDocument(doc('paper.docx', 1000, 'docx'),
          allowed: const {'pdf', 'doc', 'docx'},
          maxBytes: kJustificationMaxBytes),
      isNull,
    );
  });

  test('a docx carrying PDF bytes is refused', () {
    final error = validateDocument(
        doc('fake.docx', 1000, 'docx',
            overrideBytes: const [0x25, 0x50, 0x44, 0x46]),
        allowed: const {'pdf', 'doc', 'docx'},
        maxBytes: kJustificationMaxBytes);
    expect(error, isNotNull);
    expect(error, contains('DOCX'));
  });

  test('uploading puts the file at an unguessable path under the thesis',
      () async {
    final storage = _FakeStorage();
    final stored = await uploadDocument(
      storage: storage, file: doc('just.pdf', 10, 'pdf'),
      thesisId: 't1', documentId: 'ct1',
    );

    expect(stored.path, startsWith('theses/t1/ct1/'));
    expect(stored.path, endsWith('.pdf'));
    expect(stored.path, isNot(contains('just.pdf')),
        reason: 'the public bucket means the path must not be guessable, so '
            'it must not carry the original filename');
    expect(stored.url, contains(stored.path));
  });

  test('the content type is derived from the extension, not hardcoded', () {
    // Everything used to upload as application/octet-stream, so a public
    // bucket URL forced a save dialog rather than previewing the PDF a
    // panel member is trying to read mid-defence.
    expect(contentTypeFor('pdf'), 'application/pdf');
    expect(contentTypeFor('PDF'), 'application/pdf',
        reason: 'file_picker reports the extension in whatever case the OS did');
    expect(contentTypeFor('doc'), 'application/msword');
    expect(contentTypeFor('docx'), contains('wordprocessingml'));
    expect(contentTypeFor('ppt'), 'application/vnd.ms-powerpoint');
    expect(contentTypeFor('pptx'), contains('presentationml'));
    expect(contentTypeFor('zip'), 'application/octet-stream',
        reason: 'octet-stream stays the honest answer for an unknown type');
  });
}
