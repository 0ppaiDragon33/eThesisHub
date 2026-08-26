enum ThesisStatus {
  draft,
  nominationPendingConforme,
  nominationPendingCoordinator,
  nominationPendingDean,
  nominationApproved,
  // M1b. `titleApproved` is this milestone's terminal state; the move to
  // in_progress belongs to the documents module.
  titlePendingDefence,
  titleApproved,
  titleRejected;

  String get value => name;

  static ThesisStatus fromString(String? raw) {
    for (final s in ThesisStatus.values) {
      if (s.name == raw) return s;
    }
    return ThesisStatus.draft;
  }
}

/// The five buckets a whole-college view groups theses into — coarser than
/// [ThesisStatus], which the dean and coordinator dashboards use so a chart
/// and a table filtering "the same thing" can never silently disagree about
/// which statuses that means.
enum ThesisStage {
  nomination('Nomination'),
  titleDefence('Title defence'),
  chapters('Chapters'),
  draft('Draft'),
  returned('Returned');

  const ThesisStage(this.label);

  /// The word shown in a legend or a filter chip.
  final String label;
}

/// Buckets a single status into its [ThesisStage].
///
/// The switch is exhaustive over [ThesisStatus] on purpose: a status added
/// later fails this at compile time instead of silently vanishing from
/// whatever chart or table calls this.
ThesisStage thesisStage(ThesisStatus status) {
  switch (status) {
    case ThesisStatus.nominationPendingConforme:
    case ThesisStatus.nominationPendingCoordinator:
    case ThesisStatus.nominationPendingDean:
    case ThesisStatus.nominationApproved:
      return ThesisStage.nomination;
    case ThesisStatus.titlePendingDefence:
      return ThesisStage.titleDefence;
    case ThesisStatus.titleApproved:
      return ThesisStage.chapters;
    case ThesisStatus.draft:
      return ThesisStage.draft;
    case ThesisStatus.titleRejected:
      return ThesisStage.returned;
  }
}
