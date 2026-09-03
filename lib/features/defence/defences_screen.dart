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
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<_DefencesView>(
            // Keyed on the control itself, not its segments --
            // `ButtonSegment` carries no `key` parameter on the pinned
            // Flutter version. `faculty_mode_switch.dart`'s
            // `facultyModeSegmented` solves the same wall the same way, and
            // its tests tap by the segment's label text rather than a key,
            // which is the pattern this follows too.
            key: const Key('defencesViewToggle'),
            segments: const [
              ButtonSegment(
                value: _DefencesView.list,
                label: Text('List'),
                icon: Icon(Icons.view_list_outlined),
              ),
              ButtonSegment(
                value: _DefencesView.calendar,
                label: Text('Calendar'),
                icon: Icon(Icons.calendar_month_outlined),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (selection) =>
                setState(() => _view = selection.first),
          ),
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
