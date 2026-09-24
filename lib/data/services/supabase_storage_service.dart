import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/data/services/storage_service.dart';

class SupabaseStorageService implements StorageService, PersonalFileRemover {
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
    final (status, body) = await _callDocumentFunction({'path': path});
    if (status == 200) {
      final url = body['url'];
      if (url is String && url.isNotEmpty) return url;
      throw const StorageFailure(
        'File storage returned no link for this document.',
        code: 'storage-failed',
      );
    }
    throw _refusal(status, body['error'],
        personal: path.startsWith('personal/'));
  }

  @override
  Future<void> deletePersonal(String path) async {
    final (status, body) =
        await _callDocumentFunction({'path': path, 'action': 'delete'});
    if (status == 200) return;
    throw _refusal(status, body['error'], personal: true);
  }

  /// Calls the `document-url` function as the signed-in reader, whose
  /// Firebase ID token is the only thing that tells one reader from another.
  Future<(int, Map<String, dynamic>)> _callDocumentFunction(
    Map<String, Object> request,
  ) async {
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

    try {
      final res = await _client.functions.invoke(
        'document-url',
        body: request,
        headers: {'Authorization': 'Bearer $token'},
      );
      return (res.status, _asBody(res.data));
    } on FunctionException catch (e) {
      // functions_client 2.7.1 never returns a non-2xx `FunctionResponse`
      // from `invoke`: it throws instead. Without this catch, every refusal
      // (wrong owner, deactivated account, expired session) falls into the
      // generic `catch` below and is misreported as a generic storage
      // failure, so it must be caught before that one runs.
      return (e.status, _asBody(e.details));
    } catch (e) {
      throw classifyStorageError(e);
    }
  }

  /// Decodes a function response/exception body, which arrives as a `Map`,
  /// a JSON-encoded `String`, or nothing at all.
  static Map<String, dynamic> _asBody(Object? data) => switch (data) {
        final Map<String, dynamic> m => m,
        final String s when s.isNotEmpty =>
          jsonDecode(s) as Map<String, dynamic>,
        _ => const {},
      };

  /// Turns the function's refusal into something a screen can show.
  ///
  /// These are not retryable and must not be reported as though they were:
  /// telling a panel member who was removed from a thesis to "try again" is
  /// worse than telling them they no longer have access.
  StorageFailure _refusal(int status, Object? code, {bool personal = false}) =>
      switch ((status, code)) {
        (401, _) => const StorageFailure(
            'Your session has expired. Sign in again to open this document.',
            code: 'storage-unauthenticated',
          ),
        (403, 'unverified') => const StorageFailure(
            'Verify your email address before opening thesis documents.',
            code: 'storage-unverified',
          ),
        (403, _) when personal => const StorageFailure(
            'Only the person who added this file can open or delete it.',
            code: 'storage-forbidden',
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
