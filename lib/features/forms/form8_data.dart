import 'package:ethesishub/data/models/archive_entry.dart';

/// The three variable fields on Form 8. The rest of the form is fixed text
/// and a signature rule.
///
/// Read from the ARCHIVE ENTRY rather than the thesis (D64). M5 made
/// archiving the coordinator's assertion that Form 8 was issued and three
/// bound copies reached the Dean, the Library and R&D — which is exactly
/// what this certificate says. Generating from the entry means the paper
/// cannot claim something the record does not show, and the fields are
/// already frozen (M5's D49).
class Form8Data {
  const Form8Data({
    required this.studentNames,
    required this.title,
    required this.issuedOn,
  });

  /// Every member, on one certificate (D65). The printed form reads
  /// "his/her", singular, but a thesis here belongs to a group and the
  /// deposit was joint.
  final List<String> studentNames;

  final String title;
  final DateTime? issuedOn;

  factory Form8Data.assemble({required ArchiveEntry entry}) {
    return Form8Data(
      studentNames: entry.memberNames,
      title: entry.title,
      issuedOn: entry.archivedAt,
    );
  }
}
