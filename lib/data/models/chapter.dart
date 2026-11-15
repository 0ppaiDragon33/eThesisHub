
/// The documents a group uploads for its adviser to review.
///
/// A group does not upload five chapters one by one. It uploads ONE
/// manuscript: Chapters I-III before its pre-oral defense
/// ([manuscriptProposal]), and the whole of Chapters I-V after it
/// ([manuscriptFinal]). Each is a single document with its own versions,
/// feedback and approval, and the adviser approves it as a whole.
///
/// The five per-chapter ids below them are what groups uploaded before
/// manuscripts existed. They are kept so those records still read and still
/// count, but nothing new is written to them: the app lists them only for a
/// thesis that has them on file. The rules hardcode every id here, so
/// nothing outside this list can be written.
enum ChapterId {
  chapterI,
  chapterII,
  chapterIII,
  chapterIV,
  chapterV,
  manuscriptProposal,
  manuscriptFinal;

  String get value => name;

  String get label => switch (this) {
        ChapterId.chapterI => 'Chapter I — Introduction',
        ChapterId.chapterII => 'Chapter II — Related Literature',
        ChapterId.chapterIII => 'Chapter III — Methodology',
        ChapterId.chapterIV => 'Chapter IV — Results and Discussion',
        ChapterId.chapterV => 'Chapter V — Conclusions',
        ChapterId.manuscriptProposal => 'Manuscript — Chapters I–III',
        ChapterId.manuscriptFinal => 'Manuscript — Chapters I–V',
      };

  /// The short mark for a badge or a tab: "I" for a chapter, "I–III" for
  /// the proposal manuscript, "I–V" for the full one.
  String get mark => switch (this) {
        ChapterId.chapterI => 'I',
        ChapterId.chapterII => 'II',
        ChapterId.chapterIII => 'III',
        ChapterId.chapterIV => 'IV',
        ChapterId.chapterV => 'V',
        ChapterId.manuscriptProposal => 'I–III',
        ChapterId.manuscriptFinal => 'I–V',
      };

  /// The line a row leads with: "Introduction" for a chapter, the whole
  /// label for a manuscript (there is nothing after the dash to drop).
  String get heading => isManuscript ? label : label.split(' — ').last;

  bool get isManuscript =>
      this == ChapterId.manuscriptProposal || this == ChapterId.manuscriptFinal;

  /// Null rather than a default, deliberately. Falling back to chapterI
  /// would let a typo write one chapter's record over another's.
  static ChapterId? fromString(String? raw) {
    for (final c in ChapterId.values) {
      if (c.name == raw) return c;
    }
    return null;
  }

  /// What groups uploaded one chapter at a time, before manuscripts.
  static const legacyChapters = [chapterI, chapterII, chapterIII, chapterIV, chapterV];

  /// The two manuscripts, in the order a group reaches them.
  static const manuscripts = [manuscriptProposal, manuscriptFinal];

  /// Legacy: Chapters I-III as separate records. Approved in full, the
  /// pre-oral defense may be scheduled, as it is for an approved
  /// [manuscriptProposal].
  static const proposalChapters = [chapterI, chapterII, chapterIII];

  /// Legacy: all five chapters as separate records, as for an approved
  /// [manuscriptFinal].
  static const finalChapters = legacyChapters;

  /// The full manuscript, and the old Chapters IV and V, are written after
  /// the panel passes the group's pre-oral; until then they cannot be
  /// uploaded.
  bool get needsPassedPreOral =>
      this == ChapterId.chapterIV ||
      this == ChapterId.chapterV ||
      this == ChapterId.manuscriptFinal;
}

/// What a group sees on its Chapters screen: ONE manuscript at a time.
///
/// Before the pre-oral is passed that is the Chapters I-III manuscript;
/// after, the Chapters I-V one, which replaces it rather than sitting
/// beside it as a second thing to do. The proposal manuscript stays
/// reachable as [earlier] (its versions and the adviser's feedback are a
/// record), and anything a thesis uploaded chapter by chapter, before
/// manuscripts existed, stays reachable as [legacy].
class ManuscriptShelf {
  const ManuscriptShelf({
    required this.current,
    required this.earlier,
    required this.legacy,
  });

  /// The manuscript the group is working on now.
  final ChapterId current;

  /// The proposal manuscript, once [current] has moved on to the full one
  /// and the proposal is on file. Null before that.
  final ChapterId? earlier;

  /// Per-chapter records on file from before manuscripts, in order. Empty
  /// for every thesis that started after.
  final List<ChapterId> legacy;
}

ManuscriptShelf manuscriptShelf({
  required bool preOralPassed,
  Iterable<ChapterId> uploaded = const [],
}) {
  final have = uploaded.toSet();
  // A full manuscript already on file is the current one whatever the
  // defenses say: nothing a group has uploaded ever drops out of view.
  final current = preOralPassed || have.contains(ChapterId.manuscriptFinal)
      ? ChapterId.manuscriptFinal
      : ChapterId.manuscriptProposal;
  return ManuscriptShelf(
    current: current,
    earlier: current == ChapterId.manuscriptFinal &&
            have.contains(ChapterId.manuscriptProposal)
        ? ChapterId.manuscriptProposal
        : null,
    legacy: [for (final id in ChapterId.legacyChapters) if (have.contains(id)) id],
  );
}

enum ChapterStatus {
  submitted,
  revise,
  approved;

  String get value => name;

  /// Defaults to `submitted`: the status that grants nothing. Defaulting
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
    final chapterId = ChapterId.fromString(id);
    // Throws rather than defaulting. A silent fallback to chapterI would
    // relabel a corrupt or mistyped id as Chapter I and write one chapter's
    // record over another's, looking correct the entire time. A caller that
    // may see unknown ids filters them with ChapterId.fromString first.
    if (chapterId == null) {
      throw ArgumentError.value(id, 'id', 'Not one of the five chapters');
    }
    return ThesisChapter(
      id: chapterId,
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
