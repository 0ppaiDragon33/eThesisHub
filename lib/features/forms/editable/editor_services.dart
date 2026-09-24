import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// True while the open form editor holds edits that are not saved. Set by
/// the editor; read by [confirmLeaveFormEditor] when its route is left.
final unsavedFormEditsProvider = StateProvider<bool>((ref) => false);

typedef PdfSharer = Future<void> Function(Uint8List bytes, String filename);

/// Hands a finished PDF to the platform: the share sheet on a phone, a
/// download on the web. A provider so a test can capture the bytes instead.
final pdfSharerProvider = Provider<PdfSharer>(
  (ref) => (bytes, filename) async {
    await Printing.sharePdf(bytes: bytes, filename: filename);
  },
);

typedef FormPreviewBuilder =
    Widget Function(Key key, Future<Uint8List> Function() build);

/// The live preview of the printed form. Rasterising a PDF needs the
/// platform, so widget tests replace this with a stand-in.
final formPreviewBuilderProvider = Provider<FormPreviewBuilder>(
  (ref) =>
      (key, build) => PdfPreview(
        key: key,
        build: (_) => build(),
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        onError: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'The preview could not be drawn: $error',
              key: const Key('previewError'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
);

/// The editor route's `onExit`. It runs however the route is left: the
/// top-bar arrow and the Android back (both `pop()`), browser back, or a
/// sidebar `go()`. With unsaved edits it asks first; otherwise it lets the
/// reader go.
Future<bool> confirmLeaveFormEditor(
  BuildContext context,
  GoRouterState state,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(unsavedFormEditsProvider)) return true;
  // A redirect can also drive onExit: sign-out (-> /login) or deactivation
  // (-> /deactivated). Asking "Leave without saving?" there would let
  // "Keep editing" veto the redirect, stranding a signed-out reader on a
  // copy that can no longer load. Let those through without asking.
  final signedOut = container.read(signedInUidProvider) == null;
  final deactivated =
      container.read(currentUserProvider).valueOrNull?.active == false;
  if (signedOut || deactivated) {
    container.read(unsavedFormEditsProvider.notifier).state = false;
    return true;
  }
  final leave = await confirmAction(
    context,
    title: 'Leave without saving?',
    message: 'Your edits to this copy have not been saved.',
    confirmLabel: 'Leave',
    cancelLabel: 'Keep editing',
    confirmKey: const Key('confirmLeaveEditor'),
  );
  if (leave) container.read(unsavedFormEditsProvider.notifier).state = false;
  return leave;
}
