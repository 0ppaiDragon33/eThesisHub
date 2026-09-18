import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// Opens a stored thesis document, asking for a fresh signed URL first.
///
/// The bucket is private and the URLs Firestore holds are identifiers, not
/// links — see [StoredFile.url]. Every open therefore goes through the
/// `document-url` function, which decides whether this reader is entitled to
/// this file before it signs anything.
///
/// That means opening a document can legitimately FAIL, in ways a public
/// bucket never did: the reader may have been removed from the panel, their
/// account deactivated, or their session expired. Those are reported here
/// rather than silently opening a broken tab, and none of them are phrased
/// as "try again" — retrying cannot change any of them.
///
/// Returns true when a URL was obtained and handed to the platform.
Future<bool> openStoredDocument(
  BuildContext context,
  WidgetRef ref,
  String storagePath, {
  String? label,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (storagePath.trim().isEmpty) {
    _say(messenger, 'This entry does not record where its file is stored, so '
        'it cannot be opened.');
    return false;
  }

  try {
    final url = await ref.read(storageServiceProvider).signedUrl(storagePath);
    final opened =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened) {
      _say(messenger,
          'Nothing on this device could open ${label ?? 'that document'}.');
    }
    return opened;
  } on StorageFailure catch (e) {
    _say(messenger, '${e.message} [${e.code}]');
    return false;
  }
}

void _say(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}
