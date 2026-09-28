import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/providers/change_request_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Coordinator's and the Dean's change-of-adviser / change-of-title
/// queue: every open request at their step in the chain, with the change it
/// asks for and the reasons behind it.
///
/// [asDean] selects the provider ([deanChangeRequestsProvider] over
/// [coordinatorChangeRequestsProvider]) and which actions the row offers —
/// Approve/Return for the Dean (the Dean's approve applies the thesis change
/// in one batch via `approveAsDean`), Recommend/Return for the Coordinator
/// (both a plain `respond`). A Return always asks for a reason first, the
/// same two-step pattern as [ChangeRequestInbox] (start decline / confirm).
///
/// `respond`/`approveAsDean` throw `StateError` when the request has moved
/// on since this widget last read it (another reader's answer, or a
/// resubmission) — surfaced as a plain human message, same as
/// [ChangeRequestInbox].
class ChangeRequestQueue extends ConsumerStatefulWidget {
  const ChangeRequestQueue({super.key, required this.asDean});

  final bool asDean;

  @override
  ConsumerState<ChangeRequestQueue> createState() => _ChangeRequestQueueState();
}

class _ChangeRequestQueueState extends ConsumerState<ChangeRequestQueue> {
  final _reason = TextEditingController();
  String? _returningKey;
  String? _error;
  final Set<String> _busy = {};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _key(String thesisId, ChangeRequestType type) =>
      '$thesisId-${type.value}';

