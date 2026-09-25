import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/defence_status.dart';
import 'package:ethesishub/features/defence/redefence_notice.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The live comment log every participant watches during the presentation.
///
/// Comments may be written only while `defence.status.acceptsComments` --
/// i.e. only while the defence is `inProgress`. The security rules and
/// [DefenceRepository.addComment] both enforce that independently, but this
/// screen never offers a control that would always fail: the comment box is
/// hidden, with the reason shown instead, whenever the gate is closed.
///
/// `authorPosition` is derived from the signed-in user's relationship to
/// THIS defence -- not from their account role -- because the position held
/// at a defence must not change retroactively when the account's role does
/// later. See [Defence]'s and [DefenceComment]'s own doc comments.
class DefenceRoomScreen extends ConsumerStatefulWidget {
  const DefenceRoomScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<DefenceRoomScreen> createState() => _DefenceRoomScreenState();
}

class _DefenceRoomScreenState extends ConsumerState<DefenceRoomScreen> {
  final _bodyController = TextEditingController();
  bool _posting = false;
  bool _statusBusy = false;
  String? _commentError;
  String? _statusError;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  /// `'Adviser'` if the signed-in uid matches this defence's adviser,
  /// `'Panel Member'` if it sits among this defence's panel, else the
  /// account's own role for a coordinator or dean. Null for anyone else --
  /// which is exactly who [_canComment] also refuses.
  String? _authorPositionFor(Defence defence, String? uid, UserRole? role) {
    if (uid == null) return null;
    if (uid == defence.adviserUid) return 'Adviser';
    if (defence.panelUids.contains(uid)) return 'Panel Member';
    if (role == UserRole.coordinator) return 'Coordinator';
    if (role == UserRole.dean) return 'Dean';
    return null;
  }

  bool _canComment(Defence defence, String? uid, UserRole? role) {
    if (!defence.status.acceptsComments) return false;
    return _authorPositionFor(defence, uid, role) != null;
  }

  String _commentReasonFor(Defence defence, String? uid, UserRole? role) {
    switch (defence.status) {
      case DefenceStatus.scheduled:
        return 'The comment log opens once the defence begins.';
      case DefenceStatus.completed:
        return 'This defence is closed. The comment log cannot be added to '
            'anymore.';
      case DefenceStatus.inProgress:
        return 'Only the adviser, the panel, the coordinator, or the dean '
            'may comment here.';
      case DefenceStatus.cancelled:
        return 'This defence was cancelled, so it has no comment log.';
    }
  }

