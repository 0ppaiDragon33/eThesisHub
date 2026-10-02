import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/features/forms/editable/name_dialog.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// A form card's New copy button.
///
/// A copy is named, opened in the editor, and saved in My files. The Forms
/// page does not list copies: they are opened, renamed and deleted from My
/// files, and picked from there when a request asks for a form.
class FormCopiesSection extends ConsumerStatefulWidget {
  const FormCopiesSection({
    super.key,
    required this.formId,
    required this.defaultName,
  });

  final String formId;

  /// What the name prompt suggests for a new copy.
  final String defaultName;

  @override
  ConsumerState<FormCopiesSection> createState() => _FormCopiesSectionState();
}

class _FormCopiesSectionState extends ConsumerState<FormCopiesSection> {
  bool _creating = false;

  String get formId => widget.formId;

  Future<void> _newCopy(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Name this copy',
      initial: widget.defaultName,
      confirmLabel: 'Create',
    );
    if (name == null) return;
    setState(() => _creating = true);
    try {
      final id = await ref
          .read(formCopyRepositoryProvider)
          .create(uid: uid, formId: formId, name: name);
      if (context.mounted) context.push('/forms/$formId/copies/$id');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create the copy: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not only read in _newCopy: nothing else here keeps the sign-in
    // state loaded, and a read before it resolves finds no one signed in.
    ref.watch(authStateProvider);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          key: Key('${formId}NewCopy'),
          onPressed: _creating ? null : () => _newCopy(context, ref),
          icon: const Icon(Icons.edit_note_rounded, size: 18),
          label: const Text('New copy'),
        ),
        const SizedBox(height: AppTokens.xs),
        Text('Saved in My files.', style: text.bodySmall),
      ],
    );
  }
}
