enum ThesisStatus {
  draft,
  nominationPendingConforme,
  nominationPendingCoordinator,
  nominationPendingDean,
  nominationApproved;

  String get value => name;

  static ThesisStatus fromString(String? raw) {
    for (final s in ThesisStatus.values) {
      if (s.name == raw) return s;
    }
    return ThesisStatus.draft;
  }
}
