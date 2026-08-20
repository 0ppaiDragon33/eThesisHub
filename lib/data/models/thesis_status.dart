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
