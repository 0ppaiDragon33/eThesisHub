import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/editable/form_template.dart';
import 'package:ethesishub/features/forms/editable/form_templates.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

/// At and above this width the fields and the preview sit side by side;
/// below it an Edit / Preview switch shows one at a time. The same point
/// `SplitColumns` stops stacking at.
const double kEditorSideBySideFrom = 860;

/// How long typing must pause before the preview is rebuilt: rendering a
/// PDF on every keystroke would stutter on a phone.
const Duration kPreviewDebounce = Duration(milliseconds: 400);

enum _Pane { edit, preview }

/// Edits one saved copy of a form: every block of its text as a field,
/// beside a live preview of the printed form.
class FormCopyEditorScreen extends ConsumerStatefulWidget {
  const FormCopyEditorScreen({
    super.key,
    required this.formId,
    required this.copyId,
  });

  final String formId;
  final String copyId;

  @override
  ConsumerState<FormCopyEditorScreen> createState() =>
      _FormCopyEditorScreenState();
}

class _FormCopyEditorScreenState extends ConsumerState<FormCopyEditorScreen> {
  final _controllers = <String, TextEditingController>{};
  final _lastTexts = <String, String>{};
  String? _loadedCopyId;
  bool _dirty = false;
  bool _saving = false;
  Object? _error;
  Map<String, String> _previewOverrides = const {};
  int _previewVersion = 0;
  Timer? _debounce;
  _Pane _pane = _Pane.edit;

