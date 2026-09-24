import 'package:uuid/uuid.dart';

class StoredFile {
  const StoredFile({required this.path, required this.url});

  /// Where the object lives. This is the durable reference: Firestore stores
  /// it (`storagePath`, `manuscriptPath`) and every read is a
  /// [StorageService.signedUrl] call against it.
  final String path;

  /// The object's canonical address.
  ///
  /// Recorded by Firestore as `fileUrl` / `manuscriptUrl` and pinned by
  /// `firestore.rules` (the archive rule requires the published entry to name
  /// the same manuscript the thesis does), so it is still written.
  ///
  /// It is an IDENTIFIER, not a capability. The bucket is private, so
  /// fetching this URL directly returns an error — reading the file means
  /// asking [StorageService.signedUrl] for a fresh, short-lived URL. Nothing
  /// in the app should pass this to `launchUrl`.
  final String url;
}

/// Paths carry a UUID and never the original filename.
///
/// The bucket is private and the `document-url` function authorizes every
/// read, so unguessability is no longer the access control it once had to be
/// — it is now defence in depth, and it keeps a student's filename out of a
/// URL that other readers of the thesis will see.
class StoragePaths {
  static const _uuid = Uuid();

  static String thesisDocument({
    required String thesisId,
    required String documentId,
    required String extension,
  }) {
    return 'theses/$thesisId/$documentId/${_uuid.v4()}.$extension';
  }

  /// A file in someone's My files:
  /// `personal/{uid}/{fileId}/{uuid}.{extension}`.
  ///
  /// The person's own filename never goes in the path. It is kept in the
  /// Firestore record, and a generated name always passes the
  /// `document-url` function's strict filename check, which real filenames
  /// (spaces, accents, brackets) do not.
  static String personalFile({
    required String uid,
    required String fileId,
    required String extension,
  }) {
    return 'personal/$uid/$fileId/${_uuid.v4()}.$extension';
  }
}

/// A storage operation that failed, described in terms a screen can show.
///
/// Firestore failures arrive already coded, and [ErrorState] translates those.
/// Storage failures do not: Supabase sits outside Firebase entirely, with no
/// rules layer in front of it, so its errors surface as whatever the HTTP
/// client threw. Screens must not have to recognise those, which is why the
/// storage implementation translates them here and nothing above the data
/// layer imports Supabase.
class StorageFailure implements Exception {
  const StorageFailure(this.message, {required this.code});

  /// What to show the person. Says what happened and whether retrying helps.
  final String message;

  /// A short tag for the cause, shown beside the message — there are no
  /// server-side logs on this project, so the screen is the only place a
  /// cause can surface.
  final String code;

  @override
  String toString() => '$message [$code]';
}

/// Classifies a raw storage exception.
///
/// A pure function, separate from the client, so it can be tested against the
/// exact shapes the real one throws without standing up a network.
///
/// The case that matters most is an unreachable host. On the free tier a
/// Supabase project pauses after about a week of inactivity and is deleted
/// after a long enough pause — and when the hostname stops resolving, the
/// browser throws an `XMLHttpRequest error` that is indistinguishable from a
/// flat battery unless it is named. Telling a student to "try again" then is
/// worse than saying nothing: retrying cannot possibly work.
StorageFailure classifyStorageError(Object error) {
  final text = error.toString();

  // A DNS failure, a dead host, or an offline device. In a browser this is
  // `ClientException: XMLHttpRequest error`; on Android it is a
  // SocketException naming a failed host lookup.
  if (text.contains('XMLHttpRequest error') ||
      text.contains('ClientException') ||
      text.contains('SocketException') ||
      text.contains('Failed host lookup')) {
    return const StorageFailure(
      'Could not reach file storage, so nothing was uploaded. This is not '
      'something you can fix by retrying — tell whoever administers the '
      'project.',
      code: 'storage-unreachable',
    );
  }

  // Supabase reports its own API errors with a status code in the text.
  if (text.contains('403') || text.contains('Unauthorized')) {
    return const StorageFailure(
      'File storage refused the upload. The bucket may not be public, or '
      'the key may be wrong.',
      code: 'storage-forbidden',
    );
  }
  if (text.contains('404') || text.contains('Bucket not found')) {
    return const StorageFailure(
      'The storage bucket does not exist.',
      code: 'storage-missing-bucket',
    );
  }
  // A bucket-level MIME allow-list. `validateDocument` already restricts the
  // extension, so reaching here means the bucket disagrees with the app about
  // what a thesis document is — configuration, not a bad file, and no amount
  // of choosing a different file will help.
  if (text.contains('415') ||
      text.contains('invalid_mime_type') ||
      text.contains('mime type')) {
    return const StorageFailure(
      'File storage rejected this file type. The bucket has a MIME allow-list '
      'that does not include it — this needs fixing in Supabase, not by '
      'choosing another file.',
      code: 'storage-wrong-type',
    );
  }

  if (text.contains('413') || text.contains('too large')) {
    return const StorageFailure(
      'File storage rejected the file as too large.',
      code: 'storage-too-large',
    );
  }

  // Unrecognised. Carry the service's own words through rather than replacing
  // them with a friendlier sentence that says less: an unclassified failure is
  // precisely the one nobody can diagnose without them, and this project has
  // no server-side logs to consult instead. Trimmed and collapsed, because a
  // raw stack trace on a student's screen helps nobody either.
  final detail = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return StorageFailure(
    'File storage could not accept the upload. It said: '
    '${detail.length > 200 ? '${detail.substring(0, 200)}…' : detail}',
    code: 'storage-failed',
  );
}

abstract class StorageService {
  /// Throws [StorageFailure] — never a raw client exception. Callers above
  /// the data layer depend on that.
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  });

  Future<void> delete(String path);

  /// A short-lived URL for reading the object at [path].
  ///
  /// The bucket is private, so there is no durable URL to store and none of
  /// these outlives a couple of minutes. Screens therefore hold the
  /// **storage path** — which is what Firestore records — and ask for a URL
  /// at the moment the reader opens the file.
  ///
  /// Authorization happens server-side, in the `document-url` edge function:
  /// it verifies the caller's Firebase ID token, asks Firestore whether they
  /// are on this thesis, and only then signs. Nothing about that decision is
  /// made here, and a caller who is not entitled to the file gets a
  /// [StorageFailure] rather than a URL.
  ///
  /// Throws [StorageFailure] — including `storage-forbidden` when the reader
  /// is not authorized for the thesis the path belongs to.
  Future<String> signedUrl(String path);
}
