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
    this.nominationsSubmittedAt,
    this.presentationPath,
    this.presentationUrl,
    this.titlesSubmittedAt,
    this.titleRound = 0,
    this.approvedTitleId,
    this.titleDecidedAt,
    this.titleDecidedBy,
    this.titleRejectionRemark,
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
  final DateTime? nominationsSubmittedAt;
  final String? presentationPath;
  final String? presentationUrl;
  final DateTime? titlesSubmittedAt;

  /// 1 for the first submission, incremented on each resubmission after a
  /// rejection. Absent on theses created by M1a — read as 0.
  final int titleRound;

  final String? approvedTitleId;
  final DateTime? titleDecidedAt;
  final String? titleDecidedBy;
  final String? titleRejectionRemark;

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
      nominationsSubmittedAt: map['nominationsSubmittedAt'] as DateTime?,
      presentationPath: map['presentationPath'] as String?,
      presentationUrl: map['presentationUrl'] as String?,
      titlesSubmittedAt: map['titlesSubmittedAt'] as DateTime?,
      titleRound: (map['titleRound'] as num?)?.toInt() ?? 0,
      approvedTitleId: map['approvedTitleId'] as String?,
      titleDecidedAt: map['titleDecidedAt'] as DateTime?,
      titleDecidedBy: map['titleDecidedBy'] as String?,
      titleRejectionRemark: map['titleRejectionRemark'] as String?,
    );
  }

  /// Read-side only — for round-tripping in tests and in-memory copies.
  ///
  /// Do NOT hand this to `.set()` or `.update()`: `createdAt` is emitted as a
  /// client `DateTime`, and the rules pin server-written timestamps to
  /// `request.time`. Repositories build their own write maps with
  /// `FieldValue.serverTimestamp()`.
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
        'nominationsSubmittedAt': nominationsSubmittedAt,
      };
}
