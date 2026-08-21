
/// The five chapters, fixed. A group cannot invent a sixth, and the rules
/// hardcode these ids so nothing outside this list can be written.
enum ChapterId {
  chapterI,
  chapterII,
  chapterIII,
  chapterIV,
  chapterV;

  String get value => name;

  String get label => switch (this) {
        ChapterId.chapterI => 'Chapter I — Introduction',
        ChapterId.chapterII => 'Chapter II — Related Literature',
        ChapterId.chapterIII => 'Chapter III — Methodology',
        ChapterId.chapterIV => 'Chapter IV — Results and Discussion',
        ChapterId.chapterV => 'Chapter V — Conclusions',
      };

  /// Null rather than a default, deliberately. Falling back to chapterI
  /// would let a typo write one chapter's record over another's.
  static ChapterId? fromString(String? raw) {
    for (final c in ChapterId.values) {
      if (c.name == raw) return c;
    }
    return null;
  }

  /// Approved in full, the pre-oral defence may be scheduled.
  static const proposalChapters = [chapterI, chapterII, chapterIII];

  /// Approved in full, the final defence may be scheduled.
  static const finalChapters = ChapterId.values;
}

enum ChapterStatus {
  submitted,
  revise,
  approved;

  String get value => name;

  /// Defaults to `submitted` — the status that grants nothing. Defaulting
  /// to `approved` would let corrupt data unlock a defence.
  static ChapterStatus fromString(String? raw) {
    for (final s in ChapterStatus.values) {
      if (s.name == raw) return s;
    }
    return ChapterStatus.submitted;
  }
}

/// One chapter of one thesis: what state it is in and how many versions
/// have been uploaded. The files themselves live in `versions`.
class ThesisChapter {
  const ThesisChapter({
    required this.id,
    required this.currentVersion,
    required this.status,
    this.updatedAt,
  });

  final ChapterId id;
  final int currentVersion;
  final ChapterStatus status;
  final DateTime? updatedAt;

  factory ThesisChapter.fromMap(String id, Map<String, dynamic> map) {
    return ThesisChapter(
      id: ChapterId.fromString(id) ?? ChapterId.chapterI,
      currentVersion: (map['currentVersion'] as num?)?.toInt() ?? 1,
      status: ChapterStatus.fromString(map['status'] as String?),
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}

/// One uploaded file. Immutable: nothing is ever overwritten, so the
/// revision history is a record rather than a snapshot.
class ChapterVersion {
  const ChapterVersion({
    required this.version,
    required this.storagePath,
    required this.fileUrl,
    required this.uploadedBy,
    required this.mimeType,
    required this.sizeBytes,
    this.uploadedAt,
  });

  final int version;
  final String storagePath;
  final String fileUrl;
  final String uploadedBy;
  final String mimeType;
  final int sizeBytes;
  final DateTime? uploadedAt;

  factory ChapterVersion.fromMap(Map<String, dynamic> map) {
    return ChapterVersion(
      version: (map['version'] as num?)?.toInt() ?? 0,
      storagePath: map['storagePath'] as String? ?? '',
      fileUrl: map['fileUrl'] as String? ?? '',
      uploadedBy: map['uploadedBy'] as String? ?? '',
      mimeType: map['mimeType'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      uploadedAt: map['uploadedAt'] as DateTime?,
    );
  }
}

/// One remark on one version. Append-only: a record of what was said is
/// only a record if it cannot be rewritten afterwards.
class ChapterFeedback {
  const ChapterFeedback({
    required this.id,
    required this.version,
    required this.reviewerUid,
    required this.reviewerName,
    required this.reviewerRole,
    required this.body,
    this.createdAt,
  });

  final String id;
  final int version;
  final String reviewerUid;
  final String reviewerName;
  final String reviewerRole;
  final String body;
  final DateTime? createdAt;

  factory ChapterFeedback.fromMap(String id, Map<String, dynamic> map) {
    return ChapterFeedback(
      id: id,
      version: (map['version'] as num?)?.toInt() ?? 0,
      reviewerUid: map['reviewerUid'] as String? ?? '',
      reviewerName: map['reviewerName'] as String? ?? '',
      reviewerRole: map['reviewerRole'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
