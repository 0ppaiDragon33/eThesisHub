import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';

/// The designated members of a thesis, the Research Coordinator and the
/// Dean, as "Name (Role)" for the archive entry.
///
/// They are read from the thesis's own ex-officio nominations first. Those
/// are not always there: a coordinator or dean who had not yet signed in when
/// the nominations went out was never seated on the thesis. Form 1 handles
/// that by finding them through the record of who recommended and who
/// approved, and the archive does the same, so it never lists fewer people
/// than the form the Dean signed.
List<String> designatedMembers({
  required Thesis thesis,
  required List<Nomination> nominations,
  required List<FacultyDirectoryEntry> directory,
}) {
  final coordinators = <String>[];
  final deans = <String>[];

  void add(List<String> into, String name, String role) {
    final entry = '${name.trim()} ($role)';
    if (name.trim().isNotEmpty && !into.contains(entry)) into.add(entry);
  }

  for (final n in nominations) {
    if (!n.exOfficio) continue;
    if (n.position == NominationPosition.dean) {
      add(deans, n.nomineeName, 'Dean');
    } else {
      add(coordinators, n.nomineeName, 'Research Coordinator');
    }
  }

  void fromRecord(
      String? uid, List<String> into, String role, bool alreadyListed) {
    if (alreadyListed || uid == null) return;
    for (final e in directory) {
      if (e.uid == uid) {
        add(into, e.fullName, role);
        return;
      }
    }
  }

  fromRecord(thesis.coordinatorRecommendedBy, coordinators,
      'Research Coordinator', coordinators.isNotEmpty);
  fromRecord(thesis.deanApprovedBy, deans, 'Dean', deans.isNotEmpty);

  return [...coordinators, ...deans];
}
