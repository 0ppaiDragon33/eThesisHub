import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/change_request_form.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/providers/change_request_providers.dart';

/// Shows a leader where each open change-of-adviser/title request stands:
/// the current stage, each sign-off's state, and — once returned — the
/// decline reason and a way to edit and resubmit (spec 2026-09-25).
///
/// Modelled on `thesis_status_screen.dart`'s nomination-progress panel.
/// Renders nothing at all when there is no open or returned request, the
/// common case for most theses most of the time.
class ChangeRequestTracker extends ConsumerWidget {
  const ChangeRequestTracker({
    super.key,
    required this.thesisId,
    required this.thesis,
  });

  final String thesisId;

  /// Needed for an approved title request's record PDF, which prints the
  /// thesis's current working title alongside the requested one.
  final Thesis thesis;

  static String stageLabel(ChangeRequestStage stage) => switch (stage) {
    ChangeRequestStage.pendingAdvisers => 'Awaiting the new and former adviser',
    ChangeRequestStage.pendingAdviser => 'Awaiting your adviser',
    ChangeRequestStage.pendingCoordinator =>
      'Awaiting the Research Coordinator',
    ChangeRequestStage.pendingDean => 'Awaiting the Dean',
    ChangeRequestStage.approved => 'Approved',
    ChangeRequestStage.returned => 'Returned',
  };

  static String roleLabel(String role) => switch (role) {
    'newAdviser' => 'New adviser',
    'formerAdviser' => 'Former adviser',
    'adviser' => 'Adviser',
    'coordinator' => 'Research Coordinator',
    'dean' => 'Dean',
    _ => role,
  };

  static (String, Tone) signoffState(SignoffStatus status) => switch (status) {
    SignoffStatus.accepted => ('Accepted', Tone.endorsed),
    SignoffStatus.declined => ('Declined', Tone.returned),
    SignoffStatus.pending => ('Pending', Tone.awaiting),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(changeRequestsForThesisProvider(thesisId));

    return requestsAsync.when(
      loading: () => const Panel(
        title: 'Change requests',
        icon: Icons.sync_alt_outlined,
        child: LoadingState(label: 'Loading change requests…'),
      ),
      error: (e, _) => Panel(
        title: 'Change requests',
        icon: Icons.sync_alt_outlined,
        child: ErrorState(
          error: e,
          message: 'Could not load your change requests.',
        ),
      ),
      data: (requests) {
        // One card per open, returned or approved request. An approved
        // request's change is already reflected in the thesis document
        // itself, but the card stays so the leader can download the filled
        // Form 4a/4b record.
        final visible = requests
            .where(
              (r) =>
                  r.isOpen ||
                  r.stage == ChangeRequestStage.returned ||
                  r.stage == ChangeRequestStage.approved,
            )
            .toList();
        if (visible.isEmpty) return const SizedBox.shrink();

        return KeyedSubtree(
          key: const Key('changeRequestTracker'),
          child: Panel(
            title: 'Change requests',
            icon: Icons.sync_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  _RequestCard(
                    thesisId: thesisId,
                    thesis: thesis,
                    request: visible[i],
                  ),
                  if (i < visible.length - 1) const Gap.md(),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({
    required this.thesisId,
    required this.thesis,
    required this.request,
  });

  final String thesisId;
  final Thesis thesis;
  final ChangeRequest request;

  /// The reason on the sign-off that returned this request, if any -- the
  /// one role in [signoffRolesFor] whose status is `declined`. Requests are
  /// returned by exactly one decline, so at most one exists.
  String? _declineReason() {
    for (final role in signoffRolesFor(request.type)) {
      final signoff = request.signoffs[role];
      if (signoff?.status == SignoffStatus.declined) {
        final reason = signoff?.reason;
        if (reason != null && reason.isNotEmpty) return reason;
      }
    }
    return null;
  }

  Future<void> _download(WidgetRef ref) async {
    final bytes = await buildChangeRequestPdf(request, thesis: thesis);
    final formId = request.type == ChangeRequestType.adviser
        ? 'Form4a'
        : 'Form4b';
    await ref.read(pdfSharerProvider)(bytes, '$formId-$thesisId.pdf');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final returned = request.stage == ChangeRequestStage.returned;
    final approved = request.stage == ChangeRequestStage.approved;
    final title = request.type == ChangeRequestType.adviser
        ? 'Change of adviser'
        : 'Change of title';
    final declineReason = returned ? _declineReason() : null;

    return Container(
      key: Key('changeRequest-${request.type.value}'),
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTokens.radius),
        border: Border.all(color: p.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(title, style: text.titleSmall)),
              ToneBadge(
                label: ChangeRequestTracker.stageLabel(request.stage),
                tone: returned ? Tone.returned : Tone.awaiting,
              ),
            ],
          ),
          const SizedBox(height: AppTokens.sm),
          for (final role in signoffRolesFor(request.type))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ChangeRequestTracker.roleLabel(role),
                      style: text.bodyMedium,
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final status =
                          request.signoffs[role]?.status ??
                          SignoffStatus.pending;
                      final (label, tone) = ChangeRequestTracker.signoffState(
                        status,
                      );
                      return ToneBadge(
                        key: Key('signoff-${request.type.value}-$role'),
                        label: label,
                        tone: tone,
                        dense: true,
                      );
                    },
                  ),
                ],
              ),
            ),
          if (returned && declineReason != null) ...[
            const Gap.sm(),
            ErrorState(
              key: Key('declineReason-${request.type.value}'),
              message: 'Declined: $declineReason',
            ),
          ],
          if (returned) ...[
            const Gap.sm(),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const Key('resubmitChangeRequest'),
                onPressed: () => context.push(
                  request.type == ChangeRequestType.adviser
                      ? '/thesis/change-adviser?id=$thesisId'
                      : '/thesis/change-title?id=$thesisId',
                  extra: request,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit and resubmit'),
              ),
            ),
          ],
          if (approved) ...[
            const Gap.sm(),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: Key('downloadChangeRequestForm-${request.type.value}'),
                onPressed: () => _download(ref),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download form'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
