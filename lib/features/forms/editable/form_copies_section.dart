import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/features/forms/editable/name_dialog.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// A form card's own copies: a New copy button, and the person's saved
/// copies of this form with Open, Rename and Delete.
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

  void _open(BuildContext context, String copyId) =>
      context.push('/forms/$formId/copies/$copyId');

  void _report(BuildContext context, String what, Object error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Could not $what: $error')));
  }

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
      if (context.mounted) _open(context, id);
    } catch (e) {
      if (context.mounted) _report(context, 'create the copy', e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    FormCopy copy,
  ) async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final name = await promptForName(
      context,
      title: 'Rename this copy',
      initial: copy.name,
      confirmLabel: 'Rename',
    );
    if (name == null || name == copy.name) return;
    try {
      await ref
          .read(formCopyRepositoryProvider)
          .rename(uid: uid, copyId: copy.id, name: name);
    } catch (e) {
      if (context.mounted) _report(context, 'rename the copy', e);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    FormCopy copy,
  ) async {
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Delete this copy?',
      message: '"${copy.name}" will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      confirmKey: const Key('confirmDeleteCopy'),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(formCopyRepositoryProvider)
          .delete(uid: uid, copyId: copy.id);
    } catch (e) {
      if (context.mounted) _report(context, 'delete the copy', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final copiesAsync = ref.watch(myFormCopiesProvider(formId));
    final copies = copiesAsync.valueOrNull ?? const [];
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
        if (copiesAsync.hasError) ...[
          const SizedBox(height: AppTokens.md - 4),
          Text(
            'Could not load your copies.',
            key: Key('${formId}CopiesError'),
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
        if (copies.isNotEmpty) ...[
          const SizedBox(height: AppTokens.md - 4),
          Text(
            'My copies (${copies.length})',
            key: Key('${formId}MyCopies'),
            style: text.labelLarge,
          ),
          for (final copy in copies)
            _CopyRow(
              copy: copy,
              onOpen: () => _open(context, copy.id),
              onRename: () => _rename(context, ref, copy),
              onDelete: () => _delete(context, ref, copy),
            ),
        ],
      ],
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.copy,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final FormCopy copy;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final edited = copy.updatedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.xs),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  copy.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge,
                ),
                Text(
                  edited == null
                      ? 'Just now'
                      : 'Last edited: ${Dates.relative(edited)}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            key: Key('openCopy-${copy.id}'),
            onPressed: onOpen,
            child: const Text('Open'),
          ),
          IconButton(
            key: Key('renameCopy-${copy.id}'),
            tooltip: 'Rename',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: onRename,
          ),
          IconButton(
            key: Key('deleteCopy-${copy.id}'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
