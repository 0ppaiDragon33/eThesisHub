import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
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

/// Preferred width of the grades table's first column.
///
/// A hint, not a guarantee: `DataCell` passes its own constraints down, so
/// on a narrow screen this box is squeezed smaller and the label wraps.
/// Measured — widening it to 420 changes nothing at 360dp. What it does
/// buy is a cap on a WIDE screen, where the criterion column would
/// otherwise stretch to fit "Material and Methods  /10" on one line and
/// leave the three number columns marooned at the far right.
const double _labelWidth = 150;

/// Width of each panelist column heading, and THE reason the table fits.
///
/// A numeric column's heading is laid out in its own Row that will not
/// wrap, and it is sized against cells holding one or two digits — so an
/// unboxed "Dr. Panelist One" overflows a column built for "22". Measured:
/// remove this box and the table overflows by 113px at 360dp and 39px at
/// every width above it. Boxed and allowed two lines, nothing clips.
///
/// `defence_grades_screen_test.dart` pins this with `takeException()` at
/// 360dp and at 1400dp.
const double _panelistWidth = 58;

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
      await ref
          .read(defenceRepositoryProvider)
          .releaseEvaluations(defenceId: defenceId, adviserUid: adviserUid);
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

  Future<void> _recordVerdict(String defenceId, String adviserUid) async {
    final verdict = _verdictSelection;
    if (_recording || verdict == null) return;
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
  /// before the field existed -- a raw uid is not an identity, but it is
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
        child: PageShell(title: title, subtitle: subtitle, children: children),
      );

  /// The pre-release block. Everything here is decided from `defence`
  /// and, for the adviser only, [defenceEvaluationsProvider] -- a
  /// panelist NEVER opens that stream before release (see the class doc).
  List<Widget> _preRelease(
    BuildContext context,
    Defence defence,
    String? uid,
    bool isAdviser,
    bool isPanelist,
  ) {
    final total = defence.panelUids.length;

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
      return [
        Text(
          '$count of $total panelists have submitted',
          key: const Key('submittedCount'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        // Names, not scores: §6 keeps every number off this screen until
        // release, and D40's mitigation only works if the adviser can see
        // WHO the count is missing rather than a bare fraction.
        //
        // DELIBERATE OMISSION: §6 asks for who has NOT submitted as well,
        // and that half is not built. Naming an absent panelist needs
        // their name, and the defence document carries `panelUids` only
        // -- no names -- so the missing half would mean either a fan-out
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
        FilledButton(
          key: const Key('releaseEvaluations'),
          onPressed: _releasing ? null : () => _release(widget.defenceId, uid!),
          child: Text(
            _releasing ? 'Releasing…' : 'Release $count of $total evaluations',
          ),
        ),
      ];
    }

    if (isPanelist) {
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

    final children = <Widget>[
      if (evaluations.isEmpty)
        const EmptyState(
          key: Key('noEvaluations'),
          icon: Icons.assignment_late_outlined,
          title: 'No evaluations were submitted',
          message: 'These evaluations were released with none on file.',
        )
      else ...[
        // CRITERIA DOWN, PANELISTS ACROSS -- deliberately the transpose of
        // the obvious layout, and the reason is not just width.
        //
        // Criteria are fixed at eleven forever; panelists are three, maybe
        // four. Putting the fixed-and-large count on the horizontal axis
        // guaranteed overflow on every device permanently -- fourteen
        // columns against three rows. This way it is eleven rows against
        // three columns, which fits a 360dp phone with nothing hidden.
        //
        // The stronger reason is §8b. The panel deliberates over where they
        // DISAGREE, and disagreement lives within a criterion, across
        // panelists -- which is exactly one row here. "Result: 9, 7, 6"
        // reads in a glance; laid out the other way those three numbers sat
        // in three different rows and were off-screen together. The section
        // rows also restore Form 5c's own A/B structure, which the wide
        // table flattened away.
        //
        // NO horizontal scroll, deliberately. A DataTable given unbounded
        // width -- which is what a horizontal SingleChildScrollView hands
        // it -- sizes itself to about 1260dp whatever it contains, so the
        // scroll view was CAUSING the overflow it existed to rescue.
        // Bounded by the page instead, the table lays its columns out
        // inside the width it actually has, and the long criterion labels
        // wrap rather than push it wider.
        DataTable(
          key: const Key('gradesTable'),
          columnSpacing: AppTokens.md,
          horizontalMargin: AppTokens.sm,
          // Row heights allow two lines: both the criterion labels and the
          // panelist headings wrap rather than push the table wider. See
          // [_panelistWidth], which is the box that actually decides the fit.
          dataRowMinHeight: 40,
          dataRowMaxHeight: 60,
          // A panelist's NAME is far wider than the one or two digits
          // beneath it, and a numeric column's heading is laid out in its
          // own Row that will not wrap -- so an unboxed "Dr. Panelist One"
          // overflowed a column sized for "22". Boxed and allowed two
          // lines, with the extra heading height that needs.
          headingRowHeight: 64,
          columns: [
            const DataColumn(label: Text('Criterion')),
            for (final e in evaluations)
              DataColumn(
                label: SizedBox(
                  width: _panelistWidth,
                  child: Text(
                    _evaluatorLabel(e),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                numeric: true,
              ),
          ],
          rows: [
            for (final section in EvaluationSection.values) ...[
              // A section header. DataTable gives no spanning cell, so
              // the label sits in the first column and the rest are
              // blank -- which reads correctly and keeps the row count
              // honest for anything counting rows.
              DataRow(
                key: ValueKey('section_${section.name}'),
                cells: [
                  DataCell(
                    SizedBox(
                      width: _labelWidth,
                      child: Text(
                        '${section.label} — ${EvaluationSection.sectionTotal}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                  ),
                  for (final _ in evaluations) const DataCell(Text('')),
                ],
              ),
              for (final c in evaluationCriteria.where(
                (c) => c.section == section,
              ))
                DataRow(
                  key: ValueKey('criterion_${c.key}'),
                  cells: [
                    // The weight travels with the criterion, so a 6
                    // beside "/10" and a 6 beside "/25" are not read as
                    // the same performance.
                    DataCell(
                      SizedBox(
                        width: _labelWidth,
                        // The weight travels with the criterion, so a 6
                        // beside /10 and a 6 beside /25 are not read as
                        // the same performance.
                        child: Text('${c.label}  /${c.weight}'),
                      ),
                    ),
                    for (final e in evaluations)
                      DataCell(Text('${e.scores[c.key] ?? 0}')),
                  ],
                ),
            ],
            DataRow(
              key: const ValueKey('row_total'),
              cells: [
                const DataCell(Text('Final grade')),
                for (final e in evaluations) DataCell(Text('${e.total}')),
              ],
            ),
            DataRow(
              key: const ValueKey('row_rating'),
              cells: [
                const DataCell(Text('Rating')),
                for (final e in evaluations)
                  DataCell(Text(e.rating?.label ?? '—')),
              ],
            ),
          ],
        ),
        const Gap.lg(),
        Text('Panel mean', style: Theme.of(context).textTheme.labelMedium),
        Text(
          // One decimal place, not .round(): 83.5 and 84.4 both rendered
          // as "84", on the one number the panel deliberates over.
          (evaluations.fold<int>(0, (a, b) => a + b.total) / evaluations.length)
              .toStringAsFixed(1),
          key: const Key('panelMean'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Gap.lg(),
        Text(
          'Remarks by criterion',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const Gap.sm(),
        for (final key in contentKeys)
          if (evaluations.any((e) => e.comments[key] != null))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    criterionFor(key)?.label ?? key,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  for (final e in evaluations)
                    if (e.comments[key] != null)
                      Text('${_evaluatorLabel(e)}: ${e.comments[key]}'),
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
    BuildContext context,
    Defence defence,
    String? uid,
    bool isAdviser,
  ) {
    if (defence.hasVerdict) {
      return [
        Text(
          'Panel verdict: ${defence.panelVerdict?.label ?? '—'}',
          key: const Key('verdict'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Gap.sm(),
        Text(
          // "the adviser", not a name and not a uid. The rules pin
          // verdictRecordedBy == request.auth.uid on the only arm that
          // can write it, and only the adviser passes that arm, so the
          // scribe is always the adviser and needs no second
          // denormalization to say so. D42 wants a reader to see that
          // this was transcribed rather than decided -- which is what
          // this sentence says.
          defence.verdictRecordedAt != null
              ? 'Recorded by the adviser on '
                    '${_formatDateTime(defence.verdictRecordedAt!)}, as the '
                    'panel deliberated it under §8b.'
              : 'Recorded by the adviser, as the panel deliberated it '
                    'under §8b.',
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

    return _framed(children, title: defence.type.label, subtitle: 'Grades');
  }
}
