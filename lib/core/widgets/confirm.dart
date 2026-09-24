import 'package:flutter/material.dart';

/// A yes/no confirmation before an action that is hard to take back.
///
/// Returns true only when the reader picks the confirming button. Kept in one
/// place so every "are you sure?" reads and behaves the same — the same
/// button order, the same dismissal-is-no default — rather than each screen
/// rolling its own `showDialog<bool>`.
///
/// [confirmKey] lets a test drive the confirming button; [cancelLabel]
/// defaults to a plain "Cancel" but is worth overriding with the specific
/// "leave it as it is" phrasing where there is one ("Stay signed in").
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  Key? confirmKey,
}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return yes == true;
}
