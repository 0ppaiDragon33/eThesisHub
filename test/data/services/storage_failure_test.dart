import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/storage_service.dart';

/// The shapes the real clients actually throw. Written out verbatim rather
/// than summarised, because the classifier matches on their text and a
/// paraphrase would test nothing.
class _Thrown implements Exception {
  const _Thrown(this._text);
  final String _text;
  @override
  String toString() => _text;
}

void main() {
  test('an unreachable host says retrying will not help', () {
    // What a browser throws when the Supabase project's hostname stops
    // resolving — a paused or deleted project. This is the case that
    // actually happened: the generic handler told a student to "try again"
    // for a condition no amount of retrying could fix.
    final web = classifyStorageError(
        const _Thrown('ClientException: XMLHttpRequest error., uri=https://x'));
    expect(web.code, 'storage-unreachable');
    expect(web.message, contains('not something you can fix by retrying'));

    // The Android equivalent of the same condition.
    final android = classifyStorageError(const _Thrown(
        "SocketException: Failed host lookup: 'x.supabase.co'"));
    expect(android.code, 'storage-unreachable');
  });

  test('a refused upload is named as a configuration problem', () {
    expect(classifyStorageError(const _Thrown('StorageException: 403')).code,
        'storage-forbidden');
    expect(
        classifyStorageError(const _Thrown('Bucket not found')).code,
        'storage-missing-bucket');
  });

  test('an unrecognised failure still names storage, not the network', () {
    // The fallback must not blame the connection. "Check your connection"
    // once sent someone hunting a network fault that did not exist.
    final other = classifyStorageError(const _Thrown('something odd'));
    expect(other.code, 'storage-failed');
    expect(other.message.toLowerCase(), contains('storage'));

    // And it must carry the service's own words. Without them an
    // unclassified failure is undiagnosable: there are no server-side logs,
    // so the screen is the only place the cause can ever appear.
    expect(other.message, contains('something odd'));
  });

  test('every classification carries a code and a non-empty message', () {
    // The code is the only diagnostic that reaches a screen: there are no
    // server-side logs on this project.
    for (final raw in [
      'XMLHttpRequest error',
      'StorageException: 403',
      'Bucket not found',
      '413 too large',
      'unrecognised',
    ]) {
      final f = classifyStorageError(_Thrown(raw));
      expect(f.code, isNotEmpty, reason: raw);
      expect(f.message, isNotEmpty, reason: raw);
      expect(f.toString(), contains(f.code));
    }
  });
}
