import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// Reads the bytes behind a signed URL. A provider so a widget test can
/// stand in for the network.
typedef DocumentBytesFetcher = Future<Uint8List> Function(Uri url);

/// Hands a URL to the platform: a new tab on Web, the system viewer on
/// Android. Returns false when nothing could open it.
typedef ExternalOpener = Future<bool> Function(Uri url);

final storedDocumentBytesProvider = Provider<DocumentBytesFetcher>(
  (ref) => (url) async {
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw StateError('The file could not be read (${response.statusCode}).');
    }
    return response.bodyBytes;
  },
);

final externalOpenerProvider = Provider<ExternalOpener>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Opens a stored thesis document in the in-app viewer, with a Download
/// button on the preview: the same way a form opens.
///
/// A PDF is drawn page by page, zoomable, and downloaded from the preview.
/// A Word or PowerPoint file cannot be drawn here, so the viewer says so and
/// its Download button hands the file to the device, which is where it can
/// actually be read.
///
/// The bucket is private and the URLs Firestore holds are identifiers, not
/// links: see [StoredFile.url]. Every open therefore goes through the
/// `document-url` function, which decides whether this reader is entitled to
/// this file before it signs anything. That happens before the viewer opens,
/// so a document the reader may not see never gets as far as a blank viewer.
///
/// That means opening a document can legitimately FAIL, in ways a public
/// bucket never did: the reader may have been removed from the panel, their
/// account deactivated, or their session expired. Those are reported here
/// rather than silently opening a broken viewer, and none of them are
/// phrased as "try again": retrying cannot change any of them.
///
/// [externalOpener] replaces the platform launcher for this one call (the
/// title defense screen exposes it for its own tests).
///
/// Returns true when a URL was obtained and the viewer was opened.
Future<bool> openStoredDocument(
  BuildContext context,
  WidgetRef ref,
  String storagePath, {
  String? label,
  ExternalOpener? externalOpener,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);

  if (storagePath.trim().isEmpty) {
    _say(
      messenger,
      'This entry does not record where its file is stored, so '
      'it cannot be opened.',
    );
    return false;
  }

  try {
    final url = await ref.read(storageServiceProvider).signedUrl(storagePath);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _say(messenger, 'That ${label ?? 'document'} link is not valid.');
      return false;
    }
    if (!context.mounted) return false;
    // Not awaited: the viewer is a screen the reader leaves when they like,
    // and the caller's own button should not stay busy behind it.
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => StoredDocumentViewer(
        url: uri,
        storagePath: storagePath,
        label: label,
        externalOpener: externalOpener,
      ),
    );
    return true;
  } on StorageFailure catch (e) {
    _say(messenger, '${e.message} [${e.code}]');
    return false;
  }
}

void _say(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}

/// The extension of a storage path, lower-cased, without the dot.
String _extensionOf(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

/// A name to save the file under. The storage path never carries the
/// person's own filename (see [StoragePaths]), so the label stands in for it;
/// the extension comes from the path so the saved file opens correctly.
String downloadNameFor(String storagePath, String? label) {
  final ext = _extensionOf(storagePath);
  final cleaned = (label ?? 'document')
      .replaceAll(RegExp(r'[^A-Za-z0-9 _.\-]'), '')
      .trim();
  final base = cleaned.isEmpty ? 'document' : cleaned;
  if (ext.isEmpty || base.toLowerCase().endsWith('.$ext')) return base;
  return '$base.$ext';
}

/// The full-screen viewer a stored document opens in: a title, a Download
/// button, and the document below. Laid out like the form viewer, so a
/// manuscript and a form behave the same way.
class StoredDocumentViewer extends ConsumerStatefulWidget {
  const StoredDocumentViewer({
    super.key,
    required this.url,
    required this.storagePath,
    this.label,
    this.externalOpener,
  });

  final Uri url;
  final String storagePath;
  final String? label;
  final ExternalOpener? externalOpener;

  @override
  ConsumerState<StoredDocumentViewer> createState() =>
      _StoredDocumentViewerState();
}

class _StoredDocumentViewerState extends ConsumerState<StoredDocumentViewer> {
  late final String _ext = _extensionOf(widget.storagePath);
  bool get _isPdf => _ext == 'pdf';

  late final String _filename = downloadNameFor(
    widget.storagePath,
    widget.label,
  );

  // Read once, shared by the preview and the download, so the copy the
  // reader saves is the one they read. Only a PDF is read here.
  late final Future<Uint8List>? _bytes = _isPdf
      ? ref.read(storedDocumentBytesProvider)(widget.url)
      : null;

  bool _saving = false;
  String? _error;

  // A method tear-off, so the preview gets the same function on every
  // rebuild; a fresh closure would make it draw the pages again each time
  // the Download button redraws.
  Future<Uint8List> _source() => _bytes!;

  Future<void> _download() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isPdf) {
        await ref.read(pdfSharerProvider)(await _bytes!, _filename);
      } else {
        final ExternalOpener open =
            widget.externalOpener ?? ref.read(externalOpenerProvider);
        final opened = await open(widget.url);
        if (!opened && mounted) {
          setState(() => _error = 'Could not open that file.');
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _isPdf
              ? 'Could not save a copy.'
              : 'Could not open that file.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(formPreviewBuilderProvider);
    final text = Theme.of(context).textTheme;
    return Dialog.fullscreen(
      key: const Key('documentViewer'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTokens.xs,
              AppTokens.xs,
              AppTokens.md,
              AppTokens.xs,
            ),
            child: Row(
              children: [
                IconButton(
                  key: const Key('closeDocumentViewer'),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: AppTokens.xs),
                Expanded(
                  child: Text(
                    widget.label ?? _filename,
                    style: text.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_error != null) ...[
                  Flexible(
                    child: Text(
                      _error!,
                      key: const Key('documentViewerError'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.sm),
                ],
                OutlinedButton.icon(
                  key: const Key('downloadDocument'),
                  onPressed: _saving ? null : _download,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Download'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isPdf
                ? preview(_source)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTokens.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.insert_drive_file_outlined,
                            size: 48,
                          ),
                          const SizedBox(height: AppTokens.sm),
                          Text(
                            _ext.isEmpty
                                ? 'This file cannot be previewed here.'
                                : '.${_ext.toUpperCase()} files cannot be '
                                      'previewed here.',
                            key: const Key('noPreview'),
                            style: text.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: AppTokens.xs),
                          Text(
                            'Download it to read it on your device.',
                            style: text.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
