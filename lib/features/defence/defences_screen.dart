import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/features/defence/defence_calendar.dart';
import 'package:ethesishub/features/defence/defences_list.dart';

enum _DefencesView { list, calendar }

/// The Defences destination, at '/defences': a [PageShell] wrapping
/// [DefencesList].
///
/// The heading used to be tailored per role, because each of the four
/// dashboards hosted this body itself and passed its own wording in. Those
/// dashboards are gone and '/defences' is one route reached by one
/// sidebar entry, so it carries one heading. [DefencesList] itself is
/// already per-reader — it shows the defences you are actually party to —
/// which is where the difference between a student's view and a
/// panelist's actually lives.
///
/// [title] and [subtitle] stay overridable for a caller that embeds this
/// list under a different heading.
///
/// Carries a List/Calendar toggle. Its state is local to this widget and
/// deliberately NOT persisted -- a stored preference is not warranted for
/// something changed by a single tap, and both presentations read the same
/// [DefencesList]/[DefenceCalendar] widgets, which both watch
/// `myDefencesProvider` directly, so the two can never show different data
/// for the same account.
class DefencesScreen extends StatefulWidget {
  const DefencesScreen({
    super.key,
    this.title = 'Scheduled defences',
    this.subtitle = 'Pre-oral and final defences, and the rooms they run '
        'in.',
  });

  final String title;
  final String subtitle;

  @override
  State<DefencesScreen> createState() => _DefencesScreenState();
}

class _DefencesScreenState extends State<DefencesScreen> {
  _DefencesView _view = _DefencesView.list;

  @override
  Widget build(BuildContext context) {
    return PageShell(
      key: const Key('defencesScreen'),
      title: widget.title,
      subtitle: widget.subtitle,
      children: [
        _ViewToggle(
          view: _view,
          onChanged: (v) => setState(() => _view = v),
        ),
        const SizedBox(height: AppTokens.md),
        switch (_view) {
          _DefencesView.list => const DefencesList(),
          _DefencesView.calendar => const DefenceCalendar(),
        },
      ],
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _DefencesView view;
  final ValueChanged<_DefencesView> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('defencesViewToggle'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleButton(
          key: const Key('defencesViewList'),
          label: 'List',
          icon: Icons.view_list_outlined,
          selected: view == _DefencesView.list,
          onPressed: () => onChanged(_DefencesView.list),
        ),
        const SizedBox(width: AppTokens.sm),
        _ToggleButton(
          key: const Key('defencesViewCalendar'),
          label: 'Calendar',
          icon: Icons.calendar_month_outlined,
          selected: view == _DefencesView.calendar,
          onPressed: () => onChanged(_DefencesView.calendar),
        ),
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: AppTokens.xs),
        Text(label),
      ],
    );
    return selected
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}
