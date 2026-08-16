import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';

class Researcher {
  const Researcher({required this.name, required this.isLeader});
  final String name;
  final bool isLeader;
}

class ConformeRow {
  const ConformeRow({
    required this.name,
    required this.role,
    required this.status,
  });
  final String name;
  final String role;
  final String status;
}

class ExOfficioEntry {
  const ExOfficioEntry({required this.name, required this.role});
  final String name;
  final String role;
}

/// Everything Form 1 prints, shaped once so the PDF layer holds no logic.
class Form1Data {
  const Form1Data({
    required this.thesis,
    required this.researchers,
    required this.adviserName,
    required this.panelNames,
    required this.conformeRows,
    required this.exOfficioEntries,
    required this.coordinatorName,
    required this.deanName,
    required this.submittedOn,
  });

  final Thesis thesis;
  final List<Researcher> researchers;
  final String adviserName;
  final List<String> panelNames;
  final List<ConformeRow> conformeRows;
  final List<ExOfficioEntry> exOfficioEntries;
  final String? coordinatorName;
  final String? deanName;
  final DateTime submittedOn;

  /// Several researchers sign, so the printed form's singular reads wrongly.
  String get subjectPronoun => researchers.length > 1 ? 'We' : 'I';
  String get possessivePronoun => researchers.length > 1 ? 'our' : 'my';

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _stamp(DateTime? d) {
    if (d == null) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, '
        '${_two(d.hour)}:${_two(d.minute)}';
  }

  static Form1Data assemble({
    required Thesis thesis,
    required List<Nomination> nominations,
    required String leaderName,
    required Map<String, String> directoryNames,
  }) {
    final nominated = nominations.where((n) => !n.exOfficio).toList();
    final exOfficio = nominations.where((n) => n.exOfficio).toList();

    final adviser = nominated
        .where((n) => n.position == NominationPosition.adviser)
        .toList();
    final panel = nominated
        .where((n) => n.position == NominationPosition.panelist)
        .toList();

    String roleLabel(Nomination n) => switch (n.position) {
          NominationPosition.adviser => 'Thesis Adviser',
          NominationPosition.panelist => 'Panel Member',
          NominationPosition.coordinator =>
            'Research Coordinator (ex officio)',
          NominationPosition.dean => 'Dean (ex officio)',
        };

    final rows = <ConformeRow>[
      for (final n in [...adviser, ...panel])
        ConformeRow(
          name: n.nomineeName,
          role: roleLabel(n),
          status: n.conformeStatus == ConformeStatus.accepted
              // A hyphen, not an em dash: the `pdf` package's built-in
              // Helvetica has no glyph for U+2014 in this render path and
              // silently drops it, which is worse than a plainer dash.
              ? 'Accepted · ${_stamp(n.respondedAt)} - via eThesisHub'
              : n.conformeStatus.value,
        ),
      for (final n in exOfficio)
        ConformeRow(
          name: n.nomineeName,
          role: roleLabel(n),
          status: 'Ex officio member',
        ),
    ];

    return Form1Data(
      thesis: thesis,
      researchers: [
        Researcher(name: leaderName, isLeader: true),
        for (final m in thesis.memberNames)
          Researcher(name: m, isLeader: false),
      ],
      adviserName: adviser.isEmpty ? '' : adviser.first.nomineeName,
      panelNames: panel.map((n) => n.nomineeName).toList(),
      conformeRows: rows,
      exOfficioEntries: [
        for (final n in exOfficio)
          ExOfficioEntry(name: n.nomineeName, role: roleLabel(n)),
      ],
      coordinatorName: _nameFor(
          thesis.coordinatorRecommendedBy, directoryNames, exOfficio),
      deanName:
          _nameFor(thesis.deanApprovedBy, directoryNames, exOfficio),
      // The letter date is when the nomination was submitted, not when the
      // group record was created — those can be weeks apart. Older theses
      // predate this field and have no recorded submission moment; rather
      // than print a blank or misleading date, fall back to `createdAt` so
      // the form always carries a real date.
      submittedOn: thesis.nominationsSubmittedAt ?? thesis.createdAt,
    );
  }

  /// Prefer the directory, fall back to the ex officio entry already on the
  /// thesis. Written as a loop rather than `firstOrNull`, which lives in
  /// `package:collection` and is not a dependency here.
  static String? _nameFor(
    String? uid,
    Map<String, String> directoryNames,
    List<Nomination> exOfficio,
  ) {
    if (uid == null) return null;
    final fromDirectory = directoryNames[uid];
    if (fromDirectory != null) return fromDirectory;
    for (final n in exOfficio) {
      if (n.nomineeUid == uid) return n.nomineeName;
    }
    return null;
  }
}