  /// A date and time a coordinator can read at a glance.
  String _formatDateTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'am' : 'pm';
    return '${local.day}/${local.month}/${local.year} at $h:$m$ampm';
  }

  /// Moves the date, time or venue of a defence that has not started.
  ///
  /// Before this existed the schedule was frozen at creation, so a
  /// coordinator who picked the wrong day could neither fix it nor remove
  /// the defence -- the only way forward was opening it anyway.
  Future<void> _editSchedule(Defence defence) async {
    final venue = TextEditingController(text: defence.venue);
    var when = defence.scheduledAt ?? DateTime.now();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Edit schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('editVenue'),
                controller: venue,
                decoration: const InputDecoration(labelText: 'Venue'),
              ),
              const Gap.md(),
              OutlinedButton(
                key: const Key('editDate'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: when,
                    firstDate: DateTime.now()
                        .subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked == null) return;
                  setInner(() => when = DateTime(picked.year, picked.month,
                      picked.day, when.hour, when.minute));
                },
                child: Text(
                    'Date: ${when.day}/${when.month}/${when.year}'),
              ),
              const Gap.sm(),
              // The time needs its own control. A date picker alone carries
              // the original hour and minute forward, so a defence booked
              // for the wrong time could have its day corrected and never
              // its hour -- which is the half more likely to be wrong.
              OutlinedButton(
                key: const Key('editTime'),
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(when),
                  );
                  if (picked == null) return;
                  setInner(() => when = DateTime(when.year, when.month,
                      when.day, picked.hour, picked.minute));
                },
                child: Text('Time: ${TimeOfDay.fromDateTime(when).format(context)}'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep as is'),
            ),
            FilledButton(
              key: const Key('saveSchedule'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (!mounted) return;
    setState(() {
      _statusBusy = true;
      _statusError = null;
    });
    try {
      await ref.read(defenceRepositoryProvider).reschedule(
            defenceId: widget.defenceId,
            scheduledAt: when,
            venue: venue.text,
          );
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _statusError = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _statusError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _statusError = e.code == 'permission-denied'
            ? 'You do not have permission to change this schedule.'
            : 'Could not save the schedule.');
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  /// Calls off a defence created by mistake. Confirmed, because it is
  /// terminal: a cancelled defence cannot be walked back into the
  /// lifecycle, only replaced by scheduling a new one.
  Future<void> _confirmCancel() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this defence?'),
        content: const Text(
            'It stays in the record as cancelled rather than disappearing, '
            'and it cannot be reopened. Schedule a new one instead.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('confirmCancel'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel the defence'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _setStatus(DefenceStatus.cancelled);
  }

  Future<void> _postComment({
    required String uid,
    required String authorName,
    required String authorPosition,
  }) async {
    if (_posting) return;
    final body = _bodyController.text;

    setState(() {
      _posting = true;
      _commentError = null;
    });

    try {
      await ref.read(defenceRepositoryProvider).addComment(
            defenceId: widget.defenceId,
            authorUid: uid,
            authorName: authorName,
            authorPosition: authorPosition,
            body: body,
          );
      if (mounted) _bodyController.clear();
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _commentError = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _commentError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _commentError = e.code == 'permission-denied'
            ? 'You do not have permission to comment here '
                '[permission-denied].'
            : 'Could not post that comment. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _commentError = 'Could not post that comment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _setStatus(DefenceStatus status) async {
    if (_statusBusy) return;

    setState(() {
      _statusBusy = true;
      _statusError = null;
    });

    try {
      await ref.read(defenceRepositoryProvider).setStatus(
            defenceId: widget.defenceId,
            status: status,
          );
    } on StateError catch (e) {
      if (mounted) setState(() => _statusError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _statusError = e.code == 'permission-denied'
            ? 'You do not have permission to change this defence\'s status '
                '[permission-denied].'
            : 'Could not update this defence. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _statusError = 'Could not update this defence. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  /// Wraps every non-content state in the same frame the loaded screen
  /// uses, so a room still loading its defence, its log, or the signed-in
  /// profile is never a bare, unnavigable page.
  ///
  /// The Scaffold and AppBar moved to the app shell, which titles this
  /// route 'Defence room' for every one of these states — hence the
  /// [title] override being gone: it named the app bar, and there is no
  /// longer an app bar here to name. Which defence this is, is said by
  /// [PageShell]'s own heading instead.
  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('defenceRoom'),
        child: PageShell(children: children),
      );

  @override
  Widget build(BuildContext context) {
    final defenceAsync = ref.watch(defenceProvider(widget.defenceId));
    final commentsAsync = ref.watch(defenceCommentsProvider(widget.defenceId));
    final meAsync = ref.watch(currentUserProvider);
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    // Each of the three streams gets its own isLoading/hasError branch,
    // checked apart from the others -- collapsing them would tell a viewer
    // whose comment log is merely still connecting that the defence itself
    // does not exist, or vice versa.
    if (defenceAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading defence…')]);
    }
    if (defenceAsync.hasError) {
      return _framed([
        ErrorState(
          error: defenceAsync.error,
          message: 'Could not load this defence.',
        ),
      ]);
    }
    final defence = defenceAsync.valueOrNull;
    if (defence == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defence not found',
          message: 'This defence no longer exists.',
        ),
      ]);
    }

    // The group reads the adviser's consolidation, never this raw log --
    // M3-2 forbids it, because the log may hold half-finished remarks and
    // ones the panel withdrew. Decided from `defence` alone, before the
    // comments stream is even consulted: once released, the rules DO permit
    // a leader to read `comments`, so waiting on that stream here would let
    // it resolve and render every raw remark to the one reader who must
    // never see them.
    final isLeader = uid != null && uid == defence.leaderUid;
    if (isLeader) {
      final completed = defence.status == DefenceStatus.completed;
      return _framed([
        Panel(
          emphasis: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToneBadge(
                label: defenceStatusLabel(defence.status),
                tone: defenceStatusTone(defence.status),
                icon: defenceStatusIcon(defence.status),
              ),
              const Gap.md(),
              const Text(
                'The group reads the adviser\'s consolidated comments for '
                'this defence, not the live log.',
                key: Key('leaderRefusal'),
              ),
              // D47: the group's route to the numbers is the paper grading
              // sheet, so nothing here links to '/grades'.
              if (completed) ...[
                const Gap.md(),
                if (defence.hasVerdict) ...[
                  Text(
                    'Panel verdict: ${defence.panelVerdict!.label}',
                    key: const Key('leaderVerdict'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Gap.sm(),
                  RedefenceNotice(defence: defence),
                ] else
                  const Text(
                    'The panel has not recorded a verdict for this defence '
                    'yet.',
                    key: Key('leaderVerdictPending'),
                  ),
              ],
              const Gap.lg(),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: const Key('goToConsolidated'),
                  onPressed: () => context
                      .go('/defence/room/${widget.defenceId}/consolidated'),
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('View consolidated comments'),
                ),
              ),
            ],
          ),
        ),
      ]);
    }

    if (commentsAsync.isLoading) {
      return _framed(
        const [LoadingState(label: 'Loading comments…')],
      );
    }
    if (commentsAsync.hasError) {
      return _framed(
        [
          ErrorState(
            error: commentsAsync.error,
            message: 'Could not load the comment log.',
          ),
        ],
      );
    }
    final comments = commentsAsync.valueOrNull ?? const <DefenceComment>[];

    if (meAsync.isLoading) {
      return _framed(
        const [LoadingState(label: 'Loading your profile…')],
      );
    }
    if (meAsync.hasError) {
      return _framed(
        [
          ErrorState(
            error: meAsync.error,
            message: 'Could not load your profile.',
          ),
        ],
      );
    }
    final me = meAsync.valueOrNull;
    final role = me?.role;

    // Coordinator only -- not the dean, who also grants comment access but
    // does not drive the room's own open/close lifecycle.
    final isCoordinator = role == UserRole.coordinator;
    final canComment = _canComment(defence, uid, role);
    final authorPosition = _authorPositionFor(defence, uid, role);

    // Thesis title only, shown for orientation; never gates the room --
    // this stream is not one of the three the room depends on to function.
    final thesisTitle =
        ref.watch(thesisByIdProvider(defence.thesisId)).valueOrNull?.workingTitle;

    // The panelist's own sheet, watched only for a panelist on a closed
    // defence -- the only reader this figure is ever shown to. Watching it
    // unconditionally for everyone else would open a stream the rules deny
    // to a role that never asked for it.
    final isPanelist = uid != null && defence.panelUids.contains(uid);
    final myEvaluation = isPanelist && defence.status == DefenceStatus.completed
        ? ref.watch(myEvaluationProvider(widget.defenceId)).valueOrNull
        : null;
    final isAdviser = uid != null && uid == defence.adviserUid;

    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final at = defence.scheduledAt;

    final log = Panel(
      title: 'Session log',
      subtitle: defence.status == DefenceStatus.inProgress
          ? 'Live. Remarks appear as they are posted'
          : 'Remarks made during the defence',
      icon: Icons.forum_outlined,
      flush: true,
      trailing: defence.status == DefenceStatus.inProgress
          ? const ToneBadge(
              label: 'Live',
              tone: Tone.endorsed,
              icon: Icons.sensors_rounded,
              dense: true,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (comments.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppTokens.lg - 4),
              child: Text('No comments yet. Remarks made during the defence '
                  'will appear here.', style: text.bodySmall),
            ),
          for (final c in comments)
            Container(
              key: Key('commentRow-${c.id}'),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.lg - 4, vertical: AppTokens.md - 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: p.rule)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InitialsAvatar(c.authorName, size: 32),
                  const SizedBox(width: AppTokens.sm + 2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.authorName}, ${c.authorPosition}',
                            style: text.labelMedium),
                        const SizedBox(height: 2),
                        Text(c.body, style: text.bodyMedium),
                      ],
                    ),
                  ),
                  if (c.createdAt != null)
                    Text(Dates.time(c.createdAt!), style: text.bodySmall),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppTokens.md),
            child: canComment
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_commentError != null) ...[
                        ErrorState(
                          key: const Key('commentError'),
                          message: _commentError!,
                        ),
                        const Gap.sm(),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('commentBody'),
                              controller: _bodyController,
                              decoration: const InputDecoration(
                                hintText: 'Add a remark to the log',
                              ),
                              minLines: 1,
                              maxLines: 4,
                            ),
                          ),
                          const SizedBox(width: AppTokens.sm),
                          FilledButton(
                            key: const Key('postComment'),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(64, 52)),
                            onPressed: _posting ||
                                    uid == null ||
                                    authorPosition == null
                                ? null
                                : () => _postComment(
                                      uid: uid,
                                      authorName: me?.fullName ?? '',
                                      authorPosition: authorPosition,
                                    ),
                            child: Text(_posting ? 'Posting…' : 'Post'),
                          ),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 18, color: p.muted),
                      const SizedBox(width: AppTokens.sm),
                      Expanded(
                        child: Text(
                          _commentReasonFor(defence, uid, role),
                          key: const Key('commentReason'),
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );

    final session = Panel(
      title: 'Session',
      icon: Icons.event_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ToneBadge(
              label: defenceStatusLabel(defence.status),
              tone: defenceStatusTone(defence.status),
              icon: defenceStatusIcon(defence.status),
            ),
          ),
          const Gap.md(),
          FactLine(
            label: 'When',
            value: at == null
                ? 'Date to be confirmed'
                : '${Dates.weekday(at)}, ${Dates.day(at)}, ${Dates.time(at)}',
          ),
          FactLine(label: 'Venue', value: defence.venue),
          FactLine(
            label: 'Panel',
            value: defence.panelUids.length == 1
                ? '1 member'
                : '${defence.panelUids.length} members',
          ),
          if (_statusError != null) ...[
            ErrorState(key: const Key('statusError'), message: _statusError!),
            const Gap.sm(),
          ],
          // Hidden rather than disabled for anyone but the coordinator.
          if (isCoordinator && defence.status == DefenceStatus.scheduled) ...[
            Builder(builder: (context) {
              final opensAt = defence.scheduledAt?.subtract(defenceOpenGrace);
              final tooEarly =
                  opensAt != null && DateTime.now().isBefore(opensAt);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const Key('openDefence'),
                    onPressed: _statusBusy || tooEarly
                        ? null
                        : () => _setStatus(DefenceStatus.inProgress),
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: Text(_statusBusy ? 'Opening…' : 'Open defence'),
                  ),
                  // Say when, not just no.
                  if (tooEarly) ...[
                    const Gap.sm(),
                    Text(
                      'Opens ${_formatDateTime(opensAt)}, 30 minutes '
                          'before the scheduled time.',
                      key: const Key('openNotYet'),
                      style: text.bodySmall,
                    ),
                  ],
                ],
              );
            }),
            const Gap.sm(),
            OutlinedButton(
              key: const Key('editSchedule'),
              onPressed: _statusBusy ? null : () => _editSchedule(defence),
              child: const Text('Edit schedule'),
            ),
            // For a defence created by mistake; one that happened is
            // closed instead so its log stays a record.
            TextButton(
              key: const Key('cancelDefence'),
              style: TextButton.styleFrom(
                  foregroundColor: Tone.returned.color(context)),
              onPressed: _statusBusy ? null : _confirmCancel,
              child: const Text('Cancel this defence'),
            ),
          ],
          if (isCoordinator && defence.status == DefenceStatus.inProgress)
            FilledButton.icon(
              key: const Key('closeDefence'),
              onPressed:
                  _statusBusy ? null : () => _setStatus(DefenceStatus.completed),
              icon: const Icon(Icons.stop_rounded, size: 20),
              label: Text(_statusBusy ? 'Closing…' : 'Close defence'),
            ),
        ],
      ),
    );

    final completed = defence.status == DefenceStatus.completed;
    final canSeeGrades = isAdviser ||
        ((isPanelist || isCoordinator || role == UserRole.dean) &&
            defence.evaluationsReleased);

    final after = Panel(
      title: 'Records',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            key: const Key('goToConsolidated'),
            icon: const Icon(Icons.summarize_outlined, size: 18),
            label: const Text('Consolidated comments'),
            onPressed: () =>
                context.go('/defence/room/${widget.defenceId}/consolidated'),
          ),
          // Form 5c scores what happened, so only on a closed defence.
          if (completed && isPanelist) ...[
            const Gap.sm(),
            FilledButton(
              key: const Key('goToEvaluate'),
              onPressed: () =>
                  context.push('/defence/room/${widget.defenceId}/evaluate'),
              child: Text(myEvaluation != null
                  ? 'Your evaluation: ${myEvaluation.total}/100'
                  : 'Evaluate'),
            ),
          ],
          // Released grades: `evaluationsReleased`, never `isReleased`.
          if (completed && canSeeGrades) ...[
            const Gap.sm(),
            OutlinedButton(
              key: const Key('goToGrades'),
              onPressed: () =>
                  context.push('/defence/room/${widget.defenceId}/grades'),
              child: const Text('Grades'),
            ),
          ],
          if (!completed) ...[
            const Gap.sm(),
            Text('Evaluation opens once the defence is closed.',
                style: text.bodySmall),
          ],
        ],
      ),
    );

    return KeyedSubtree(
      key: const Key('defenceRoom'),
      child: PageShell(
        maxWidth: AppTokens.measureWide,
        kicker: defence.label,
        title: thesisTitle ?? defence.label,
        children: [
          if (defence.isRedefence) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('redefenceOfLink'),
                onPressed: () =>
                    context.push('/defence/room/${defence.redefenceOf}'),
                icon: const Icon(Icons.history, size: 18),
                label: Text('Re-defence of an earlier '
                    '${defence.type.label.toLowerCase()}. Open the original'),
              ),
            ),
            const Gap.sm(),
          ],
          SplitColumns(
            secondaryFirstWhenStacked: true,
            primary: [log],
            secondary: [session, after],
          ),
        ],
      ),
    );
  }
}
