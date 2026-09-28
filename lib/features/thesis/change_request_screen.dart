import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/change_request_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The student leader's form for requesting a change of adviser (Form 4a) or
/// a change of the approved title (Form 4b), routed through the sign-off
/// chain (spec 2026-09-25). One screen, two modes, chosen by [type].
///
/// Modelled on `schedule_defence_screen.dart`'s shape: `_framed`, busy/error
/// state, and the same `ArgumentError`/`FirebaseException` handling.
class ChangeRequestScreen extends ConsumerStatefulWidget {
  const ChangeRequestScreen({
    super.key,
    required this.thesisId,
    required this.type,
    this.prefill,
  });

  final String thesisId;
  final ChangeRequestType type;

  /// A previously returned request to prefill from, reached from the
  /// tracker's "Edit and resubmit" button. Null for a fresh request.
  final ChangeRequest? prefill;

  @override
  ConsumerState<ChangeRequestScreen> createState() =>
      _ChangeRequestScreenState();
}

class _ChangeRequestScreenState extends ConsumerState<ChangeRequestScreen> {
  final _reasonsController = TextEditingController();
  final _titleController = TextEditingController();
  String? _newAdviserUid;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final prefill = widget.prefill;
    if (prefill != null) {
      _reasonsController.text = prefill.reasons;
      _titleController.text = prefill.newTitle ?? '';
      _newAdviserUid = prefill.newAdviserUid;
    }
  }

  @override
  void dispose() {
    _reasonsController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit(Thesis thesis) async {
    if (_busy) return;

    final reasons = _reasonsController.text.trim();
    if (reasons.isEmpty) {
      setState(() => _error = 'Give a reason for this request.');
      return;
    }

    if (widget.type == ChangeRequestType.title) {
      if (_titleController.text.trim().isEmpty) {
        setState(() => _error = 'Give the new title.');
        return;
      }
    } else {
      if (_newAdviserUid == null) {
        setState(() => _error = 'Choose the new adviser.');
        return;
      }
      if (_newAdviserUid == thesis.adviserUid) {
        setState(
          () => _error =
              'The new adviser must be different from the current adviser.',
        );
        return;
      }
      // The former adviser this request records: on a fresh request this is
      // the thesis's current adviser; on a resubmit it is whoever a
      // previously returned request already named, which may since have
      // stopped being the thesis's current adviser.
      final formerAdviserUid =
          widget.prefill?.formerAdviserUid ?? thesis.adviserUid;
      if (_newAdviserUid == formerAdviserUid) {
        setState(
          () => _error =
              'The new adviser is the same as the former adviser — this '
              'request would not change anything.',
        );
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (widget.type == ChangeRequestType.title) {
        await ref
            .read(changeRequestRepositoryProvider)
            .submitTitleChange(
              thesis: thesis,
              newTitle: _titleController.text.trim(),
              reasons: reasons,
            );
      } else {
        final directory =
            ref.read(allDirectoryProvider).valueOrNull ?? const [];
        final newAdviser = directory
            .where((f) => f.uid == _newAdviserUid)
            .firstOrNull;
        if (newAdviser == null) {
          setState(
            () => _error =
                'That adviser no longer resolves in the faculty directory. '
                'Please choose again.',
          );
          return;
        }
        final formerAdviserName =
            widget.prefill?.formerAdviserName ??
            directory
                .where((f) => f.uid == thesis.adviserUid)
                .firstOrNull
                ?.fullName ??
            '';
        await ref
            .read(changeRequestRepositoryProvider)
            .submitAdviserChange(
              thesis: thesis,
              newAdviser: newAdviser,
              formerAdviserName: formerAdviserName,
              reasons: reasons,
            );
      }
      if (mounted) context.pop();
    } on ArgumentError catch (e) {
      // The repository's own message — the one failure a leader can act on
      // directly.
      if (mounted) setState(() => _error = e.message.toString());
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'permission-denied'
              ? 'You do not have permission to submit this request '
                    '[permission-denied].'
              : 'Could not submit this request. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not submit this request. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Wraps every non-form state in the same frame the form uses. The shell
  /// supplies the Scaffold/AppBar for every signed-in route.
  Widget _framed(List<Widget> children) => PageShell(children: children);

  DropdownButtonFormField<String> _adviserPicker(
    Thesis thesis,
    List<FacultyDirectoryEntry> directory,
  ) {
    // Honours nominableAsAdviser (spec D32/faculty-directory convention) and
    // excludes the current adviser — requesting a "change" to the same
    // person is never offered as an option at all.
    final offerable = directory
        .where((f) => f.nominableAsAdviser)
        .where((f) => f.uid != thesis.adviserUid)
        .toList();
    // Same stale-value fallback as nominate_screen.dart's picker: a previous
    // pick can vanish from the live directory stream between selection and
    // submit.
    final displayValue = offerable.any((f) => f.uid == _newAdviserUid)
        ? _newAdviserUid
        : null;
    return DropdownButtonFormField<String>(
      key: const Key('newAdviserPicker'),
      initialValue: displayValue,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'New adviser'),
      items: [
        for (final f in offerable)
          DropdownMenuItem(
            value: f.uid,
            child: Text(f.fullName, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() => _newAdviserUid = v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thesisAsync = ref.watch(thesisByIdProvider(widget.thesisId));

    if (thesisAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading thesis…')]);
    }
    if (thesisAsync.hasError) {
      return _framed([
        ErrorState(
          error: thesisAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }
    final thesis = thesisAsync.valueOrNull;
    if (thesis == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Thesis not found',
          message:
              'This thesis no longer exists, or it belongs to '
              'another group.',
        ),
      ]);
    }

    final isAdviser = widget.type == ChangeRequestType.adviser;
    final directoryAsync = ref.watch(allDirectoryProvider);

    return KeyedSubtree(
      key: const Key('changeRequestScreen'),
      child: PageShell(
        kicker: 'My thesis',
        title: isAdviser
            ? 'Request a change of adviser'
            : 'Request a change of title',
        subtitle: thesis.workingTitle,
        children: [
          Panel(
            title: isAdviser ? 'New adviser' : 'New title',
            icon: isAdviser
                ? Icons.switch_account_outlined
                : Icons.edit_document,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isAdviser)
                  FormRow(
                    label: 'New adviser',
                    child: directoryAsync.when(
                      loading: () => const LoadingState(),
                      error: (e, _) => ErrorState(
                        error: e,
                        message: 'Could not load the faculty directory.',
                      ),
                      data: (directory) => _adviserPicker(thesis, directory),
                    ),
                  )
                else
                  FormRow(
                    label: 'New title',
                    child: TextField(
                      key: const Key('newTitleField'),
                      controller: _titleController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'The proposed new working title',
                      ),
                    ),
                  ),
                FormRow(
                  label: 'Reasons',
                  child: TextField(
                    key: const Key('changeReasons'),
                    controller: _reasonsController,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Why is this change needed?',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap.lg(),
          if (_error != null) ...[
            ErrorState(key: const Key('error'), message: _error!),
            const Gap.md(),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const Key('submitChangeRequest'),
              onPressed: _busy ? null : () => _submit(thesis),
              icon: const Icon(Icons.send_outlined, size: 18),
              label: Text(_busy ? 'Submitting…' : 'Submit'),
            ),
          ),
        ],
      ),
    );
  }
}
