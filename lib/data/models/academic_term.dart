/// A semester of an academic year: "Second semester, AY 2026–2027".
///
/// A thesis keeps the term it started in (Form 1 prints it). The college's
/// current term lives in `settings/academicTerm`, set by the Coordinator,
/// and the app works out where a thesis is now from the two.
class AcademicTerm {
  const AcademicTerm({required this.semester, required this.academicYear});

  /// 'First' or 'Second', as stored on a thesis.
  final String semester;

  /// 'YYYY-YYYY', e.g. '2026-2027'.
  final String academicYear;

  static const semesters = ['First', 'Second'];

  /// The first year of [academicYear] (2026 for '2026-2027'), or null when
  /// it is not in that form.
  int? get startYear {
    final m = RegExp(r'^(\d{4})-(\d{4})$').firstMatch(academicYear);
    return m == null ? null : int.parse(m.group(1)!);
  }

  bool get isValid => semesters.contains(semester) && startYear != null;

  /// Semesters in order: two per academic year.
  int? get index {
    final y = startYear;
    if (y == null || !semesters.contains(semester)) return null;
    return y * 2 + (semester == 'Second' ? 1 : 0);
  }

  /// The term after this one: First → Second of the same year, Second →
  /// First of the next.
  AcademicTerm get next {
    final y = startYear;
    if (y == null) return this;
    return semester == 'First'
        ? AcademicTerm(semester: 'Second', academicYear: academicYear)
        : AcademicTerm(semester: 'First', academicYear: yearFrom(y + 1));
  }

  static String yearFrom(int start) => '$start-${start + 1}';

  /// "1st sem 2026–27".
  String get short {
    final y = startYear;
    final sem = semester == 'First' ? '1st sem' : '2nd sem';
    if (y == null) return '$sem $academicYear';
    final end = (y + 1) % 100;
    return '$sem $y–${end.toString().padLeft(2, '0')}';
  }

  factory AcademicTerm.fromMap(Map<String, dynamic> m) => AcademicTerm(
        semester: m['semester'] as String? ?? '',
        academicYear: m['academicYear'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is AcademicTerm &&
      other.semester == semester &&
      other.academicYear == academicYear;

  @override
  int get hashCode => Object.hash(semester, academicYear);
}

/// The year level a thesis group starts in. Theses here begin in 3rd year.
const kThesisStartYearLevel = 3;

/// The group's year level in [now], counted from the term it [started] in:
/// one level per academic year passed. Null when either term is malformed
/// or [now] is before [started].
int? yearLevelIn(AcademicTerm started, AcademicTerm now) {
  final s = started.startYear, n = now.startYear;
  if (s == null || n == null || n < s) return null;
  return kThesisStartYearLevel + (n - s);
}

/// "3rd year", "4th year".
String yearLevelLabel(int level) {
  final suffix = switch (level % 100) {
    11 || 12 || 13 => 'th',
    _ => switch (level % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' },
  };
  return '$level$suffix year';
}
