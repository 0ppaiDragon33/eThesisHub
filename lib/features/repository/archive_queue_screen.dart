import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/archive_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The coordinator's queue of theses waiting to be published to the
/// archive: every thesis [archiveQueueProvider] reports as passed, in
/// manuscript, and not yet archived.
class ArchiveQueueScreen extends ConsumerWidget {
  const ArchiveQueueScreen({super.key});

  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('archiveQueue'),
        child: PageShell(
          title: 'Publish Queue',
          subtitle: 'Theses ready to be added to the college archive.',
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(archiveQueueProvider);

    // Loading, error and empty are kept apart on purpose: a failed read
    // must never render as "nothing to publish" (D-shaped bug this
    // project has shipped from a missing document read as a settled
    // answer).
    if (queueAsync.isLoading) {
      return _framed(const [
        LoadingState(
          key: Key('queueLoading'),
          label: 'Checking the publish queue…',
        ),
      ]);
    }
    if (queueAsync.hasError) {
      return _framed([
        ErrorState(
          error: queueAsync.error,
          message: 'Could not load the publish queue.',
        ),
      ]);
    }

    final queue = queueAsync.valueOrNull ?? const <Thesis>[];

    if (queue.isEmpty) {
      return _framed(const [
        EmptyState(
          key: Key('emptyQueue'),
          icon: Icons.inbox_outlined,
          title: 'Nothing is waiting to be published.',
          message: 'A thesis appears here once it passes its final '
              'defence and its manuscript is uploaded.',
        ),
      ]);
    }

    return _framed([
      for (final t in queue) _QueueRow(thesis: t),
    ]);
  }
}

/// One thesis in the queue, and the button that publishes it.
///
/// A separate widget so its own directory/defence reads and publish-in-
/// flight state do not force the whole list to rebuild.
class _QueueRow extends ConsumerStatefulWidget {
  const _QueueRow({required this.thesis});

  final Thesis thesis;

  @override
  ConsumerState<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends ConsumerState<_QueueRow> {
  bool _publishing = false;
  String? _error;

  /// The final defence that passed this thesis, resolved off
  /// [allDefencesProvider] rather than re-queried: [archiveQueueProvider]
  /// already proved one exists, or this row would not be on screen.
  Defence? _passedFinalDefence(List<Defence> defences) {
    for (final d in defences) {
      if (d.thesisId == widget.thesis.id &&
          d.type == DefenceType.final_ &&
          d.panelVerdict == PassFail.pass) {
        return d;
      }
    }
    return null;
  }

  /// The title this row will actually PUBLISH: the approved candidate's
  /// text, not `thesis.workingTitle`.
  ///
  /// The two are different strings -- the working title is what the group
  /// typed when they created the thesis, the approved one is what the panel
  /// and the dean signed off -- and [publish] writes the approved one. A row
  /// labelled with the working title therefore had the coordinator approving
  /// one thing and publishing another.
  ///
  /// Returns null when it cannot be resolved (titles still loading, the read
  /// failed, no approvedTitleId, or the document is gone); the caller falls
  /// back to the working title, because a row with no title at all is worse
  /// than a row with the older one. Used by BOTH the label and [_publish],
  /// so the two can never name different titles.
  String? _approvedTitle(List<CandidateTitle>? candidates) {
    final approvedId = widget.thesis.approvedTitleId;
    if (candidates == null || approvedId == null) return null;
    for (final c in candidates) {
      if (c.id == approvedId && c.titleText.isNotEmpty) return c.titleText;
    }
    return null;
  }

  /// A directory entry's name, or the uid itself when the directory has
  /// none — a raw uid is not an identity, but it beats a blank field in a
  /// record meant to stay public and correct forever.
  String _nameFor(List<FacultyDirectoryEntry> directory, String uid) {
    for (final entry in directory) {
      if (entry.uid == uid && entry.fullName.isNotEmpty) return entry.fullName;
    }
    return uid;
  }

  Future<void> _publish() async {
    setState(() {
      _publishing = true;
      _error = null;
    });

    try {
      final thesis = widget.thesis;
      final defences = await ref.read(allDefencesProvider.future);
      final finalDefence = _passedFinalDefence(defences);
      if (finalDefence == null) {
        throw StateError('This thesis has no passed final defence on '
            'record anymore.');
      }

      final candidates =
          await ref.read(candidateTitlesProvider(thesis.id).future);
      final title = _approvedTitle(candidates) ?? thesis.workingTitle;

      final directory = await ref.read(allDirectoryProvider.future);
      final adviserUid = thesis.adviserUid;
      final adviserName = adviserUid == null
          ? 'Unassigned'
          : _nameFor(directory, adviserUid);
      final panelNames = [
        for (final uid in thesis.panelistUids) _nameFor(directory, uid),
      ];

      final coordinatorUid = ref.read(signedInUidProvider);
      if (coordinatorUid == null) {
        throw StateError('You must be signed in to publish a thesis.');
      }

      await ref.read(archiveRepositoryProvider).publish(
            thesis: thesis,
            title: title,
            adviserName: adviserName,
            panelNames: panelNames,
            finalDefenceId: finalDefence.id,
            coordinatorUid: coordinatorUid,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = 'Could not publish this thesis: $e';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _publishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final thesis = widget.thesis;
    final text = Theme.of(context).textTheme;
    // The same resolution [_publish] performs, so the label names the title
    // the button will publish.
    final title = _approvedTitle(
            ref.watch(candidateTitlesProvider(thesis.id)).valueOrNull) ??
        thesis.workingTitle;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final authors = thesis.memberNames.isNotEmpty
        ? thesis.memberNames.join(', ')
        : 'Unknown authors';
    final uploadedAt = thesis.manuscriptUploadedAt;
    final uploadedLabel = uploadedAt == null
        ? 'Manuscript uploaded'
        : 'Uploaded ${uploadedAt.year}-${uploadedAt.month.toString().padLeft(2, '0')}-'
            '${uploadedAt.day.toString().padLeft(2, '0')}';

    return Card(
      key: Key('queueRow-${thesis.id}'),
      margin: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                key: Key('queueTitle-${thesis.id}'),
                style: text.titleMedium),
            const SizedBox(height: AppTokens.xs),
            Text(authors, style: text.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: AppTokens.xs),
            Text(uploadedLabel, style: text.bodySmall?.copyWith(color: muted)),
            if (_error != null) ...[
              const SizedBox(height: AppTokens.sm),
              ErrorState(message: _error!),
            ],
            const SizedBox(height: AppTokens.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: Key('publish-${thesis.id}'),
                onPressed: _publishing ? null : _publish,
                child: _publishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Publish to archive'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
