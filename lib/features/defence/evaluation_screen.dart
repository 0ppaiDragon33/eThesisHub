import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/forms/form5c_data.dart';
import 'package:ethesishub/features/forms/form5c_pdf.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// Research Form 5c — one panelist's own score sheet for a defence.
///
/// The adviser branch is decided from [defenceProvider] alone, before
/// [myEvaluationProvider] is even consulted — the same discipline
/// `defence_room_screen.dart` uses for its leader branch. An adviser is
/// never in `panelUids` (D37: they cannot mark at arm's length after months
/// on the thesis), so their evaluation stream would simply error on a
/// permission-denied read once real security rules are in force; waiting on
/// it here would show "Could not load your evaluation." in place of the
/// actual reason.
class EvaluationScreen extends ConsumerStatefulWidget {
  const EvaluationScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends ConsumerState<EvaluationScreen> {
  final Map<String, int> _scores = {};
  final Map<String, TextEditingController> _comments = {
    for (final key in contentKeys) key: TextEditingController(),
  };
  PassFail? _rating;

  /// Guards the one-time seed from [myEvaluationProvider]. Without it, every
  /// later snapshot of the panelist's own sheet -- including the echo of the
  /// write this screen itself just made -- would overwrite whatever they are
  /// currently typing.
  bool _seeded = false;

  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _seedFrom(Evaluation? evaluation) {
    if (_seeded) return;
    _seeded = true;
    if (evaluation == null) return;
    _scores.addAll(evaluation.scores);
    evaluation.comments.forEach((key, value) {
      _comments[key]?.text = value;
    });
    _rating = evaluation.rating;
  }

  /// The stepper's whole reason to exist is that a panelist scores eleven
  /// criteria on a phone without summoning a numeric keypad eleven times --
  /// which only holds if the +/- controls are themselves comfortable to
  /// thumb. Kept at Material's own 48x48 minimum tap target rather than
  /// shrunk to fit a test surface; the test harness grows to fit the
  /// product, not the other way around (see `useTallSurface` in the test
  /// file).
  Widget _stepperButton({
    required Key key,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      key: key,
      icon: Icon(icon, size: 20),
      onPressed: onPressed,
    );
  }

  void _adjust(String key, int delta, int weight) {
    final current = _scores[key] ?? 0;
    setState(() {
      _scores[key] = (current + delta).clamp(0, weight);
    });
  }

  Future<void> _submit(String uid, String name) async {
    if (_submitting) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await ref.read(defenceRepositoryProvider).submitEvaluation(
            defenceId: widget.defenceId,
            evaluatorUid: uid,
            evaluatorName: name,
            scores: _scores,
            comments: {
              for (final e in _comments.entries)
                if (e.value.text.isNotEmpty) e.key: e.value.text,
            },
            rating: _rating!,
          );
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _submitError = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _submitError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _submitError = e.code == 'permission-denied'
            ? 'You do not have permission to submit this evaluation '
                '[permission-denied].'
            : 'Could not submit this evaluation. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _submitError =
            'Could not submit this evaluation. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// The title this sheet prints: the approved candidate's text, not
  /// `thesis.workingTitle`. Mirrors `_ArchiveQueueRowState._approvedTitle`
  /// in `archive_queue_screen.dart` rather than inventing a second
  /// resolution of the same fact — the working title is what the group
  /// typed at creation, the approved one is what the panel and the dean
  /// actually signed off, and only the latter belongs on a signed record.
  String? _approvedTitle(Thesis thesis, List<CandidateTitle> candidates) {
    final approvedId = thesis.approvedTitleId;
    if (approvedId == null) return null;
    for (final c in candidates) {
      if (c.id == approvedId && c.titleText.isNotEmpty) return c.titleText;
    }
    return null;
  }

  /// Builds and shares this panelist's own Form 5c.
  ///
  /// Reachable both before and after release (D59: a panelist scores their
  /// own sheet under M4's unconditional access to it — release changes
  /// nothing about who may read it, only whether it may still be edited).
  /// Every read here is a one-shot `ref.read(...).future`/`fetch`, not a
  /// watch: this runs once, on tap, exactly like `ThesisStatusScreen`'s
  /// Form 1 handler.
  Future<void> _downloadForm5c(
      Defence defence, Evaluation evaluation, String uid) async {
    try {
      final thesis =
          await ref.read(thesisByIdProvider(defence.thesisId).future);
      if (thesis == null) {
        throw StateError('This thesis could not be found.');
      }

      final candidates =
          await ref.read(candidateTitlesProvider(thesis.id).future);
      final title = _approvedTitle(thesis, candidates) ?? thesis.workingTitle;

      // Empty when the directory has no entry for this panelist —
      // `Form5cData` and its renderer both treat that as honest, not an
      // error, so no placeholder is invented here either.
      final entry =
          await ref.read(facultyDirectoryRepositoryProvider).fetch(uid);

      final data = Form5cData.assemble(
        thesis: thesis,
        defence: defence,
        evaluation: evaluation,
        title: title,
        evaluatorField: entry?.specialization ?? '',
      );
      await Printing.sharePdf(
        bytes: await buildForm5cPdf(data),
        filename: 'Form5c-${defence.id}-$uid.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate Form 5c: $e')),
      );
    }
  }

