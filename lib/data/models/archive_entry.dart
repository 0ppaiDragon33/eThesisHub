/// One published thesis, frozen at the moment the coordinator archived it.
///
/// Every field here is a SNAPSHOT, resolved once and never consulted again
/// (D49). If a member's name is corrected next semester, or the panel is
/// reshuffled, this record still says who actually did the work — the same
/// reasoning behind M3 snapshotting `panelUids` onto a defence and M4
/// denormalizing `evaluatorName` onto an evaluation. A publication should
/// be fixed.
class ArchiveEntry {
  const ArchiveEntry({
    required this.thesisId,
    required this.title,
    required this.memberNames,
    required this.abstract,
    required this.college,
    required this.program,
    required this.academicYear,
    required this.adviserName,
    required this.panelNames,
    required this.manuscriptUrl,
    required this.manuscriptPath,
    required this.finalDefenceId,
    required this.uploadedBy,
    required this.archivedBy,
    this.uploadedAt,
    this.archivedAt,
  });

  /// The document id IS the thesis id, so a thesis is archived at most once
  /// and duplication is impossible by construction.
  final String thesisId;

  /// The approved title's text, resolved from the thesis's
  /// `approvedTitleId` at archive time — not the working title.
  final String title;

  final List<String> memberNames;
  final String abstract;
  final String college;
  final String program;
  final String academicYear;
  final String adviserName;
  final List<String> panelNames;
  final String manuscriptUrl;
  final String manuscriptPath;

  /// The defence whose Pass authorised this. Carried because Firestore
  /// rules cannot query: without the id there is no way for a rule to find
  /// "the final defence for this thesis" (D52).
  final String finalDefenceId;

  final String uploadedBy;
  final DateTime? uploadedAt;
  final String archivedBy;
  final DateTime? archivedAt;

  /// Authors as one line, for a card.
  String get authorsLabel => memberNames.join(', ');

  /// Title and authors only (D55), matched anywhere in the string.
  ///
  /// Mid-string is the whole point: Firestore can only match a prefix, so
  /// `where('title', isGreaterThanOrEqualTo: 'fisheries')` would never find
  /// "A Study of Coastal Fisheries". That is why search runs here instead
  /// (D54).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (title.toLowerCase().contains(q)) return true;
    for (final name in memberNames) {
      if (name.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  factory ArchiveEntry.fromMap(String thesisId, Map<String, dynamic> map) {
    List<String> strings(String key) =>
        List<String>.from(map[key] as List? ?? const []);

    return ArchiveEntry(
      thesisId: thesisId,
      title: map['title'] as String? ?? '',
      memberNames: strings('memberNames'),
      abstract: map['abstract'] as String? ?? '',
      college: map['college'] as String? ?? '',
      program: map['program'] as String? ?? '',
      academicYear: map['academicYear'] as String? ?? '',
      adviserName: map['adviserName'] as String? ?? '',
      panelNames: strings('panelNames'),
      manuscriptUrl: map['manuscriptUrl'] as String? ?? '',
      manuscriptPath: map['manuscriptPath'] as String? ?? '',
      finalDefenceId: map['finalDefenceId'] as String? ?? '',
      uploadedBy: map['uploadedBy'] as String? ?? '',
      uploadedAt: map['uploadedAt'] as DateTime?,
      archivedBy: map['archivedBy'] as String? ?? '',
      archivedAt: map['archivedAt'] as DateTime?,
    );
  }
}
