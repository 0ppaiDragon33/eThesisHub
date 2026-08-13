import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/storage_service.dart';

void main() {
  test('thesis document paths are namespaced and unguessable', () {
    final path = StoragePaths.thesisDocument(
      thesisId: 'thesis-1',
      documentId: 'doc-1',
      extension: 'pdf',
    );

    expect(path, startsWith('theses/thesis-1/doc-1/'));
    expect(path, endsWith('.pdf'));
    // A UUID v4 has 36 characters; the segment must not be predictable.
    final filename = path.split('/').last;
    expect(filename.length, greaterThan(36));
  });

  test('two calls never produce the same path', () {
    final a = StoragePaths.thesisDocument(
        thesisId: 't', documentId: 'd', extension: 'pdf');
    final b = StoragePaths.thesisDocument(
        thesisId: 't', documentId: 'd', extension: 'pdf');
    expect(a, isNot(b));
  });
}
