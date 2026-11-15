import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/features/defence/defence_mode_gate.dart';
import 'package:ethesishub/features/dashboard/switch_mode_notice.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/grades_table.dart';
import 'package:ethesishub/features/defence/redefence_notice.dart';
import 'package:ethesishub/features/defence/remarks_view.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

/// Research Form 5c, the other half: release, deliberation and the
/// recorded verdict.
///
/// The pre-release count is gated on ROLE, never on whether a stream
/// happened to return data. The rules grant the adviser `get, list`
/// on `evaluations` unconditionally, so [defenceEvaluationsProvider] is
/// safe to open for them before release, but the same rules still deny
/// that list to a panelist until release, so opening it for a panelist
/// here would surface a `permission-denied` this screen would then have
/// to explain away. `fake_cloud_firestore` enforces no rules, so a
/// role-blind screen looks fine in every Dart test and fails live; that
/// is why this branches on `isAdviser`/`released`, not on the async
/// state the stream happens to be in.
class DefenceGradesScreen extends ConsumerStatefulWidget {
  const DefenceGradesScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<DefenceGradesScreen> createState() =>
      _DefenceGradesScreenState();
}

class _DefenceGradesScreenState extends ConsumerState<DefenceGradesScreen> {
  bool _releasing = false;
  String? _releaseError;

  bool _recording = false;
  String? _recordError;
  PassFail? _verdictSelection;

