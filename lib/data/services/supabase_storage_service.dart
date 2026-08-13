import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/data/services/storage_service.dart';

class SupabaseStorageService implements StorageService {
  SupabaseStorageService(this._client);

  final SupabaseClient _client;

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    final bucket = _client.storage.from(AppConfig.documentsBucket);

    await bucket.uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );

    return StoredFile(path: path, url: bucket.getPublicUrl(path));
  }

  @override
  Future<void> delete(String path) async {
    await _client.storage.from(AppConfig.documentsBucket).remove([path]);
  }
}