  Future<void> _act(
    String thesisId,
    ChangeRequestType type,
    Future<void> Function() action,
  ) async {
    final key = _key(thesisId, type);
    if (_busy.contains(key)) return; // guards against a double tap

    setState(() {
      _busy.add(key);
      _error = null;
    });

    try {
      await action();
      if (mounted) {
        setState(() {
          _returningKey = null;
          _reason.clear();
        });
      }
    } on StateError catch (_) {
      // Reachable in normal use: another reader's answer already advanced
      // the stage, or the request was resubmitted, while this tab sat open.
      if (mounted) {
        setState(() => _error = 'This request has already been updated.');
      }
    } on FirebaseException catch (_) {
      if (mounted) setState(() => _error = 'Could not record your response.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not record your response.');
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _advance(String thesisId, ChangeRequestType type) {
    final repo = ref.read(changeRequestRepositoryProvider);
    return _act(
      thesisId,
      type,
      () => widget.asDean
          ? repo.approveAsDean(thesisId: thesisId, type: type)
          : repo.respond(
              thesisId: thesisId,
              type: type,
              role: 'coordinator',
              accept: true,
            ),
    );
  }

  Future<void> _return(String thesisId, ChangeRequestType type) {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Please give a reason for returning.');
      return Future.value();
    }
    final repo = ref.read(changeRequestRepositoryProvider);
    return _act(
      thesisId,
      type,
      () => repo.respond(
        thesisId: thesisId,
        type: type,
        role: widget.asDean ? 'dean' : 'coordinator',
        accept: false,
        reason: _reason.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(
      widget.asDean
          ? deanChangeRequestsProvider
          : coordinatorChangeRequestsProvider,
    );

    return KeyedSubtree(
      key: const Key('changeRequestQueue'),
      child: requestsAsync.when(
        loading: () => const Panel(
          title: 'Change requests',
          icon: Icons.rule_folder_outlined,
          child: LoadingState(label: 'Loading change requests…'),
        ),
        error: (e, _) => Panel(
          title: 'Change requests',
          icon: Icons.rule_folder_outlined,
          child: ErrorState(
            error: e,
            message: 'Could not load the change-request queue.',
          ),
        ),
        data: (items) => Panel(
          title: 'Change requests',
          icon: Icons.rule_folder_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.rule_folder_outlined,
                  title: 'Nothing waiting',
                  message:
                      'A change of adviser or title appears here once it '
                      'reaches your step.',
                ),
              if (_error != null) ...[
                ErrorState(
                  key: const Key('changeRequestQueueError'),
                  message: _error!,
                ),
                const Gap.md(),
              ],
              for (var i = 0; i < items.length; i++) ...[
                _QueueRow(
                  asDean: widget.asDean,
                  thesisId: items[i].thesisId,
                  request: items[i].request,
                  returning:
                      _returningKey ==
                      _key(items[i].thesisId, items[i].request.type),
                  busy: _busy.contains(
                    _key(items[i].thesisId, items[i].request.type),
                  ),
                  reason: _reason,
                  onAdvance: () =>
                      _advance(items[i].thesisId, items[i].request.type),
                  onStartReturn: () => setState(() {
                    _returningKey = _key(
                      items[i].thesisId,
                      items[i].request.type,
                    );
                    _error = null;
                  }),
                  onCancelReturn: () => setState(() {
                    _returningKey = null;
                    _reason.clear();
                  }),
                  onConfirmReturn: () =>
                      _return(items[i].thesisId, items[i].request.type),
                ),
                if (i < items.length - 1) const Gap.md(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One request at this reader's step: the thesis, the change it asks for,
/// the reasons, and the two actions.
class _QueueRow extends ConsumerWidget {
  const _QueueRow({
    required this.asDean,
    required this.thesisId,
    required this.request,
    required this.returning,
    required this.busy,
    required this.reason,
    required this.onAdvance,
    required this.onStartReturn,
    required this.onCancelReturn,
    required this.onConfirmReturn,
  });

  final bool asDean;
  final String thesisId;
  final ChangeRequest request;
  final bool returning;
  final bool busy;
  final TextEditingController reason;
  final VoidCallback onAdvance;
  final VoidCallback onStartReturn;
  final VoidCallback onCancelReturn;
  final VoidCallback onConfirmReturn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final thesis = ref.watch(thesisByIdProvider(thesisId));
    final title = request.type == ChangeRequestType.adviser
        ? 'Change of adviser'
        : 'Change of title';
    final fromTo = request.type == ChangeRequestType.adviser
        ? '${request.formerAdviserName ?? 'the former adviser'} → '
              '${request.newAdviserName ?? 'the new adviser'}'
        : '${thesis.valueOrNull?.workingTitle ?? '…'} → '
              '${request.newTitle ?? ''}';
    final advanceLabel = asDean ? 'Approve' : 'Recommend';
    final advanceKey = asDean
        ? 'approveChangeRequest-$thesisId-${request.type.value}'
        : 'recommendChangeRequest-$thesisId-${request.type.value}';
    final returnKey = 'returnChangeRequest-$thesisId-${request.type.value}';

    return Panel(
      key: Key('changeRequestQueueRow-$thesisId-${request.type.value}'),
      emphasis: !returning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(thesis.valueOrNull?.workingTitle ?? '…', style: text.titleLarge),
          const Gap.sm(),
          Text(title, style: text.titleSmall),
          const SizedBox(height: 2),
          Text(fromTo, style: text.bodyMedium),
          const Gap.sm(),
          Text('Reasons: ${request.reasons}', style: text.bodySmall),
          const Gap.md(),
          if (returning) ...[
            FormRow(
              label: 'Reason for returning',
              hint: 'The group will see this.',
              child: TextField(
                key: const Key('changeRequestReturnReason'),
                controller: reason,
                maxLines: 3,
                minLines: 2,
                autofocus: true,
              ),
            ),
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              children: [
                FilledButton(
                  key: Key(returnKey),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tone.returned.color(context),
                  ),
                  onPressed: busy ? null : onConfirmReturn,
                  child: const Text('Confirm return'),
                ),
                TextButton(
                  onPressed: busy ? null : onCancelReturn,
                  child: const Text('Keep the request'),
                ),
              ],
            ),
          ] else
            Wrap(
              spacing: AppTokens.sm,
              runSpacing: AppTokens.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  key: Key(advanceKey),
                  onPressed: busy ? null : onAdvance,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(advanceLabel),
                ),
                OutlinedButton(
                  key: Key(
                    'startReturnChangeRequest-$thesisId-${request.type.value}',
                  ),
                  onPressed: busy ? null : onStartReturn,
                  child: const Text('Return'),
                ),
                if (busy) Text('Recording your answer…', style: text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
