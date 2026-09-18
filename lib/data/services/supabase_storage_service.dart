import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/data/services/storage_service.dart';

class SupabaseStorageService implements StorageService {
  SupabaseStorageService(this._client, this._auth);

  final SupabaseClient _client;

  /// The source of the caller's identity.
  ///
  /// Supabase has no idea who the reader is — the app authenticates with
  /// Firebase and initialises Supabase with the publishable key and no
  /// session, so every request to Supabase arrives as the same anonymous
  /// principal. The Firebase ID token is what the `document-url` function
  /// verifies, and it is the only thing that distinguishes one reader from
  /// another.
  final FirebaseAuth _auth;

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

    // Recorded by Firestore and pinned by `firestore.rules`, but never
    // fetched: the bucket is private. See [StoredFile.url].
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

  @override
  Future<String> signedUrl(String path) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const StorageFailure(
        'You are signed out, so this file cannot be opened. Sign in and try '
        'again.',
        code: 'storage-unauthenticated',
      );
    }

    final String token;
    try {
      final t = await user.getIdToken();
      if (t == null || t.isEmpty) throw StateError('no token');
      token = t;
    } catch (e) {
      throw classifyStorageError(e);
    }

    final Map<String, dynamic> body;
    final int status;
    try {
      final res = await _client.functions.invoke(
        'document-url',
        body: {'path': path},
        headers: {'Authorization': 'Bearer $token'},
      );
      status = res.status;
      body = switch (res.data) {
        final Map<String, dynamic> m => m,
        final String s when s.isNotEmpty =>
          jsonDecode(s) as Map<String, dynamic>,
        _ => const {},
      };
    } catch (e) {
      throw classifyStorageError(e);
    }

    if (status == 200) {
      final url = body['url'];
      if (url is String && url.isNotEmpty) return url;
      throw const StorageFailure(
        'File storage returned no link for this document.',
        code: 'storage-failed',
      );
    }

    throw _refusal(status, body['error']);
  }

  /// Turns the function's refusal into something a screen can show.
  ///
  /// These are not retryable and must not be reported as though they were:
  /// telling a panel member who was removed from a thesis to "try again" is
  /// worse than telling them they no longer have access.
  StorageFailure _refusal(int status, Object? code) => switch ((status, code)) {
        (401, _) => const StorageFailure(
            'Your session has expired. Sign in again to open this document.',
            code: 'storage-unauthenticated',
          ),
        (403, 'unverified') => const StorageFailure(
            'Verify your email address before opening thesis documents.',
            code: 'storage-unverified',
          ),
        (403, _) => const StorageFailure(
            'You do not have access to this document. Only the group, their '
            'adviser, the panel and the research office can open it.',
            code: 'storage-forbidden',
          ),
        (400, _) => const StorageFailure(
            'That document reference is not one this app can open.',
            code: 'storage-bad-path',
          ),
        _ => const StorageFailure(
            'File storage could not produce a link for this document. This is '
            'not something you can fix by retrying — tell whoever administers '
            'the project.',
            code: 'storage-failed',
          ),
      };
}
