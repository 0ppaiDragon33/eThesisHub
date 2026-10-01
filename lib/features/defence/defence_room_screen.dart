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
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/defence_status.dart';
import 'package:ethesishub/features/defence/manuscript/defence_typing.dart';
import 'package:ethesishub/features/defence/manuscript/highlights_panel.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_pane.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';
import 'package:ethesishub/features/defence/redefence_notice.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The defence room: the manuscript the panel marks up, with the highlights
/// beside it, and the session controls.
///
/// The panel's remarks are highlights on the manuscript, each with its own
/// comment. There is no separate live comment log: a remark belongs to the
/// passage it is about. (Comments written before this are still stored, and
/// the adviser's consolidation still shows them.)
///
/// Highlights may be drawn only while `defence.status.acceptsComments` --
/// i.e. only while the defence is `inProgress`. The security rules and
/// [DefenceRepository.addAnnotation] both enforce that independently, but
/// this screen never offers a control that would always fail.
///
/// `authorPosition` is derived from the signed-in user's relationship to
/// THIS defence -- not from their account role -- because the position held
/// at a defence must not change retroactively when the account's role does
/// later. See [Defence]'s and [DefenceAnnotation]'s own doc comments.
class DefenceRoomScreen extends ConsumerStatefulWidget {
  const DefenceRoomScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<DefenceRoomScreen> createState() => _DefenceRoomScreenState();
}

class _DefenceRoomScreenState extends ConsumerState<DefenceRoomScreen> {
  final _manuscript = ManuscriptController();
  DefenceTyping? _typing;
  bool _statusBusy = false;
  String? _statusError;

