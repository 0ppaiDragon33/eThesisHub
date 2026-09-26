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

/// Lets a faculty member accept or decline a change-of-adviser / change-of-
/// title request addressed to a role they hold, mounted as a section on
/// [NominationInboxScreen] below the nomination inbox.
///
/// `mySignoffRequestsProvider` already scopes its query to the signed-in
/// uid's own `awaitingUids` entries server-side, so every row here is
/// correctly targeted -- no client-side cross-filter needed.
///
/// `respond` throws `StateError` when the request has moved on since this
/// widget last read it (a stale tab, or a co-signer's answer already
/// resolved the step) -- surfaced here as a plain human message, the same
/// pattern as `NominationInboxScreen._respond`.
class ChangeRequestInbox extends ConsumerStatefulWidget {
  const ChangeRequestInbox({super.key});

  @override
  ConsumerState<ChangeRequestInbox> createState() => _ChangeRequestInboxState();
}

class _ChangeRequestInboxState extends ConsumerState<ChangeRequestInbox> {
  final _reason = TextEditingController();
  String? _decliningKey;
  String? _error;
  final Set<String> _busy = {};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String _key(String thesisId, String role) => '$thesisId-$role';

  Future<void> _respond(
    String thesisId,
    ChangeRequestType type,
    String role,
    bool accept,
  ) async {
    final key = _key(thesisId, role);
    if (_busy.contains(key)) return; // guards against a double tap

    if (!accept && _reason.text.trim().isEmpty) {
      setState(() => _error = 'Please give a reason for declining.');
      return;
    }

    setState(() {
      _busy.add(key);
      _error = null;
    });

    try {
      await ref
          .read(changeRequestRepositoryProvider)
          .respond(
            thesisId: thesisId,
            type: type,
            role: role,
            accept: accept,
            reason: accept ? null : _reason.text.trim(),
          );
      if (mounted) {
        setState(() {
          _decliningKey = null;
          _reason.clear();
        });
      }
    } on StateError catch (_) {
      // Reachable in normal use: a co-signer's accept already advanced the
      // stage, or the request was resubmitted, while this tab sat open.
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

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(mySignoffRequestsProvider);

    return KeyedSubtree(
      key: const Key('changeRequestInbox'),
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
            message: 'Could not load your change requests.',
          ),
        ),
        data: (visible) => Panel(
          title: 'Change requests',
          icon: Icons.rule_folder_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (visible.isEmpty)
                const EmptyState(
                  icon: Icons.rule_folder_outlined,
                  title: 'No change requests waiting',
                  message:
                      'When a group asks you to sign off on a '
                      'change of adviser or title, the request appears '
                      'here.',
                ),
              if (_error != null) ...[
                ErrorState(
                  key: const Key('changeRequestError'),
                  message: _error!,
                ),
                const Gap.md(),
              ],
              for (var i = 0; i < visible.length; i++) ...[
                _RequestCard(
                  thesisId: visible[i].thesisId,
                  request: visible[i].request,
                  role: visible[i].role,
                  declining:
                      _decliningKey ==
                      _key(visible[i].thesisId, visible[i].role),
                  busy: _busy.contains(
                    _key(visible[i].thesisId, visible[i].role),
                  ),
                  reason: _reason,
                  onAccept: () => _respond(
                    visible[i].thesisId,
                    visible[i].request.type,
                    visible[i].role,
                    true,
                  ),
                  onStartDecline: () => setState(() {
                    _decliningKey = _key(
                      visible[i].thesisId,
                      visible[i].role,
                    );
                    _error = null;
                  }),
                  onCancelDecline: () => setState(() {
                    _decliningKey = null;
                    _reason.clear();
                  }),
                  onConfirmDecline: () => _respond(
                    visible[i].thesisId,
                    visible[i].request.type,
                    visible[i].role,
                    false,
                  ),
                ),
                if (i < visible.length - 1) const Gap.md(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _roleLabel(String role) => switch (role) {
  'newAdviser' => 'new adviser',
  'formerAdviser' => 'former adviser',
  'adviser' => 'adviser',
  _ => role,
};

/// One request awaiting this reader's sign-off: who asks, the from→to
/// change, the reasons, and the two answers.
class _RequestCard extends ConsumerWidget {
  const _RequestCard({
    required this.thesisId,
    required this.request,
    required this.role,
    required this.declining,
    required this.busy,
    required this.reason,
    required this.onAccept,
    required this.onStartDecline,
    required this.onCancelDecline,
    required this.onConfirmDecline,
  });

  final String thesisId;
  final ChangeRequest request;
  final String role;
  final bool declining;
  final bool busy;
  final TextEditingController reason;
  final VoidCallback onAccept;
  final VoidCallback onStartDecline;
  final VoidCallback onCancelDecline;
  final VoidCallback onConfirmDecline;

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

    return Panel(
      key: Key('changeRequestCard-$thesisId-$role'),
      emphasis: !declining,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ToneBadge(
                label: 'Asking you as ${_roleLabel(role)}',
                tone: Tone.act,
                icon: Icons.how_to_reg_outlined,
                dense: true,
              ),
            ],
          ),
          const Gap.sm(),
          Text(thesis.valueOrNull?.workingTitle ?? '…', style: text.titleLarge),
          const Gap.sm(),
          Text(title, style: text.titleSmall),
          const SizedBox(height: 2),
          Text(fromTo, style: text.bodyMedium),
          const Gap.sm(),
          Text('Reasons: ${request.reasons}', style: text.bodySmall),
          const Gap.md(),
          if (declining) ...[
            FormRow(
              label: 'Reason for declining',
              hint: 'The group and the chain above them will see this.',
              child: TextField(
                key: const Key('changeRequestDeclineReason'),
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
                  key: Key('declineChangeRequest-$thesisId-$role'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tone.returned.color(context),
                  ),
                  onPressed: busy ? null : onConfirmDecline,
                  child: const Text('Confirm decline'),
                ),
                TextButton(
                  onPressed: busy ? null : onCancelDecline,
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
                  key: Key('acceptChangeRequest-$thesisId-$role'),
                  onPressed: busy ? null : onAccept,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Accept'),
                ),
                OutlinedButton(
                  key: Key('startDeclineChangeRequest-$thesisId-$role'),
                  onPressed: busy ? null : onStartDecline,
                  child: const Text('Decline'),
                ),
                if (busy) Text('Recording your answer…', style: text.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}
