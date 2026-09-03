import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
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
      return _framed(
        [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'The group reads the adviser\'s consolidated comments for '
              'this defence, not the live log.',
              key: Key('leaderRefusal'),
            ),
          ),
          FilledButton(
            key: const Key('goToConsolidated'),
            onPressed: () => context
                .go('/defence/room/${widget.defenceId}/consolidated'),
            child: const Text('View consolidated comments'),
          ),
          // D47's group half. Decided from `defence` alone, same as the
          // isLeader gate above it: the group's route to the numbers is the
          // paper grading sheet through the subject professor, and no arm
          // of the rules grants them a read of any evaluation, so nothing
          // here links to '/grades' -- the screen would load and then deny.
          if (defence.status == DefenceStatus.completed)
            if (defence.hasVerdict)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Panel verdict: ${defence.panelVerdict!.label}',
                  key: const Key('leaderVerdict'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'The panel has not recorded a verdict for this defence '
                  'yet.',
                  key: Key('leaderVerdictPending'),
                ),
              ),
        ],
      );
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

    return KeyedSubtree(
      key: const Key('defenceRoom'),
      child: PageShell(
        title: defence.type.label,
        subtitle: thesisTitle,
        children: [
          // The room has no other route to the consolidated view once the
          // coordinator closes it -- grep for 'consolidated' across lib/
          // found it nowhere else before this. Visible to everyone who can
          // already see the room; the leader never reaches this branch at
          // all (see the isLeader gate above), so this is not their door.
          //
          // On the page rather than in the app bar, because the app bar
          // belongs to the app shell now and it carries the sidebar and
          // the back control, which every screen needs, rather than one
          // screen's own link.
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('goToConsolidated'),
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Consolidated comments'),
              onPressed: () => context
                  .go('/defence/room/${widget.defenceId}/consolidated'),
            ),
          ),
          const Gap.md(),
          // Evaluation entry points, only on a closed defence -- Form 5c
          // exists to score what happened in the room, not one still open.
          // Above the comment log, since the sheet and the grades are what
          // brought most panelists and the adviser back to this screen once
          // the defence is done.
          if (defence.status == DefenceStatus.completed) ...[
            if (isPanelist)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: const Key('goToEvaluate'),
                  onPressed: () => context
                      .push('/defence/room/${widget.defenceId}/evaluate'),
                  child: Text(myEvaluation != null
                      ? 'Your evaluation — ${myEvaluation.total}/100'
                      : 'Evaluate'),
                ),
              ),
            // The adviser always, once closed; the panel, the coordinator
            // and the dean once the adviser has released the grades. The
            // rules already grant all four the released evaluations and
            // §6 names all four as viewers of this screen -- without the
            // last two, two authorised roles could reach the grades only
            // by typing the URL. Naming this on `evaluationsReleased`,
            // never `isReleased`: that flag is the comment log's own
            // release to the group, three lines away in defence.dart and
            // easy to reach for by mistake.
            if (isAdviser ||
                ((isPanelist || isCoordinator || role == UserRole.dean) &&
                    defence.evaluationsReleased))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const Key('goToGrades'),
                    onPressed: () => context
                        .push('/defence/room/${widget.defenceId}/grades'),
                    child: const Text('Grades'),
                  ),
                ),
              ),
            const Gap.md(),
          ],
          for (final c in comments)
            Card(
              key: Key('commentRow-${c.id}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.authorName} — ${c.authorPosition}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(c.body),
                  ],
                ),
              ),
            ),
          if (comments.isEmpty)
            const EmptyState(
              icon: Icons.forum_outlined,
              title: 'No comments yet',
              message: 'Remarks made during the defence will appear here.',
            ),
          const Gap.lg(),
          if (canComment) ...[
            TextField(
              key: const Key('commentBody'),
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Add a comment'),
              minLines: 2,
              maxLines: 4,
            ),
            const Gap.md(),
            if (_commentError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _commentError!,
                  key: const Key('commentError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('postComment'),
              onPressed: _posting || uid == null || authorPosition == null
                  ? null
                  : () => _postComment(
                        uid: uid,
                        authorName: me?.fullName ?? '',
                        authorPosition: authorPosition,
                      ),
              child: Text(_posting ? 'Posting…' : 'Post comment'),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _commentReasonFor(defence, uid, role),
                key: const Key('commentReason'),
              ),
            ),
          const Gap.lg(),
          if (_statusError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _statusError!,
                key: const Key('statusError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // Hidden rather than merely disabled for anyone but the
          // coordinator: the rules deny the write either way, but a button
          // that always fails is worse than no button at all.
          if (isCoordinator && defence.status == DefenceStatus.scheduled) ...[
            Builder(builder: (context) {
              final opensAt = defence.scheduledAt?.subtract(defenceOpenGrace);
              final tooEarly =
                  opensAt != null && DateTime.now().isBefore(opensAt);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    key: const Key('openDefence'),
                    onPressed: _statusBusy || tooEarly
                        ? null
                        : () => _setStatus(DefenceStatus.inProgress),
                    child: Text(_statusBusy ? 'Opening…' : 'Open defence'),
                  ),
                  // Say WHEN, not just no. A dead button with no reason
                  // reads as a broken app; the coordinator needs to know
                  // whether to wait or to move the schedule.
                  if (tooEarly) ...[
                    const Gap.sm(),
                    Text(
                      'Opens ${_formatDateTime(opensAt)}, 30 minutes '
                          'before the scheduled time.',
                      key: const Key('openNotYet'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              );
            }),
            const Gap.sm(),
            OutlinedButton(
              key: const Key('editSchedule'),
              onPressed:
                  _statusBusy ? null : () => _editSchedule(defence),
              child: const Text('Edit schedule'),
            ),
            const Gap.sm(),
            // Cancelling is for a defence created by mistake -- wrong
            // thesis, duplicate, abandoned. One that actually happened is
            // closed instead, so its log stays a record of what was said.
            TextButton(
              key: const Key('cancelDefence'),
              onPressed: _statusBusy ? null : _confirmCancel,
              child: const Text('Cancel this defence'),
            ),
          ],
          if (isCoordinator && defence.status == DefenceStatus.inProgress)
            FilledButton(
              key: const Key('closeDefence'),
              onPressed:
                  _statusBusy ? null : () => _setStatus(DefenceStatus.completed),
              child: Text(_statusBusy ? 'Closing…' : 'Close defence'),
            ),
        ],
      ),
    );
  }
}
