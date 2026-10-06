import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/academic_term.dart';
import 'package:ethesishub/providers/academic_term_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// The college's current term on the Coordinator's dashboard, with the one
/// control that changes it. Set it at the start of each semester; every
/// thesis then shows where it is now without being edited.
class CurrentTermPanel extends ConsumerWidget {
  const CurrentTermPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final termAsync = ref.watch(currentTermProvider);
    final term = termAsync.valueOrNull;
    final text = Theme.of(context).textTheme;

    final String line;
    if (termAsync.isLoading) {
      line = 'Loading the current term…';
    } else if (termAsync.hasError) {
      line = 'Could not load the current term.';
    } else if (term == null) {
      line = 'Not set yet. Set it so theses show their current year level.';
    } else {
      line = '${term.semester} semester, AY ${term.academicYear}';
    }

    return Panel(
      key: const Key('currentTermPanel'),
      title: 'Current term',
      icon: Icons.event_note_outlined,
      trailing: termAsync.isLoading
          ? null
          : TextButton(
              key: const Key('setCurrentTerm'),
              onPressed: () => _set(context, ref, term),
              child: Text(term == null ? 'Set term' : 'Change'),
            ),
      child: Text(line, key: const Key('currentTermText'), style: text.bodyMedium),
    );
  }

  Future<void> _set(
    BuildContext context,
    WidgetRef ref,
    AcademicTerm? current,
  ) async {
    final picked = await showDialog<AcademicTerm>(
      context: context,
      builder: (_) => _TermDialog(current: current),
    );
    if (picked == null || !context.mounted) return;
    final uid = ref.read(signedInUidProvider);
    if (uid == null) return;
    try {
      await ref
          .read(academicTermRepositoryProvider)
          .setCurrent(picked, coordinatorUid: uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Current term set to ${picked.short}.'),
        ));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not set the term. Please try again.'),
        ));
      }
    }
  }
}

/// Picks a semester and an academic year. Opens on the term after the
/// current one, since moving to the next semester is the usual change.
class _TermDialog extends StatefulWidget {
  const _TermDialog({required this.current});

  final AcademicTerm? current;

  @override
  State<_TermDialog> createState() => _TermDialogState();
}

class _TermDialogState extends State<_TermDialog> {
  late final AcademicTerm _start = widget.current?.next ??
      AcademicTerm(
        semester: DateTime.now().month >= 6 && DateTime.now().month <= 12
            ? 'First'
            : 'Second',
        academicYear: AcademicTerm.yearFrom(
          DateTime.now().month >= 6 ? DateTime.now().year : DateTime.now().year - 1,
        ),
      );
  late String _semester = _start.semester;
  late String _year = _start.academicYear;

  List<String> get _years {
    final base = _start.startYear ?? DateTime.now().year;
    return [for (var y = base - 1; y <= base + 1; y++) AcademicTerm.yearFrom(y)];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set the current term'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('termSemester'),
            initialValue: _semester,
            decoration: const InputDecoration(labelText: 'Semester'),
            items: [
              for (final s in AcademicTerm.semesters)
                DropdownMenuItem(value: s, child: Text('$s semester')),
            ],
            onChanged: (v) => setState(() => _semester = v!),
          ),
          const SizedBox(height: AppTokens.md),
          DropdownButtonFormField<String>(
            key: const Key('termYear'),
            initialValue: _year,
            decoration: const InputDecoration(labelText: 'Academic year'),
            items: [
              for (final y in _years) DropdownMenuItem(value: y, child: Text(y)),
            ],
            onChanged: (v) => setState(() => _year = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('saveTerm'),
          onPressed: () => Navigator.of(context).pop(
            AcademicTerm(semester: _semester, academicYear: _year),
          ),
          child: const Text('Set term'),
        ),
      ],
    );
  }
}
