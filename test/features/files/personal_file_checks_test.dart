import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';

const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const jpeg = [0xFF, 0xD8, 0xFF, 0xE0];
const pdf = [0x25, 0x50, 0x44, 0x46, 0x2D];

PickedDocument picked(String ext, Uint8List bytes) => PickedDocument(
      name: 'x.$ext',
      bytes: bytes,
      extension: ext,
      contentType: contentTypeFor(ext),
    );

String? check(PickedDocument file) => validateDocument(
      file,
      allowed: kPersonalFileTypes,
      maxBytes: kPersonalFileMaxBytes,
    );

void main() {
  test('My files accepts documents, slides and photos, up to 25 MB', () {
    expect(kPersonalFileTypes,
        {'pdf', 'doc', 'docx', 'ppt', 'pptx', 'png', 'jpg', 'jpeg'});
    expect(kPersonalFileMaxBytes, 25 * 1024 * 1024);
  });

  test('a real PNG or JPEG passes the content check', () {
    expect(contentMatchesExtension('png', png), isTrue);
    expect(contentMatchesExtension('jpg', jpeg), isTrue);
    expect(contentMatchesExtension('jpeg', jpeg), isTrue);
  });

  test('a renamed file fails the content check', () {
    expect(contentMatchesExtension('png', pdf), isFalse);
    expect(contentMatchesExtension('jpg', png), isFalse);
  });

  test('photos are stored with an image content type', () {
    expect(contentTypeFor('png'), 'image/png');
    expect(contentTypeFor('jpg'), 'image/jpeg');
    expect(contentTypeFor('JPEG'), 'image/jpeg');
  });

  test('validateDocument with the My files limits', () {
    expect(check(picked('png', Uint8List.fromList(png))), isNull);
    expect(check(picked('pdf', Uint8List.fromList(pdf))), isNull);
    expect(check(picked('exe', Uint8List.fromList([0x4D, 0x5A]))), isNotNull,
        reason: 'not an allowed type');
    expect(check(picked('png', Uint8List.fromList(pdf))),
        contains('does not look like a real PNG'));

    final big = Uint8List(kPersonalFileMaxBytes + 1)..setRange(0, 4, pdf);
    expect(check(picked('pdf', big)), 'That file is larger than 25 MB.');
  });

  test('a personal file path is personal/{uid}/{fileId}/{uuid}.{ext}', () {
    final path =
        StoragePaths.personalFile(uid: 'u1', fileId: 'f1', extension: 'png');
    expect(path, matches(RegExp(r'^personal/u1/f1/[0-9a-f-]{36}\.png$')));
  });
}