  @override
  void dispose() {
    _typing?.dispose();
    _manuscript.dispose();
    super.dispose();
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _composeHighlight(
    DrawnHighlight drawn, {
    required String uid,
    required String authorName,
    required String authorPosition,
  }) async {
    final body = await showHighlightComposer(
      context,
      onTyping: (on) =>
          _typing?.typing(ComposingTarget.manuscript, active: on),
    );
    _typing?.typing(ComposingTarget.manuscript, active: false);
    if (body == null || !mounted) return;
    try {
      await ref.read(defenceRepositoryProvider).addAnnotation(
            defenceId: widget.defenceId,
            authorUid: uid,
            authorName: authorName,
            authorPosition: authorPosition,
            chapter: drawn.chapter,
            version: drawn.version,
            page: drawn.page,
            rect: drawn.rect,
            body: body,
          );
    } on ArgumentError catch (e) {
      if (mounted) _say(e.message.toString());
    } on StateError catch (e) {
      if (mounted) _say(e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        _say(e.code == 'permission-denied'
            ? 'You do not have permission to highlight here '
                '[permission-denied].'
            : 'Could not save the highlight. Please try again.');
      }
    } catch (_) {
      if (mounted) _say('Could not save the highlight. Please try again.');
    }
  }

  Future<void> _deleteHighlight(DefenceAnnotation a, String uid) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this highlight?'),
        content: Text('"${a.body}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            key: const Key('confirmDeleteHighlight'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await ref.read(defenceRepositoryProvider).deleteAnnotation(
          defenceId: widget.defenceId, annotationId: a.id, uid: uid);
    } on StateError catch (e) {
      if (mounted) _say(e.message);
    } catch (_) {
      // A FirebaseException or anything else: the same message.
      if (mounted) _say('Could not remove the highlight. Please try again.');
    }
  }

  /// `'Adviser'` if the signed-in uid matches this defence's adviser,
  /// `'Panel Member'` if it sits among this defence's panel, else the
  /// account's own role for a coordinator or dean. Null for anyone else --
  /// who may not highlight either.
  String? _authorPositionFor(Defence defence, String? uid, UserRole? role) {
    if (uid == null) return null;
    if (uid == defence.adviserUid) return 'Adviser';
    if (defence.panelUids.contains(uid)) return 'Panel Member';
    if (role == UserRole.coordinator) return 'Coordinator';
    if (role == UserRole.dean) return 'Dean';
    return null;
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
    final meAsync = ref.watch(currentUserProvider);
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    // Each stream gets its own isLoading/hasError branch, checked apart from
    // the others -- collapsing them would tell a viewer whose profile is
    // merely still connecting that the defence itself does not exist, or
    // vice versa.
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

    // The group sees the panel's highlights only once the adviser has
    // released them, never while the defence is live (M3-2): a remark may
    // be half-finished or withdrawn. Decided from `defence` alone, before
    // any highlight stream is consulted, so nothing here can render a live
    // highlight to the one reader who must not see it yet.
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
              // What the group can do now, said plainly: the panel's
              // highlights are theirs to read once the adviser releases.
              Text(
                defence.isReleased
                    ? 'The panel has marked up your manuscript. Read each '
                        'highlight and its comment on the page it is about.'
                    : 'The panel marks up your manuscript during the '
                        'defence. You can read their highlights here once '
                        'your adviser releases them.',
                key: const Key('leaderRefusal'),
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
              Wrap(
                spacing: AppTokens.sm,
                runSpacing: AppTokens.sm,
                children: [
                  // The panel's highlights reach the group on the adviser's
                  // release (spec §7.2): the main thing to do here.
                  if (defence.isReleased)
                    FilledButton.icon(
                      key: const Key('goToManuscript'),
                      onPressed: () => context
                          .go('/defence/room/${widget.defenceId}/manuscript'),
                      icon: const Icon(Icons.highlight_alt, size: 18),
                      label: const Text('View manuscript and highlights'),
                    ),
                  // Remarks written before highlights replaced the live
                  // log are still the adviser's to consolidate and release.
                  OutlinedButton.icon(
                    key: const Key('goToConsolidated'),
                    onPressed: () => context
                        .go('/defence/room/${widget.defenceId}/consolidated'),
                    icon: const Icon(Icons.summarize_outlined, size: 18),
                    label: const Text('View consolidated comments'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]);
    }

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

    // Coordinator only -- not the dean, who may also highlight but does not
    // drive the room's own open/close lifecycle.
    final isCoordinator = role == UserRole.coordinator;
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
    final showManuscript = defence.status != DefenceStatus.cancelled;
    final canHighlight = defence.status == DefenceStatus.inProgress &&
        uid != null &&
        authorPosition != null;
    // The "is typing" marker for a highlight's comment, made only for
    // someone who may highlight.
    if (canHighlight) {
      _typing ??= DefenceTyping(
        repo: ref.read(defenceRepositoryProvider),
        defenceId: widget.defenceId,
        uid: uid,
        name: me?.fullName ?? '',
        position: authorPosition,
      );
    }

    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final at = defence.scheduledAt;

    final live = defence.status == DefenceStatus.inProgress
        ? const ToneBadge(
            label: 'Live',
            tone: Tone.endorsed,
            icon: Icons.sensors_rounded,
            dense: true,
          )
        : null;
    // The panel's remarks: each highlight with its own comment, in page
    // order, beside the manuscript. The only place remarks are written.
    final highlightsPanel = Panel(
      title: 'Highlights',
      subtitle: defence.status == DefenceStatus.inProgress
          ? 'Live. Highlights appear as they are made'
          : 'Boxes drawn on the manuscript, in page order',
      icon: Icons.highlight_alt,
      flush: true,
      trailing: live,
      child: HighlightsTab(
        defence: defence,
        myUid: uid,
        onSelect: _manuscript.reveal,
        onDelete: uid == null ? null : (a) => _deleteHighlight(a, uid),
      ),
    );

    final pane = DefenceManuscriptPane(
      defence: defence,
      controller: _manuscript,
      canHighlight: canHighlight,
      highlightClosedReason: defence.status == DefenceStatus.scheduled
          ? 'Highlighting opens when the defence starts.'
          : null,
      // Spelled out rather than `canHighlight ? …`: the null checks here are
      // what promote `uid` and `authorPosition` inside the closure.
      onHighlightDrawn: defence.status == DefenceStatus.inProgress &&
              uid != null &&
              authorPosition != null
          ? (d) => _composeHighlight(d,
              uid: uid,
              authorName: me?.fullName ?? '',
              authorPosition: authorPosition)
          : null,
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

    final redefenceLink = [
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
    ];

    final stacked = SplitColumns(
      secondaryFirstWhenStacked: true,
      primary: [highlightsPanel],
      secondary: [session, after],
    );

    // A cancelled defence has no manuscript and no highlights: just its
    // record.
    if (!showManuscript) {
      return KeyedSubtree(
        key: const Key('defenceRoom'),
        child: PageShell(
          maxWidth: AppTokens.measureWide,
          kicker: defence.label,
          title: thesisTitle ?? defence.label,
          children: [
            ...redefenceLink,
            SplitColumns(
              secondaryFirstWhenStacked: true,
              primary: [
                Panel(
                  title: 'Highlights',
                  icon: Icons.highlight_alt,
                  child: Text(
                    'This defence was cancelled, so nothing was marked.',
                    key: const Key('cancelledNote'),
                    style: text.bodySmall,
                  ),
                ),
              ],
              secondary: [session, after],
            ),
          ],
        ),
      );
    }

    switch (Breakpoint.of(context)) {
      case Breakpoint.expanded:
        // Spec §7.1 Option A: the manuscript left, the room on the right.
        return KeyedSubtree(
          key: const Key('defenceRoom'),
          child: PageShell(
            scrollable: false,
            maxWidth: AppTokens.measureWide,
            kicker: defence.label,
            title: thesisTitle ?? defence.label,
            children: [
              ...redefenceLink,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: pane),
                    const SizedBox(width: AppTokens.lg),
                    SizedBox(
                      width: 420,
                      child: ListView(
                        key: const Key('roomSideColumn'),
                        children: [
                          session,
                          const Gap.lg(),
                          highlightsPanel,
                          const Gap.lg(),
                          after,
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case Breakpoint.compact:
        // A phone: the pages fill the screen, the room slides up over them.
        return KeyedSubtree(
          key: const Key('defenceRoom'),
          child: PageShell(
            scrollable: false,
            kicker: defence.label,
            title: thesisTitle ?? defence.label,
            children: [
              ...redefenceLink,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        bottom: box.maxHeight * 0.12,
                        child: pane,
                      ),
                      DraggableScrollableSheet(
                        key: const Key('roomSheet'),
                        initialChildSize: 0.35,
                        minChildSize: 0.12,
                        maxChildSize: 0.95,
                        builder: (context, scroll) => Material(
                          color: p.canvas,
                          elevation: 8,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(16)),
                          child: ListView(
                            controller: scroll,
                            padding: const EdgeInsets.all(AppTokens.sm),
                            children: [
                              Center(
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  margin: const EdgeInsets.only(
                                      bottom: AppTokens.sm),
                                  decoration: BoxDecoration(
                                    color: p.rule,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              highlightsPanel,
                              const Gap.md(),
                              session,
                              const Gap.md(),
                              after,
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case Breakpoint.medium:
        return KeyedSubtree(
          key: const Key('defenceRoom'),
          child: PageShell(
            maxWidth: AppTokens.measureWide,
            kicker: defence.label,
            title: thesisTitle ?? defence.label,
            children: [
              ...redefenceLink,
              stacked,
              const Gap.lg(),
              SizedBox(
                height: (MediaQuery.sizeOf(context).height * 0.8)
                    .clamp(480.0, 1100.0),
                child: pane,
              ),
            ],
          ),
        );
    }
  }
}
