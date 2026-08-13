import 'package:uuid/uuid.dart';

class StoredFile {
  const StoredFile({required this.path, required this.url});
  final String path;
  final String url;
}

/// The Supabase bucket is public, so paths must be unguessable (spec §7.2).
class StoragePaths {
  static const _uuid = Uuid();

  static String thesisDocument({
    required String thesisId,
    required String documentId,
    required String extension,
  }) {
    return 'theses/$thesisId/$documentId/${_uuid.v4()}-${_uuid.v4()}.$extension';
  }
}

abstract class StorageService {
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  });

  Future<void> delete(String path);
}