  /// Wraps every non-content state in the same frame the loaded screen
  /// uses, so a panelist still loading the defence or their sheet is never
  /// left on a bare, unnavigable page.
  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('evaluation'),
        child: PageShell(children: children),
      );

  @override
  Widget build(BuildContext context) {
    final defenceAsync = ref.watch(defenceProvider(widget.defenceId));
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    // The panelist's own profile, for the name stored on the sheet. Read
    // through the same `me?.fullName ?? ''` shape `defence_room_screen`
    // uses for a comment's authorName, and blocked on below for the same
    // reason: the name goes into a permanent academic record at the
    // moment of the act, and submitting while the profile is still in
    // flight would file the sheet under nobody.
    final meAsync = ref.watch(currentUserProvider);

    // Each async source gets its own isLoading/hasError branch, checked
    // apart from the other -- collapsing them would tell a panelist whose
    // own sheet is merely still connecting that the defence itself does not
    // exist, or vice versa.
    if (defenceAsync.isLoading) {
      return _framed(
        const [LoadingState(key: Key('evaluationLoading'), label: 'Loading defence…')],
      );
    }
    if (defenceAsync.hasError) {
      return _framed([
        ErrorState(
          error: defenceAsync.error,
          message: 'Could not load this defence.',
        ),
      ]);
    }
    if (meAsync.isLoading) {
      return _framed(
        const [
          LoadingState(
              key: Key('evaluationLoading'), label: 'Loading your profile…'),
        ],
      );
    }
    if (meAsync.hasError) {
      return _framed([
        ErrorState(
          error: meAsync.error,
          message: 'Could not load your profile.',
        ),
      ]);
    }
    final myName = meAsync.valueOrNull?.fullName ?? '';

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

    // Decided from `defence` alone, before `myEvaluationProvider` is even
    // watched. An adviser advises one group across months and is barred
    // from scoring it at arm's length (D37) -- they are never in
    // `panelUids`, so consulting their evaluation stream first would only
    // add a permission error to a page that has nothing to score anyway.
    final isAdviser = uid != null && uid == defence.adviserUid;
    if (isAdviser) {
      return _framed([
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Advisers comment on a defence but do not score it. Your '
            'remarks are in the defence log.',
            key: Key('adviserRefusal'),
          ),
        ),
        FilledButton(
          key: const Key('goToGrades'),
          // The full path, and `push`, not `go`: '/grades' is not a route
          // this app has, so it landed the adviser on GoRouter's error
          // page and took the shell with it; and this is a deep screen
          // under the Defences destination, so it stacks rather than
          // replacing.
          onPressed: () => context
              .push('/defence/room/${widget.defenceId}/grades'),
          child: const Text('Go to grades'),
        ),
      ]);
    }

    final evaluationAsync = ref.watch(myEvaluationProvider(widget.defenceId));
    if (evaluationAsync.isLoading) {
      return _framed(
        const [
          LoadingState(
              key: Key('evaluationLoading'), label: 'Loading your sheet…'),
        ],
      );
    }
    if (evaluationAsync.hasError) {
      return _framed([
        ErrorState(
          error: evaluationAsync.error,
          message: 'Could not load your evaluation.',
        ),
      ]);
    }

    final isPanelist = uid != null && defence.panelUids.contains(uid);
    if (!isPanelist) {
      return _framed(const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'You are not on the panel for this defence.',
            key: Key('notPanelist'),
          ),
        ),
      ]);
    }

    final existing = evaluationAsync.valueOrNull;
    _seedFrom(existing);

    // A sheet already on file. D44: it stays editable right up to the
    // seal, so the control has to say "Update", not "Submit" -- a
    // panelist who has already filed one and sees "Submit evaluation"
    // has no way to tell whether they are about to add a second.
    final hasSheet = existing != null;
    final released = defence.evaluationsReleased;
    final locked = released || _submitting;
    final complete = _scores.length == evaluationCriteria.length;

    return KeyedSubtree(
      key: const Key('evaluation'),
      child: PageShell(
        title: defence.type.label,
        subtitle: 'Research Form 5c',
        children: [
          if (released)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'These evaluations have been released. This sheet is now '
                'part of the record.',
                key: const Key('releasedNotice'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (final section in EvaluationSection.values) ...[
            Text(section.label, style: Theme.of(context).textTheme.titleMedium),
            const Gap.sm(),
            for (final c in evaluationCriteria.where((c) => c.section == section))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('${c.label} (${c.weight})'),
                        ),
                        _stepperButton(
                          key: Key('minus_${c.key}'),
                          icon: Icons.remove,
                          onPressed:
                              locked ? null : () => _adjust(c.key, -1, c.weight),
                        ),
                        SizedBox(
                          width: 24,
                          child: Text(
                            '${_scores[c.key] ?? 0}',
                            key: Key('score_${c.key}'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        _stepperButton(
                          key: Key('plus_${c.key}'),
                          icon: Icons.add,
                          onPressed:
                              locked ? null : () => _adjust(c.key, 1, c.weight),
                        ),
                      ],
                    ),
                    if (c.prompt.isNotEmpty)
                      Text(
                        c.prompt,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (c.takesComment) ...[
                      const Gap.sm(),
                      TextField(
                        key: Key('comment_${c.key}'),
                        controller: _comments[c.key],
                        enabled: !locked,
                        decoration: const InputDecoration(labelText: 'Remarks'),
                        minLines: 1,
                        maxLines: 3,
                      ),
                    ],
                  ],
                ),
              ),
            Text(
              '${section.label} subtotal: '
              '${_scores.entries.where((e) => criterionFor(e.key)?.section == section).fold<int>(0, (a, b) => a + b.value)} '
              '/ ${EvaluationSection.sectionTotal}',
              key: Key(
                'sectionTotal_${section == EvaluationSection.content ? 'content' : 'presentation'}',
              ),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Gap.md(),
          ],
          Text('Final grade', style: Theme.of(context).textTheme.labelMedium),
          Text(
            totalOf(_scores).toString(),
            key: const Key('finalGrade'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Gap.lg(),
          Text(
            'Your own rating under §8a. The panel\'s verdict is decided '
            'separately, after deliberation.',
            key: const Key('ratingIsYours'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Gap.sm(),
          SegmentedButton<PassFail>(
            segments: const [
              ButtonSegment(value: PassFail.pass, label: Text('Pass')),
              ButtonSegment(value: PassFail.fail, label: Text('Fail')),
            ],
            selected: {?_rating},
            emptySelectionAllowed: true,
            onSelectionChanged: locked
                ? null
                : (selection) =>
                    setState(() => _rating = selection.firstOrNull),
          ),
          const Gap.lg(),
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _submitError!,
                key: const Key('submitError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!released) ...[
            if (hasSheet)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'You submitted this sheet already. It can be changed '
                  'until the adviser releases the evaluations.',
                  key: const Key('editableUntilRelease'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('submitEvaluation'),
                  onPressed: !locked && complete && _rating != null
                      ? () => _submit(uid, myName)
                      : null,
                  child: Text(_submitting
                      ? (hasSheet ? 'Updating…' : 'Submitting…')
                      : (hasSheet ? 'Update evaluation' : 'Submit evaluation')),
                ),
                if (hasSheet)
                  OutlinedButton(
                    key: const Key('downloadForm5c'),
                    onPressed: () => _downloadForm5c(defence, existing, uid),
                    child: const Text('Download Form 5c'),
                  ),
              ],
            ),
          ] else if (hasSheet)
            OutlinedButton(
              key: const Key('downloadForm5c'),
              onPressed: () => _downloadForm5c(defence, existing, uid),
              child: const Text('Download Form 5c'),
            ),
        ],
      ),
    );
  }
}
