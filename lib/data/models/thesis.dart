import 'package:ethesishub/data/models/thesis_status.dart';

class Thesis {
  const Thesis({
    required this.id,
    required this.leaderUid,
    required this.memberNames,
    required this.workingTitle,
    required this.college,
    required this.program,
    required this.semester,
    required this.academicYear,
    required this.status,
    required this.panelistUids,
    required this.createdAt,
    this.adviserUid,
    this.coordinatorRecommendedAt,
    this.coordinatorRecommendedBy,
    this.deanApprovedAt,
    this.deanApprovedBy,
  });

  final String id;
  final String leaderUid;
  final List<String> memberNames;
  final String workingTitle;
  final String college;
  final String program;
  final String semester;
  final String academicYear;
  final ThesisStatus status;
  final List<String> panelistUids;
  final DateTime createdAt;
  final String? adviserUid;
  final DateTime? coordinatorRecommendedAt;
  final String? coordinatorRecommendedBy;
  final DateTime? deanApprovedAt;
  final String? deanApprovedBy;

  factory Thesis.fromMap(String id, Map<String, dynamic> map) {
    return Thesis(
      id: id,
      leaderUid: map['leaderUid'] as String? ?? '',
      memberNames: List<String>.from(map['memberNames'] as List? ?? const []),
      workingTitle: map['workingTitle'] as String? ?? '',
      college: map['college'] as String? ?? '',
      program: map['program'] as String? ?? '',
      semester: map['semester'] as String? ?? '',
      academicYear: map['academicYear'] as String? ?? '',
      status: ThesisStatus.fromString(map['status'] as String?),
      panelistUids: List<String>.from(map['panelistUids'] as List? ?? const []),
      createdAt: map['createdAt'] as DateTime? ?? DateTime.now().toUtc(),
      adviserUid: map['adviserUid'] as String?,
      coordinatorRecommendedAt: map['coordinatorRecommendedAt'] as DateTime?,
      coordinatorRecommendedBy: map['coordinatorRecommendedBy'] as String?,
      deanApprovedAt: map['deanApprovedAt'] as DateTime?,
      deanApprovedBy: map['deanApprovedBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'leaderUid': leaderUid,
        'memberNames': memberNames,
        'workingTitle': workingTitle,
        'college': college,
        'program': program,
        'semester': semester,
        'academicYear': academicYear,
        'status': status.value,
        'panelistUids': panelistUids,
        'createdAt': createdAt,
        'adviserUid': adviserUid,
        'coordinatorRecommendedAt': coordinatorRecommendedAt,
        'coordinatorRecommendedBy': coordinatorRecommendedBy,
        'deanApprovedAt': deanApprovedAt,
        'deanApprovedBy': deanApprovedBy,
      };
}
