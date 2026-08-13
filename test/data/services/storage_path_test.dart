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

    final filename = path.split('/').last;
    // Filename must be a genuine UUID v4 (36 chars) + extension.
    // Regex pattern: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx.ext
    // where x = [0-9a-f], y = [89ab]
    final uuidV4Pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.\w+$',
      caseSensitive: false,
    );
    expect(filename, matches(uuidV4Pattern),
        reason: 'filename must be a genuine UUID v4 to prove unguessability');
  });

  test('two calls never produce the same path', () {
    final a = StoragePaths.thesisDocument(
        thesisId: 't', documentId: 'd', extension: 'pdf');
    final b = StoragePaths.thesisDocument(
        thesisId: 't', documentId: 'd', extension: 'pdf');
    expect(a, isNot(b));
  });
}
