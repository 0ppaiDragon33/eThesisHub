import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/data/services/storage_service.dart';

class SupabaseStorageService implements StorageService {
  SupabaseStorageService(this._client);

  final SupabaseClient _client;

  /// Every failure leaves here as a [StorageFailure].
  ///
  /// Supabase is outside Firebase, so nothing translates its errors the way
  /// `ErrorState` translates Firestore's — a paused project surfaces as a
  /// bare `XMLHttpRequest error`, which a screen would otherwise report as
  /// "please try again" for a condition retrying can never fix.
  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    final bucket = _client.storage.from(AppConfig.documentsBucket);

    try {
      await bucket.uploadBinary(
        path,
        Uint8List.fromList(bytes),
        fileOptions: FileOptions(contentType: contentType, upsert: false),
      );
    } catch (e) {
      throw classifyStorageError(e);
    }

    return StoredFile(path: path, url: bucket.getPublicUrl(path));
  }

  @override
  Future<void> delete(String path) async {
    try {
      await _client.storage.from(AppConfig.documentsBucket).remove([path]);
    } catch (e) {
      throw classifyStorageError(e);
    }
  }
}
