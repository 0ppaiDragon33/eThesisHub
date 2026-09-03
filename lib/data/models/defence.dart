import 'package:ethesishub/data/models/evaluation.dart';

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

/// How early a defence may be opened, relative to its scheduled time.
///
/// Panels gather before the hour and rooms run late, so an exact-moment
/// gate would refuse a defence convening five minutes ahead of schedule.
///
/// THIS NUMBER EXISTS TWICE. `firestore.rules` carries the same 30 minutes
/// as a literal, because rules cannot import Dart. If the two ever
/// disagree, the button looks enabled and the write is denied -- so the
/// rules suite pins the exact boundary in minutes, and changing one
/// without the other fails there.
const defenceOpenGrace = Duration(minutes: 30);

enum DefenceStatus {
  scheduled,
  inProgress,
  completed,
  /// A defence created by mistake -- wrong thesis, duplicate, or simply
  /// abandoned. Cancelled rather than deleted: the defence record is
  /// evidence, and a hard delete leaves nothing to explain a gap in the
  /// history to a panel later.
  cancelled;

  String get value => name;

  /// Comments may only be written while the defence is open. That is what
  /// makes the log a record of what was said in the room rather than a
  /// document anyone can append to days later.
  bool get acceptsComments => this == DefenceStatus.inProgress;

  /// Nothing further happens to a defence in a terminal state.
  bool get isTerminal =>
      this == DefenceStatus.completed || this == DefenceStatus.cancelled;

  /// Only a scheduled defence can still be edited or called off.
  bool get isEditable => this == DefenceStatus.scheduled;

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
    this.evaluationsReleasedAt,
    this.panelVerdict,
    this.verdictRecordedBy,
    this.verdictRecordedAt,
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

  /// When the adviser released the panel's evaluations to each other.
  ///
  /// The same shape as [consolidatedAt] and for the same reason: presence
  /// is the gate, so `firestore.rules` tests `'evaluationsReleasedAt' in
  /// resource.data` -- a presence check, never a sentinel comparison. The
  /// coordinator-admin milestone lost time twice to sentinel collisions
  /// (`.get(k, true)` colliding with a real `true`, then `.get(k, null)`
  /// with an explicit `null`); presence is value-blind and cannot collide.
  ///
  /// SEPARATE from [consolidatedAt]. One releases the room log to the
  /// group; this releases the grades to the panel. Neither implies the
  /// other.
  final DateTime? evaluationsReleasedAt;

  /// Guidelines §8b, deliberated by the panel as a body and recorded once.
  ///
  /// NEVER computed from the panelists' individual ratings (D41). §8b
  /// hands the decision to a conversation; deriving it would be the system
  /// overruling the body the manual says decides.
  final PassFail? panelVerdict;

  /// The adviser who recorded [panelVerdict].
  ///
  /// Exists so a reader can see the adviser TRANSCRIBED a decision rather
  /// than made one -- they are barred from scoring at all (D37), so their
  /// role here has to be visibly that of a scribe.
  final String? verdictRecordedBy;

  final DateTime? verdictRecordedAt;

  bool get isReleased => consolidatedAt != null;

  bool get evaluationsReleased => evaluationsReleasedAt != null;

  bool get hasVerdict => panelVerdict != null;

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
      evaluationsReleasedAt: map['evaluationsReleasedAt'] as DateTime?,
      panelVerdict: PassFail.fromString(map['panelVerdict'] as String?),
      verdictRecordedBy: map['verdictRecordedBy'] as String?,
      verdictRecordedAt: map['verdictRecordedAt'] as DateTime?,
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