  Future<void> _release(String defenceId, String adviserUid) async {
    if (_releasing) return;

    final confirmed = await confirmAction(
      context,
      title: 'Release the evaluations?',
      message:
          'The panel, the Coordinator and the Dean will see every score and '
          'comment. The students will see the written remarks only, not the '
          'scores. This cannot be undone.',
      confirmLabel: 'Release',
      confirmKey: const Key('confirmRelease'),
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _releasing = true;
      _releaseError = null;
    });
    try {
      await ref
          .read(defenceRepositoryProvider)
          .releaseEvaluations(defenceId: defenceId, adviserUid: adviserUid);
      // Best-effort, after the release, swallowing its own failure.
      try {
        await ref
            .read(auditServiceProvider)
            .log(
              actorUid: adviserUid,
              action: 'evaluations.released',
              targetType: 'defence',
              targetId: defenceId,
            );
      } catch (_) {
        /* audit must never block the action */
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _releaseError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _releaseError =
              'Could not release these evaluations. '
              'Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  /// Takes the verdict rather than reading [_verdictSelection], so the
  /// value that reaches Firestore is the one the gate approved. A Pass the
  /// passing-mark gate forbids arrives here as null and is refused.
  Future<void> _recordVerdict(
    String defenceId,
    String adviserUid,
    PassFail? verdict,
  ) async {
    if (_recording || verdict == null) return;

    final pass = verdict == PassFail.pass;
    final confirmed = await confirmAction(
      context,
      title: 'Record a ${pass ? 'Pass' : 'Fail'} verdict?',
      message:
          'This is the panel\'s decision and goes on the permanent '
          'record.',
      confirmLabel: 'Record ${pass ? 'Pass' : 'Fail'}',
      confirmKey: const Key('confirmVerdict'),
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _recording = true;
      _recordError = null;
    });
    try {
      await ref
          .read(defenceRepositoryProvider)
          .recordVerdict(
            defenceId: defenceId,
            adviserUid: adviserUid,
            verdict: verdict,
          );
    } on StateError catch (e) {
      if (mounted) setState(() => _recordError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _recordError = 'Could not record the verdict. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  /// The name the panelist carried when they submitted, denormalized onto
  /// the evaluation itself. Falls back to the uid only for a sheet written
  /// before the field existed: a raw uid is not an identity, but it is
  /// better than a blank cell in a column that must identify someone.
  String _evaluatorLabel(Evaluation e) =>
      e.evaluatorName.isNotEmpty ? e.evaluatorName : e.evaluatorUid;

  /// A fourth private copy of this, matching `defence_room_screen.dart`
  /// and `schedule_defence_screen.dart`: `intl` for one format string is
  /// the heavier dependency, and that is the reason already recorded in
  /// `defences_list.dart`.
  String _formatDateTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'am' : 'pm';
    return '${local.day}/${local.month}/${local.year} at $h:$m$ampm';
  }

  Widget _framed(List<Widget> children, {String? title, String? subtitle}) =>
      KeyedSubtree(
        key: const Key('grades'),
        child: PageShell(
          maxWidth: 1000,
          kicker: subtitle == null ? null : 'Research Form 5c, $subtitle',
          title: title,
          children: children,
        ),
      );

  /// The pre-release block. Everything here is decided from `defence`
  /// and, for the adviser only, [defenceEvaluationsProvider]: a
  /// panelist never opens that stream before release (see the class doc).
  List<Widget> _preRelease(
    BuildContext context,
    Defence defence,
    String? uid,
    bool isAdviser,
    bool isGrader,
  ) {
    // Every panelist, plus the Coordinator and the Dean, each file a sheet.
    final total = defence.requiredEvaluations;

    if (isAdviser) {
      final evalsAsync = ref.watch(
        defenceEvaluationsProvider(widget.defenceId),
      );
      if (evalsAsync.isLoading) {
        return const [
          LoadingState(
            key: Key('gradesLoading'),
            label: 'Loading evaluations…',
          ),
        ];
      }
      if (evalsAsync.hasError) {
        return [
          ErrorState(
            error: evalsAsync.error,
            message: 'Could not load these evaluations.',
          ),
        ];
      }
      final submitted = evalsAsync.valueOrNull ?? const <Evaluation>[];
      final count = submitted.length;
      // The release is judged on the uids RECORDED on the defence, the
      // very list the rules read, and on who they are rather than how many:
      // every panelist must be among them.
      final outstanding = defence.evaluationsOutstanding(defence.submittedUids);
      final canRelease = outstanding == 0;
      // Sheets that exist but were never recorded: submitted before the
      // record was kept. They count on screen yet not for release, so say
      // what unlocks it rather than leave a button that looks stuck.
      final unrecorded =
          defence.evaluationsOutstanding(
                submitted.map((e) => e.evaluatorUid),
              ) ==
              0 &&
          !canRelease;
      return [
        Text(
          '$count of $total have submitted',
          key: const Key('submittedCount'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        // Names, not scores: §6 keeps every number off this screen until
        // release, and the mitigation only works if the adviser can see
        // WHO the count is missing rather than a bare fraction.
        //
        // DELIBERATE OMISSION: §6 asks for who has not submitted as well,
        // and that half is not built. Naming an absent panelist needs
        // their name, and the defence document carries `panelUids` only
        // no names, so the missing half would mean either a fan-out
        // of profile reads per row or another denormalization onto the
        // defence. Recorded here so the next reader knows it was decided
        // rather than missed.
        if (submitted.isNotEmpty) ...[
          const Gap.sm(),
          Text(
            submitted.map(_evaluatorLabel).join(', '),
            key: const Key('submittedNames'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const Gap.lg(),
        if (_releaseError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _releaseError!,
              key: const Key('releaseError'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (unrecorded)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'All sheets are in, but some were not recorded. Each grader must save their sheet again.',
              key: const Key('unrecordedNote'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        // Locked until every grader, every panelist included, has
        // submitted. A disabled button that says why it is disabled.
        FilledButton(
          key: const Key('releaseEvaluations'),
          onPressed: _releasing || !canRelease
              ? null
              : () => _release(widget.defenceId, uid!),
          child: Text(
            _releasing
                ? 'Releasing…'
                : !canRelease
                ? 'Waiting on $outstanding more '
                      'evaluation${outstanding == 1 ? '' : 's'}'
                : 'Release evaluations',
          ),
        ),
      ];
    }

    if (isGrader) {
      final mineAsync = ref.watch(myEvaluationProvider(widget.defenceId));
      if (mineAsync.isLoading) {
        return const [
          LoadingState(key: Key('gradesLoading'), label: 'Loading your sheet…'),
        ];
      }
      if (mineAsync.hasError) {
        return [
          ErrorState(
            error: mineAsync.error,
            message: 'Could not load your evaluation.',
          ),
        ];
      }
      final submitted = mineAsync.valueOrNull != null;
      return [
        Text(
          submitted
              ? 'Submitted. The adviser releases the grades once every sheet '
                    'is in.'
              : 'You have not submitted your evaluation yet.',
          key: const Key('mySubmissionStatus'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ];
    }

    return const [
      Text(
        'These evaluations have not been released yet.',
        key: Key('notReleasedNotice'),
      ),
    ];
  }

  /// What the release gives the group: the panel's written remarks and the
  /// verdict, and never a score. Reads [defenceRemarksProvider], the only
  /// evaluation data the rules let the group's leader open.
  List<Widget> _leaderPostRelease(
    BuildContext context,
    Defence defence,
    String? uid,
  ) {
    final remarksAsync = ref.watch(defenceRemarksProvider(widget.defenceId));
    if (remarksAsync.isLoading) {
      return const [
        LoadingState(key: Key('gradesLoading'), label: 'Loading remarks…'),
      ];
    }
    if (remarksAsync.hasError) {
      return [
        ErrorState(
          error: remarksAsync.error,
          message: 'Could not load the panel\'s remarks.',
        ),
      ];
    }
    final remarks = remarksAsync.valueOrNull ?? const <EvaluationRemarks>[];
    // Nothing written by anyone is one state; some panelists silent is
    // another, and those cards say so rather than vanish.
    final anyWritten = remarks.any((r) => r.comments.isNotEmpty);

    return [
      Text(
        'Your adviser has released the panel\'s written remarks on your '
        '${defence.label.toLowerCase()}. Open a panelist to read theirs. '
        'Scores are not shown to the group.',
        key: const Key('leaderGradesIntro'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const Gap.md(),
      if (!anyWritten)
        const EmptyState(
          key: Key('noRemarks'),
          icon: Icons.notes_rounded,
          title: 'The panel wrote no remarks',
          message: 'Nothing was written on the evaluation sheets.',
        )
      else
        RemarksGrid(remarks: remarks),
      const Gap.md(),
      Panel(
        title: 'Panel verdict',
        icon: Icons.gavel_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _verdictBlock(context, defence, uid, false, null),
        ),
      ),
    ];
  }

  /// Post-release: [defenceEvaluationsProvider] is open to the adviser, the
  /// panel, the Coordinator and the Dean. The group's leader is not among
  /// them: they read [_leaderPostRelease] instead, which has no scores.
  List<Widget> _postRelease(
    BuildContext context,
    Defence defence,
    String? uid,
    bool isAdviser,
  ) {
    final evalsAsync = ref.watch(defenceEvaluationsProvider(widget.defenceId));

    if (evalsAsync.isLoading) {
      return const [
        LoadingState(key: Key('gradesLoading'), label: 'Loading evaluations…'),
      ];
    }
    if (evalsAsync.hasError) {
      return [
        ErrorState(
          error: evalsAsync.error,
          message: 'Could not load these evaluations.',
        ),
      ];
    }

    final evaluations = evalsAsync.valueOrNull ?? const <Evaluation>[];

    // One source of truth for the mean. The number the panel deliberates
    // over and the number that gates the verdict must never drift apart, so
    // the display and the Pass/Fail gate both read this one value. Null only
    // when nothing was submitted, in which case there is nothing to gate on.
    final mean = evaluations.isEmpty
        ? null
        : evaluations.fold<int>(0, (a, b) => a + b.total) / evaluations.length;

    final children = <Widget>[
      if (evaluations.isEmpty)
        const EmptyState(
          key: Key('noEvaluations'),
          icon: Icons.assignment_late_outlined,
          title: 'No evaluations were submitted',
          message: 'These evaluations were released with none on file.',
        )
      else ...[
        // Criteria down, panelists across: eleven rows against a few
        // columns, so the numbers a panel disagrees over (one criterion,
        // across panelists) sit in a single row. The criterion column stays
        // put and the panelists' columns slide, so a row keeps its label.
        GradesTable(evaluations: evaluations, evaluatorLabel: _evaluatorLabel),
        const Gap.lg(),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Panel mean',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    Text(
                      // One decimal place: 83.5 and 84.4 must not both
                      // read as 84.
                      mean!.toStringAsFixed(1),
                      key: const Key('panelMean'),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              ToneBadge(
                label: meanClearsPassingMark(mean)
                    ? 'At or above $passingMark'
                    : 'Below $passingMark',
                tone: meanClearsPassingMark(mean)
                    ? Tone.endorsed
                    : Tone.returned,
              ),
            ],
          ),
        ),
        if (contentKeys.any(
          (k) => evaluations.any((e) => e.comments[k] != null),
        )) ...[
          const Gap.md(),
          Panel(
            title: 'Remarks by criterion',
            icon: Icons.notes_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final key in contentKeys)
                  if (evaluations.any((e) => e.comments[key] != null))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            criterionFor(key)?.label ?? key,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          for (final e in evaluations)
                            if (e.comments[key] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '${_evaluatorLabel(e)}: ${e.comments[key]}',
                                ),
                              ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
      const Gap.md(),
      Panel(
        title: 'Panel verdict',
        icon: Icons.gavel_outlined,
        emphasis: isAdviser && !defence.hasVerdict,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _verdictBlock(context, defence, uid, isAdviser, mean),
        ),
      ),
    ];

    return children;
  }

  List<Widget> _verdictBlock(
    BuildContext context,
    Defence defence,
    String? uid,
    bool isAdviser,
    double? mean,
  ) {
    if (defence.hasVerdict) {
      return [
        Text(
          'Panel verdict: ${defence.panelVerdict?.label ?? '—'}',
          key: const Key('verdict'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Gap.sm(),
        Text(
          // "the adviser", not a name and not a uid. The rules pin
          // verdictRecordedBy == request.auth.uid on the only arm that
          // can write it, and only the adviser passes that arm, so the
          // scribe is always the adviser and needs no second
          // denormalization to say so. The spec wants a reader to see that
          // this was transcribed rather than decided, which is what
          // this sentence says.
          defence.verdictRecordedAt != null
              ? 'Recorded by the adviser on '
                    '${_formatDateTime(defence.verdictRecordedAt!)}.'
              : 'Recorded by the adviser.',
          key: const Key('verdictScribe'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const Gap.md(),
        RedefenceNotice(defence: defence),
      ];
    }

    if (!isAdviser) {
      return const [
        Text(
          'The adviser records the verdict after the panel deliberates.',
          key: Key('verdictPending'),
        ),
      ];
    }

    // The mean decides which verdict is open, both ways. Below the passing
    // mark only Fail is allowed; at or above it only Pass is, so Fail
    // is locked. Exactly one of the two is ever open. A null mean means
    // nothing was submitted, so there is nothing to gate on: the release
    // gate upstream already prevents a verdict in that state.
    final passLocked = mean != null && !meanClearsPassingMark(mean);
    final failLocked = mean != null && meanClearsPassingMark(mean);
    // Never hand the record button a selection the gate forbids, even if
    // the selection drifted there before the grades resolved.
    final selection =
        (passLocked && _verdictSelection == PassFail.pass) ||
            (failLocked && _verdictSelection == PassFail.fail)
        ? null
        : _verdictSelection;

    return [
      Text(
        'Record the panel\'s decision.',
        key: const Key('verdictCaption'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (passLocked) ...[
        const Gap.sm(),
        Text(
          // The precise mean, not the one-decimal figure shown above: 74.96
          // displays as "75.0", and without the exact number here a locked
          // Pass reads as a broken button rather than a rule.
          'Mean ${mean.toStringAsFixed(2)} is under $passingMark, so only '
          'Fail is allowed.',
          key: const Key('verdictLocked'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      if (failLocked) ...[
        const Gap.sm(),
        Text(
          // The precise mean, for the same reason as the Pass lock above.
          'Mean ${mean.toStringAsFixed(2)} is $passingMark or more, so only '
          'Pass is allowed.',
          key: const Key('verdictFailLocked'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const Gap.md(),
      SegmentedButton<PassFail>(
        segments: [
          ButtonSegment(
            value: PassFail.pass,
            label: const Text('Pass'),
            enabled: !passLocked,
          ),
          ButtonSegment(
            value: PassFail.fail,
            label: const Text('Fail'),
            enabled: !failLocked,
          ),
        ],
        selected: {?selection},
        emptySelectionAllowed: true,
        onSelectionChanged: _recording
            ? null
            : (sel) => setState(() => _verdictSelection = sel.firstOrNull),
      ),
      const Gap.sm(),
      if (_recordError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            _recordError!,
            key: const Key('recordError'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      FilledButton(
        key: const Key('recordVerdict'),
        onPressed: !_recording && selection != null
            ? () => _recordVerdict(widget.defenceId, uid!, selection)
            : null,
        child: Text(_recording ? 'Recording…' : 'Record verdict'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final defenceAsync = ref.watch(defenceProvider(widget.defenceId));
    final uid = ref.watch(signedInUidProvider);

    if (defenceAsync.isLoading) {
      return _framed(const [
        LoadingState(key: Key('gradesLoading'), label: 'Loading defense…'),
      ]);
    }
    if (defenceAsync.hasError) {
      return _framed([
        ErrorState(
          error: defenceAsync.error,
          message: 'Could not load this defense.',
        ),
      ]);
    }
    final defence = defenceAsync.valueOrNull;
    if (defence == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defense not found',
          message: 'This defense no longer exists.',
        ),
      ]);
    }

    // A faculty member who holds both capabilities must be in the mode that
    // matches their seat on THIS defense: adviser mode for the adviser,
    // panelist mode for a panelist. Anything else is turned away here, before
    // a single highlight, grade or evaluation is read.
    final modeGate = checkDefenceModeGate(ref, defence, uid);
    if (modeGate.gate == DefenceModeGate.loading) {
      return _framed(const [LoadingState(label: 'Checking your mode…')]);
    }
    if (modeGate.gate == DefenceModeGate.blocked) {
      return _framed([DefenceModeBlock(needed: modeGate.needed!)]);
    }

    final isAdviser = uid != null && uid == defence.adviserUid;
    // Graders: the panel, and the Coordinator and the Dean (2026-10-01).
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    final isGrader =
        uid != null &&
        !isAdviser &&
        (defence.panelUids.contains(uid) ||
            role == UserRole.coordinator ||
            role == UserRole.dean);
    // The group's leader: the student who owns the thesis. Not a grader and
    // not on the panel, so the mode switch never applies to them.
    final isLeader =
        uid != null && !isAdviser && !isGrader && uid == defence.leaderUid;
    final released = defence.evaluationsReleased;

    final children = released
        ? (isLeader
              ? _leaderPostRelease(context, defence, uid)
              : _postRelease(context, defence, uid, isAdviser))
        : _preRelease(context, defence, uid, isAdviser, isGrader);

    final isPanelMember = uid != null && defence.panelUids.contains(uid);
    final modeNotice = isAdviser
        ? const SwitchModeNotice(
            needed: FacultyMode.adviser,
            message: 'Switch to Adviser mode to release grades.',
          )
        : isPanelMember
        ? const SwitchModeNotice(
            needed: FacultyMode.panelist,
            message: 'Switch to Panelist mode to evaluate.',
          )
        : null;

    return _framed(
      [?modeNotice, ...children],
      title: defence.label,
      subtitle: 'Grades',
    );
  }
}
