import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// Research Form 5c, the other half: release, deliberation and the
/// recorded verdict.
///
/// The pre-release count is gated on ROLE, never on whether a stream
/// happened to return data. Task 4's rules grant the adviser `get, list`
/// on `evaluations` unconditionally, so [defenceEvaluationsProvider] is
/// safe to open for them before release -- but the same rules still deny
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
    setState(() {
      _releasing = true;
      _releaseError = null;
    });
    try {
      await ref.read(defenceRepositoryProvider).releaseEvaluations(
            defenceId: defenceId,
            adviserUid: adviserUid,
          );
    } on StateError catch (e) {
      if (mounted) setState(() => _releaseError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _releaseError = 'Could not release these evaluations. '
                'Please try again.');
      }
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  Future<void> _recordVerdict(String defenceId, String adviserUid) async {
    final verdict = _verdictSelection;
    if (_recording || verdict == null) return;
    setState(() {
      _recording = true;
      _recordError = null;
    });
    try {
      await ref.read(defenceRepositoryProvider).recordVerdict(
            defenceId: defenceId,
            adviserUid: adviserUid,
            verdict: verdict,
          );
    } on StateError catch (e) {
      if (mounted) setState(() => _recordError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _recordError = 'Could not record the verdict. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Widget _framed(List<Widget> children, {String? title, String? subtitle}) =>
      KeyedSubtree(
        key: const Key('grades'),
        child: PageShell(title: title, subtitle: subtitle, children: children),
      );

  /// The pre-release block. Everything here is decided from `defence`
  /// and, for the adviser only, [defenceEvaluationsProvider] -- a
  /// panelist NEVER opens that stream before release (see the class doc).
  List<Widget> _preRelease(BuildContext context, Defence defence, String? uid,
      bool isAdviser, bool isPanelist) {
    final total = defence.panelUids.length;

    if (isAdviser) {
      final evalsAsync =
          ref.watch(defenceEvaluationsProvider(widget.defenceId));
      if (evalsAsync.isLoading) {
        return const [
          LoadingState(
              key: Key('gradesLoading'), label: 'Loading evaluations…'),
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
      final count = evalsAsync.valueOrNull?.length ?? 0;
      return [
        Text(
          '$count of $total panelists have submitted',
          key: const Key('submittedCount'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
        FilledButton(
          key: const Key('releaseEvaluations'),
          onPressed: _releasing
              ? null
              : () => _release(widget.defenceId, uid!),
          child: Text(
              _releasing ? 'Releasing…' : 'Release $count of $total evaluations'),
        ),
      ];
    }

    if (isPanelist) {
      final mineAsync = ref.watch(myEvaluationProvider(widget.defenceId));
      if (mineAsync.isLoading) {
        return const [
          LoadingState(
              key: Key('gradesLoading'), label: 'Loading your sheet…'),
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
              ? 'You have submitted your evaluation. The panel\'s grades '
                  'are released by the adviser once every evaluation is in.'
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

  /// Post-release: [defenceEvaluationsProvider] is open to everyone with a
  /// stake in the defence, adviser and panel alike.
  List<Widget> _postRelease(
      BuildContext context, Defence defence, String? uid, bool isAdviser) {
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

    final children = <Widget>[
      if (evaluations.isEmpty)
        const EmptyState(
          key: Key('noEvaluations'),
          icon: Icons.assignment_late_outlined,
          title: 'No evaluations were submitted',
          message: 'These evaluations were released with none on file.',
        )
      else ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            key: const Key('gradesTable'),
            columns: [
              const DataColumn(label: Text('Panelist')),
              for (final c in evaluationCriteria) DataColumn(label: Text(c.label)),
              const DataColumn(label: Text('Total')),
              const DataColumn(label: Text('Rating')),
            ],
            rows: [
              for (final e in evaluations)
                DataRow(cells: [
                  DataCell(Text(e.evaluatorUid)),
                  for (final c in evaluationCriteria)
                    DataCell(Text('${e.scores[c.key] ?? 0}')),
                  DataCell(Text('${e.total}')),
                  DataCell(Text(e.rating?.label ?? '—')),
                ]),
            ],
          ),
        ),
        const Gap.lg(),
        Text(
          'Panel mean',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(
          (evaluations.fold<int>(0, (a, b) => a + b.total) /
                  evaluations.length)
              .round()
              .toString(),
          key: const Key('panelMean'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Gap.lg(),
        Text('Remarks by criterion',
            style: Theme.of(context).textTheme.labelMedium),
        const Gap.sm(),
        for (final key in contentKeys)
          if (evaluations.any((e) => e.comments[key] != null))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(criterionFor(key)?.label ?? key,
                      style: Theme.of(context).textTheme.bodyLarge),
                  for (final e in evaluations)
                    if (e.comments[key] != null)
                      Text('${e.evaluatorUid}: ${e.comments[key]}'),
                ],
              ),
            ),
      ],
      const Gap.lg(),
      ..._verdictBlock(context, defence, uid, isAdviser),
    ];

    return children;
  }

  List<Widget> _verdictBlock(
      BuildContext context, Defence defence, String? uid, bool isAdviser) {
    if (defence.hasVerdict) {
      return [
        Text(
          'Panel verdict: ${defence.panelVerdict?.label ?? '—'}',
          key: const Key('verdict'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Gap.sm(),
        Text(
          'Recorded by ${defence.verdictRecordedBy}',
          key: const Key('verdictScribe'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ];
    }

    if (!isAdviser) {
      return const [
        Text(
          'The panel deliberates over the released grades under §8b. The '
          'adviser records the verdict once decided.',
          key: Key('verdictPending'),
        ),
      ];
    }

    return [
      Text(
        'Record the panel\'s deliberated decision under §8b. This is a '
        'transcription of what the panel decided, not a computed grade.',
        key: const Key('verdictCaption'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const Gap.sm(),
      SegmentedButton<PassFail>(
        segments: const [
          ButtonSegment(value: PassFail.pass, label: Text('Pass')),
          ButtonSegment(value: PassFail.fail, label: Text('Fail')),
        ],
        selected: {?_verdictSelection},
        emptySelectionAllowed: true,
        onSelectionChanged: _recording
            ? null
            : (selection) =>
                setState(() => _verdictSelection = selection.firstOrNull),
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
        onPressed: !_recording && _verdictSelection != null
            ? () => _recordVerdict(widget.defenceId, uid!)
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
        LoadingState(key: Key('gradesLoading'), label: 'Loading defence…'),
      ]);
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

    final isAdviser = uid != null && uid == defence.adviserUid;
    final isPanelist = uid != null && defence.panelUids.contains(uid);
    final released = defence.evaluationsReleased;

    final children = released
        ? _postRelease(context, defence, uid, isAdviser)
        : _preRelease(context, defence, uid, isAdviser, isPanelist);

    return _framed(
      children,
      title: defence.type.label,
      subtitle: 'Grades',
    );
  }
}
