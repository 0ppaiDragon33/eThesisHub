import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// Optional: pick one of the person's saved copies of [formId] from My files
/// to send along with a request. Lists only copies of that form, and draws
/// nothing when they have none. The picked id is null for "None".
class FormCopyPicker extends ConsumerWidget {
  const FormCopyPicker({
    super.key,
    required this.formId,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String formId;
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final copies =
        ref.watch(myFormCopiesProvider(formId)).valueOrNull ?? const <FormCopy>[];
    if (copies.isEmpty) return const SizedBox.shrink();
    // A pick that was deleted since falls back to none, which the dropdown
    // would otherwise assert on.
    final shown = copies.any((c) => c.id == value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          key: Key('${formId}CopyPicker'),
          initialValue: shown,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None')),
            for (final c in copies)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text(c.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
        const SizedBox(height: AppTokens.xs),
        Text(
          'Copies saved in My files.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
