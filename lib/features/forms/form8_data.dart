import 'package:ethesishub/data/models/archive_entry.dart';

/// Thrown instead of building a certificate that would certify nothing.
///
/// §6: *"A certificate with a blank name is worse than no certificate,
/// because it looks official."* The structural gate — the button is not
/// reachable unless the thesis is archived — does not cover an archived
/// entry whose fields are empty: `ArchiveEntry.fromMap` defaults both
/// `title` and `memberNames` to empty on a malformed document, and the
/// entry screen already prints 'Unknown authors' precisely because an entry
/// with no members recorded is possible. Rendered, that produces a
/// letterheaded CERTIFICATION with a signature rule attesting that *nobody*
/// deposited bound copies.
///
/// [toString] is the message itself, not `Exception: …`, because the screen
/// surfaces it verbatim in a SnackBar.
class Form8Unissuable implements Exception {
  const Form8Unissuable(this.message);

  final String message;

  /// Null when [entry] can carry a truthful certificate; otherwise the
  /// refusal, naming what is missing so a coordinator can go and fix it
  /// rather than only learning that something failed.
  static Form8Unissuable? check(ArchiveEntry entry) {
    final missing = [
      if (entry.memberNames.isEmpty) 'no student names',
      if (entry.title.isEmpty) 'no thesis title',
    ];
    if (missing.isEmpty) return null;
    return Form8Unissuable(
      'this archive entry records ${missing.join(' and ')}. '
      'Form 8 certifies who submitted bound copies of which thesis, so it '
      'cannot be issued until the entry is corrected.',
    );
  }

  @override
  String toString() => message;
}

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
