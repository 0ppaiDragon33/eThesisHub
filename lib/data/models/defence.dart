/// Which defence this is. The title defence is NOT here: it keeps M1b's own
/// collection, so that working, field-verified code is untouched.
enum DefenceType {
  preOral,
  // `final` is a Dart keyword, so the constant cannot be named for its own
  // stored value. `value` is what the security rules match on.
  final_;

  String get value => this == DefenceType.final_ ? 'final' : 'preOral';

  String get label =>
      this == DefenceType.final_ ? 'Final defence' : 'Pre-oral defence';

  /// Null rather than a default: a typo must not silently schedule the
  /// wrong kind of defence.
  static DefenceType? fromString(String? raw) {
    for (final t in DefenceType.values) {
      if (t.value == raw) return t;
    }
    return null;
  }
}

enum DefenceStatus {
  scheduled,
  inProgress,
  completed;

  String get value => name;

  /// Comments may only be written while the defence is open. That is what
  /// makes the log a record of what was said in the room rather than a
  /// document anyone can append to days later.
  bool get acceptsComments => this == DefenceStatus.inProgress;

  /// Defaults to `scheduled` — the status that grants nothing. Defaulting
  /// to `inProgress` would let corrupt data open a defence for comments.
  static DefenceStatus fromString(String? raw) {
    for (final s in DefenceStatus.values) {
      if (s.name == raw) return s;
    }
    return DefenceStatus.scheduled;
  }
}

/// One scheduled defence.
///
/// `panelUids`, `adviserUid`, and `leaderUid` are SNAPSHOTS taken when the
/// coordinator schedules it. If the panel changes next semester, last
/// semester's record must still say who actually sat. The thesis holds the
/// live truth; this holds the historical one.
class Defence {
  const Defence({
    required this.id,
    required this.thesisId,
    required this.type,
    required this.venue,
    required this.panelUids,
    required this.adviserUid,
    required this.leaderUid,
    required this.status,
    required this.createdBy,
    this.scheduledAt,
    this.createdAt,
    this.consolidatedAt,
  });

  final String id;
  final String thesisId;
  final DefenceType type;
  final DateTime? scheduledAt;
  final String venue;
  final List<String> panelUids;
  final String adviserUid;
  final String leaderUid;
  final DefenceStatus status;
  final String createdBy;
  final DateTime? createdAt;

  /// When the adviser released the consolidation. Absent until then, and
  /// its presence is exactly what lets the group read the comments.
  final DateTime? consolidatedAt;

  bool get isReleased => consolidatedAt != null;

  factory Defence.fromMap(String id, Map<String, dynamic> map) {
    return Defence(
      id: id,
      thesisId: map['thesisId'] as String? ?? '',
      type: DefenceType.fromString(map['type'] as String?) ??
          DefenceType.preOral,
      scheduledAt: map['scheduledAt'] as DateTime?,
      venue: map['venue'] as String? ?? '',
      panelUids: List<String>.from(map['panelUids'] as List? ?? const []),
      adviserUid: map['adviserUid'] as String? ?? '',
      leaderUid: map['leaderUid'] as String? ?? '',
      status: DefenceStatus.fromString(map['status'] as String?),
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
      consolidatedAt: map['consolidatedAt'] as DateTime?,
    );
  }
}

/// One remark, append-only.
///
/// `authorPosition` is stored rather than derived from the account role: the
/// position someone held at this defence must not change when their role
/// changes later, because it is the label the consolidation prints.
class DefenceComment {
  const DefenceComment({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.authorPosition,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String authorPosition;
  final String body;
  final DateTime? createdAt;

  factory DefenceComment.fromMap(String id, Map<String, dynamic> map) {
    return DefenceComment(
      id: id,
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorPosition: map['authorPosition'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
