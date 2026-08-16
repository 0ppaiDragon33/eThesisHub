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
}

PickedDocument doc(String name, int bytes, String ext) => PickedDocument(
      name: name,
      bytes: Uint8List(bytes),
      extension: ext,
      contentType: 'application/octet-stream',
    );

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
}
