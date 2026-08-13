enum FacultyMode {
  adviser,
  panelist;

  String get value => name;
  String get label => this == FacultyMode.adviser ? 'Adviser' : 'Panelist';

  static FacultyMode fromString(String? raw) =>
      raw == FacultyMode.panelist.name ? FacultyMode.panelist : FacultyMode.adviser;
}
