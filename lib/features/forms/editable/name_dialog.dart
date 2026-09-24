import 'package:flutter/material.dart';

import 'package:ethesishub/data/repositories/form_copy_repository.dart';

/// Asks for a copy's name. Returns it trimmed, or null when cancelled.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  required String initial,
  required String confirmLabel,
  int maxLength = kFormCopyNameMax,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      initial: initial,
      confirmLabel: confirmLabel,
      maxLength: maxLength,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    required this.maxLength,
  });

  final String title;
  final String initial;
  final String confirmLabel;
  final int maxLength;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid {
    final name = _controller.text.trim();
    return name.isNotEmpty && name.length <= widget.maxLength;
  }

  void _submit() {
    if (_valid) Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('copyNameField'),
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('copyNameConfirm'),
          onPressed: _valid ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