  @override
  void initState() {
    super.initState();
    // A flag left over from an editor torn down without leaving through its
    // route (a sign-out, say) must not make this one ask on the way out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_dirty) {
        ref.read(unsavedFormEditsProvider.notifier).state = false;
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values() =>
      {for (final e in _controllers.entries) e.key: e.value.text};

  /// Fills the fields once per copy. Later snapshots of the same copy (its
  /// own save coming back) must not overwrite what is being typed.
  void _load(FormTemplate template, FormCopy copy) {
    if (_loadedCopyId == copy.id) return;
    _loadedCopyId = copy.id;
    final text = FormText(template, copy.overrides);
    for (final b in template.blocks) {
      final c = TextEditingController(text: text.of(b.id));
      _lastTexts[b.id] = c.text;
      c.addListener(() => _onChanged(template, b.id, c));
      _controllers[b.id] = c;
    }
    _previewOverrides = template.overridesFrom(_values());
  }

  void _onChanged(
      FormTemplate template, String id, TextEditingController c) {
    // A controller also notifies on cursor and selection moves; only a
    // change of text is an edit.
    if (c.text == _lastTexts[id]) return;
    _lastTexts[id] = c.text;
    if (!_dirty) {
      setState(() => _dirty = true);
      ref.read(unsavedFormEditsProvider.notifier).state = true;
    }
    _debounce?.cancel();
    _debounce = Timer(kPreviewDebounce, () {
      if (!mounted) return;
      setState(() {
        _previewOverrides = template.overridesFrom(_values());
        _previewVersion++;
      });
    });
  }

  Future<void> _save(FormTemplate template, String uid) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(formCopyRepositoryProvider).saveOverrides(
            uid: uid,
            copyId: widget.copyId,
            overrides: template.overridesFrom(_values()),
          );
      if (!mounted) return;
      setState(() => _dirty = false);
      ref.read(unsavedFormEditsProvider.notifier).state = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _download(FormTemplate template, FormCopy copy) async {
    try {
      final bytes =
          await buildFormPdf(template, template.overridesFrom(_values()));
      await ref.read(pdfSharerProvider)(bytes, '${_fileSafe(copy.name)}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not make the PDF: $e')));
    }
  }

  /// A file name any platform accepts: letters, digits, spaces, `_`, `-`.
  static String _fileSafe(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '_').trim();

  Future<void> _resetAll(FormTemplate template) async {
    final reset = await confirmAction(
      context,
      title: 'Reset every field?',
      message: 'All your edits in this copy go back to the form\'s original '
          'wording. Nothing is saved until you press Save.',
      confirmLabel: 'Reset',
      confirmKey: const Key('confirmResetAll'),
    );
    if (!reset) return;
    for (final b in template.blocks) {
      _controllers[b.id]!.text = b.defaultText;
    }
  }

  @override
  Widget build(BuildContext context) {
    final template = templateFor(widget.formId);
    if (template == null) {
      return const PageShell(children: [
        EmptyState(
          key: Key('formUnavailable'),
          icon: Icons.description_outlined,
          title: 'This form is no longer available',
          message: 'It may have been removed in an update.',
        ),
      ]);
    }

    final uid = ref.watch(signedInUidProvider);
    return ref.watch(formCopyProvider(widget.copyId)).when(
          loading: () => const PageShell(
            children: [LoadingState.page(label: 'Opening your copy…')],
          ),
          error: (e, _) => PageShell(children: [
            ErrorState(error: e, message: 'Could not open this copy.'),
          ]),
          data: (copy) {
            if (copy == null || copy.formId != widget.formId) {
              return const PageShell(children: [
                EmptyState(
                  key: Key('copyMissing'),
                  icon: Icons.description_outlined,
                  title: 'This copy no longer exists',
                  message: 'It may have been deleted.',
                ),
              ]);
            }
            _load(template, copy);
            return _editor(template, copy, uid);
          },
        );
  }

  Widget _editor(FormTemplate template, FormCopy copy, String? uid) {
    final fields = Column(
      key: const Key('editorFields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in template.blocks)
          _BlockField(
            block: b,
            controller: _controllers[b.id]!,
            onReset: () => _controllers[b.id]!.text = b.defaultText,
          ),
      ],
    );

    // Captured, so the preview renders exactly the text it was keyed for.
    final overrides = _previewOverrides;
    final preview = SizedBox(
      height: 760,
      child: ref.watch(formPreviewBuilderProvider)(
        ValueKey(_previewVersion),
        () => buildFormPdf(template, overrides),
      ),
    );

    return PageShell(
      maxWidth: AppTokens.measureWide,
      kicker: template.title,
      title: copy.name,
      subtitle: _dirty ? 'Unsaved changes' : 'All changes saved',
      actions: [
        FilledButton.icon(
          key: const Key('saveCopy'),
          onPressed: (!_dirty || _saving || uid == null)
              ? null
              : () => _save(template, uid),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'Saving…' : 'Save'),
        ),
        OutlinedButton.icon(
          key: const Key('downloadCopy'),
          onPressed: () => _download(template, copy),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download PDF'),
        ),
        TextButton(
          key: const Key('resetAllCopy'),
          onPressed: () => _resetAll(template),
          child: const Text('Reset all'),
        ),
      ],
      children: [
        if (_error != null) ...[
          ErrorState(
            key: const Key('saveError'),
            error: _error,
            message: 'Could not save this copy. Your edits are still here.',
          ),
          const Gap.md(),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= kEditorSideBySideFrom) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: fields),
                  const SizedBox(width: AppTokens.lg),
                  Expanded(child: preview),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<_Pane>(
                  key: const Key('editorPaneSwitch'),
                  segments: const [
                    ButtonSegment(
                      value: _Pane.edit,
                      label: Text('Edit'),
                      icon: Icon(Icons.edit_outlined),
                    ),
                    ButtonSegment(
                      value: _Pane.preview,
                      label: Text('Preview'),
                      icon: Icon(Icons.visibility_outlined),
                    ),
                  ],
                  selected: {_pane},
                  onSelectionChanged: (s) => setState(() => _pane = s.first),
                ),
                const Gap.md(),
                if (_pane == _Pane.edit) fields else preview,
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One block of the form's text: its label, its field, and a button that
/// puts back the form's own wording.
class _BlockField extends StatelessWidget {
  const _BlockField({
    required this.block,
    required this.controller,
    required this.onReset,
  });

  final FormBlock block;
  final TextEditingController controller;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return FormRow(
      label: block.label,
      hint: block.kind == BlockKind.blank
          ? 'Leave empty to print a blank line.'
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: Key('field-${block.id}'),
              controller: controller,
              minLines: block.multiline ? 3 : 1,
              maxLines: block.multiline ? 8 : 1,
            ),
          ),
          IconButton(
            key: Key('resetField-${block.id}'),
            tooltip: 'Back to the form\'s wording',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: onReset,
          ),
        ],
      ),
    );
  }
}
