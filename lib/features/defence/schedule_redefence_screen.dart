import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/defence/defence_date_picker.dart';
import 'package:ethesishub/features/defence/defences_list.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The Coordinator's screen for the one re-defence of a failed defence
/// (spec 2026-09-25 §6.4), at '/defence/schedule?redefenceOf=<id>'.
///
/// The kind, thesis and panel come from the failed defence; only the date,
/// time and venue are asked.
class ScheduleRedefenceScreen extends ConsumerStatefulWidget {
  const ScheduleRedefenceScreen({super.key, required this.failedDefenceId});

  final String failedDefenceId;

  @override
  ConsumerState<ScheduleRedefenceScreen> createState() =>
      _ScheduleRedefenceScreenState();
}

class _ScheduleRedefenceScreenState
    extends ConsumerState<ScheduleRedefenceScreen> {
  final _venue = TextEditingController();
  late DateTime _scheduledAt;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _scheduledAt = DateTime(now.year, now.month, now.day + 7, 9);
  }

  @override
  void dispose() {
    _venue.dispose();
    super.dispose();
  }

  Future<void> _schedule(Defence failed, String uid) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(defenceRepositoryProvider)
          .scheduleRedefence(
            failed: failed,
            scheduledAt: _scheduledAt,
            venue: _venue.text,
            createdBy: uid,
          );
      if (mounted) context.push('/defence/room/$id');
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on FirebaseException catch (e) {
      // Most often: the thesis panel changed since the Fail, so the copied
      // panel no longer matches and the rules refuse the re-defence.
      if (mounted) {
        setState(
          () => _error = e.code == 'permission-denied'
              ? 'You do not have permission to schedule this re-defence. '
                    'If the panel changed since the defence, the re-defence '
                    'cannot use the old one [permission-denied].'
              : 'Could not schedule this re-defence. Please try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not schedule this re-defence. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _framed(List<Widget> children) => KeyedSubtree(
    key: const Key('scheduleRedefenceScreen'),
    child: PageShell(
      kicker: 'Research office',
      title: 'Schedule a re-defence',
      children: children,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final failedAsync = ref.watch(defenceProvider(widget.failedDefenceId));
    final allAsync = ref.watch(myDefencesProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    if (failedAsync.isLoading || allAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading the defence…')]);
    }
    if (failedAsync.hasError || allAsync.hasError) {
      return _framed([
        ErrorState(
          error: failedAsync.error ?? allAsync.error,
          message: 'Could not load this defence.',
        ),
      ]);
    }
    final failed = failedAsync.valueOrNull;
    if (failed == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defence not found',
          message: 'This defence no longer exists.',
        ),
      ]);
    }

    final String? refusal = failed.panelVerdict != PassFail.fail
        ? 'Only a defence the panel failed can be re-defended.'
        : failed.isRedefence
        ? 'This was already the group\'s re-defence of this stage.'
        : hasRedefence(failed, allAsync.value ?? const [])
        ? 'This defence already has its re-defence.'
        : null;
    if (refusal != null) {
      return _framed([
        EmptyState(
          key: const Key('cannotRedefend'),
          icon: Icons.block_outlined,
          title: 'This defence cannot be re-defended',
          message: refusal,
        ),
      ]);
    }

    final thesisTitle = ref
        .watch(thesisByIdProvider(failed.thesisId))
        .valueOrNull
        ?.workingTitle;
    final at = failed.scheduledAt;
    final isCoordinator = me?.role == UserRole.coordinator;

    return _framed([
      if (thesisTitle != null && thesisTitle.isNotEmpty) ...[
        Text(thesisTitle, style: Theme.of(context).textTheme.titleMedium),
        const Gap.sm(),
      ],
      Panel(
        title: 'Session',
        icon: Icons.replay_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Re-defence of the ${failed.type.label.toLowerCase()} held '
              '${at == null ? 'on a date not recorded' : DefencesList.formatDateTime(at)}',
              key: const Key('redefenceOfSummary'),
            ),
            const Gap.md(),
            FormRow(
              label: 'Date and time',
              child: InkWell(
                key: const Key('redefenceDate'),
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final picked = await pickDefenceDateTime(
                    context,
                    _scheduledAt,
                  );
                  if (picked != null && mounted) {
                    setState(() => _scheduledAt = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.schedule_rounded),
                    suffixIcon: Icon(Icons.edit_calendar_outlined),
                  ),
                  child: Text(DefencesList.formatDateTime(_scheduledAt)),
                ),
              ),
            ),
            FormRow(
              label: 'Venue',
              child: TextField(
                key: const Key('redefenceVenue'),
                controller: _venue,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                  hintText: 'Room or online link',
                ),
              ),
            ),
          ],
        ),
      ),
      const Gap.lg(),
      if (_error != null) ...[
        ErrorState(key: const Key('redefenceError'), message: _error!),
        const Gap.md(),
      ],
      if (isCoordinator)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('scheduleRedefenceButton'),
            onPressed: _busy || uid == null
                ? null
                : () => _schedule(failed, uid),
            icon: const Icon(Icons.replay_outlined, size: 18),
            label: Text(_busy ? 'Scheduling…' : 'Schedule re-defence'),
          ),
        )
      else
        Text(
          'Only the Research Coordinator can schedule defences.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ]);
  }
}
