import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The coordinator's screen for scheduling a pre-oral or final defence.
///
/// Reads the thesis to snapshot `panelUids`, `adviserUid` and `leaderUid` at
/// the moment of scheduling -- see [Defence]'s own doc comment for why these
/// are snapshots rather than a live reference. `panelUids` and `leaderUid`
/// are passed straight through below, never sorted, de-duplicated or
/// rebuilt: the security rule validating the create is an array-equality
/// check that includes ORDER --
/// `incoming().panelUids == thesisOf(incoming().thesisId).panelistUids` --
/// so any reordering here passes every Dart test (fake_cloud_firestore
/// enforces no rules) and is denied in production. `adviserUid` gets one
/// exception: a null value is refused client-side before the write (see
/// `_schedule`), rather than sent through as `''`, because the create rule
/// would deny `''` against a stored `null` and blame the coordinator's
/// permissions for what is actually missing data.
class ScheduleDefenceScreen extends ConsumerStatefulWidget {
  const ScheduleDefenceScreen({super.key, required this.thesisId});

  final String thesisId;

  @override
  ConsumerState<ScheduleDefenceScreen> createState() =>
      _ScheduleDefenceScreenState();
}

class _ScheduleDefenceScreenState
    extends ConsumerState<ScheduleDefenceScreen> {
  DefenceType _type = DefenceType.preOral;
  final _venueController = TextEditingController();
  late DateTime _scheduledAt;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A week out, mid-morning: a sensible default so the form is valid
    // without forcing a picker interaction, while still leaving the field
    // fully editable.
    final now = DateTime.now();
    _scheduledAt = DateTime(now.year, now.month, now.day + 7, 9);
  }

  @override
  void dispose() {
    _venueController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt,
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    // Guard every setState after an await with mounted: the dialog can
    // outlive the screen if the coordinator navigates away mid-pick.
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt),
    );
    if (time == null || !mounted) return;

    setState(() {
      _scheduledAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} $hour:$minute $period';
  }

  Future<void> _schedule({
    required Thesis thesis,
    required String coordinatorUid,
  }) async {
    if (_busy) return;

    final adviserUid = thesis.adviserUid;
    // Unreachable through the app: a thesis only reaches titleApproved after
    // nomination completes, and that write sets adviserUid atomically. But if
    // it ever IS null, the create rule compares '' against null, denies the
    // write, and the screen would blame the coordinator's permissions for a
    // data problem they cannot act on.
    if (adviserUid == null || adviserUid.isEmpty) {
      if (mounted) {
        setState(() => _error =
            'This thesis has no adviser on record, so a defence cannot be '
            'scheduled for it yet.');
      }
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final id = await ref.read(defenceRepositoryProvider).schedule(
            thesisId: thesis.id,
            type: _type,
            scheduledAt: _scheduledAt,
            venue: _venueController.text,
            // Snapshots, verbatim -- see the class doc comment above.
            panelUids: thesis.panelistUids,
            adviserUid: adviserUid,
            leaderUid: thesis.leaderUid,
            createdBy: coordinatorUid,
          );
      // '/defence/room/:defenceId' is the path Task 11 registers for the
      // defence room (Task 8). Matching it exactly here, before either
      // exists, means the moment they land this link is live rather than a
      // 404 nobody's test would have caught.
      if (mounted) context.push('/defence/room/$id');
    } on ArgumentError catch (e) {
      // The one failure a coordinator can act on directly: fill in the
      // venue and try again. Its message comes straight from the
      // repository, which is the only place that knows the exact rule
      // that was violated.
      if (mounted) setState(() => _error = e.message.toString());
    } on FirebaseException catch (e) {
      // Named specifically: there are no server-side logs on this project,
      // so "permission-denied" is the only clue a coordinator whose role
      // changed mid-session, or whose panel snapshot the rules rejected,
      // will ever see.
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to schedule this defence '
                '[permission-denied].'
            : 'Could not schedule this defence. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not schedule this defence. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Wraps every non-form state in the same frame the form uses.
  ///
  /// The Scaffold and AppBar that used to be here belong to the app shell
  /// now, which supplies them to every state of every signed-in route —
  /// so a screen still loading its thesis or its chapters is still never a
  /// bare, unnavigable page.
  Widget _framed(List<Widget> children) => PageShell(children: children);

  @override
  Widget build(BuildContext context) {
    final thesisAsync = ref.watch(thesisByIdProvider(widget.thesisId));
    final me = ref.watch(currentUserProvider).valueOrNull;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    // Loading and error kept apart from "thesis not found": collapsing
    // them would tell a coordinator whose thesis stream is merely still
    // connecting that the thesis does not exist.
    if (thesisAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading thesis…')]);
    }
    if (thesisAsync.hasError) {
      return _framed([
        ErrorState(
          error: thesisAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }
    final thesis = thesisAsync.valueOrNull;
    if (thesis == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Thesis not found',
          message: 'This thesis no longer exists, or it belongs to '
              'another group.',
        ),
      ]);
    }

    final isCoordinator = me?.role == UserRole.coordinator;

    return KeyedSubtree(
      key: const Key('scheduleDefenceScreen'),
      child: PageShell(
        title: 'Schedule a defence',
        subtitle: thesis.workingTitle,
        children: [
          SegmentedButton<DefenceType>(
            key: const Key('defenceType'),
            segments: const [
              ButtonSegment(
                value: DefenceType.preOral,
                label: Text('Pre-oral defence'),
              ),
              ButtonSegment(
                value: DefenceType.final_,
                label: Text('Final defence'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (selection) =>
                setState(() => _type = selection.first),
          ),
          const Gap.md(),
          InkWell(
            key: const Key('defenceDate'),
            onTap: _pickDateTime,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date and time'),
              child: Text(_formatDateTime(_scheduledAt)),
            ),
          ),
          const Gap.md(),
          TextField(
            key: const Key('defenceVenue'),
            controller: _venueController,
            decoration: const InputDecoration(labelText: 'Venue'),
          ),
          const Gap.lg(),
          // Its own isLoading/hasError branch, kept separate from the
          // thesis stream above: a thesis that has loaded but whose
          // chapters are still connecting must not read as "0 approved,
          // not ready" -- see _ReadinessRow in defence_readiness.dart for
          // the same reasoning applied to the dean/coordinator list.
          ref.watch(chaptersProvider(widget.thesisId)).when(
                loading: () =>
                    const LoadingState(label: 'Loading chapters…'),
                error: (e, _) => ErrorState(
                  error: e,
                  message: 'Could not load this thesis\'s chapters.',
                ),
                data: (chapters) {
                  final readiness = readinessOf(chapters);
                  // finalReady implies the pre-oral gate is also met, so a
                  // pre-oral defence only warns on notReady, while a final
                  // defence warns unless every chapter is approved.
                  final gateMet = _type == DefenceType.preOral
                      ? readiness != DefenceReadiness.notReady
                      : readiness == DefenceReadiness.finalReady;
                  if (gateMet) return const SizedBox.shrink();

                  final message = _type == DefenceType.preOral
                      ? 'Chapters I–III are not all approved yet. You can '
                          'still schedule this defence.'
                      : 'Chapters I–V are not all approved yet. You can '
                          'still schedule this defence.';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: ErrorState(
                      key: const Key('readinessWarning'),
                      message: message,
                    ),
                  );
                },
              ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                key: const Key('error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // Hidden rather than merely disabled for anyone who is not the
          // coordinator: the rules deny the write either way, but a button
          // that always fails is worse than no button at all.
          if (isCoordinator)
            FilledButton(
              key: const Key('scheduleDefence'),
              onPressed: _busy || uid == null
                  ? null
                  : () => _schedule(thesis: thesis, coordinatorUid: uid),
              child: Text(_busy ? 'Scheduling…' : 'Schedule defence'),
            ),
        ],
      ),
    );
  }
}
