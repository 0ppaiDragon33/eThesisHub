/// What kind of event this notification reports.
///
/// Each value corresponds to exactly one detector in
/// `lib/providers/notification_providers.dart`. `titleApproved` and
/// `titleRejected` are separate values (not one `titleDecided`) because
/// their messages read completely differently and a reader should be able
/// to tell them apart from the type alone, the same way the app already
/// keeps `ThesisStatus.titleApproved`/`titleRejected` as distinct values.
enum NotificationType {
  conformeRequested,
  nominationRecommended,
  nominationApproved,
  titleApproved,
  titleRejected,
  chapterFeedback,
  defenceComment,
  defenceScheduled,
  evaluationAwaits,
  archivePublished;

  String get value => name;

  static NotificationType fromString(String? raw) {
    for (final t in NotificationType.values) {
      if (t.name == raw) return t;
    }
    return NotificationType.chapterFeedback;
  }
}

/// A deterministic item id, derived from the type and a source-specific
/// key — never random, never wall-clock. Two clients detecting the same
/// event (two of the reader's own devices, or one client re-running
/// detection after a reconnect) must land on the exact same id, so the
/// second write is a no-op rather than a duplicate row (D71).
///
/// `sourceKey` is each detector's own concern: a comment id is already
/// unique on its own, but a field-level change (a defence's schedule
/// moving) has no natural document id of its own, so its detector folds
/// the new value into the key instead — see
/// `lib/providers/notification_providers.dart`.
String notificationId(NotificationType type, String sourceKey) =>
    '${type.value}_$sourceKey';

/// One entry in a reader's own notification feed.
///
/// Lives at `notifications/{uid}/items/{id}` — always the READER's own
/// subcollection, written only by the reader's own client (D70). `id` is
/// always a [notificationId] result; nothing constructs one ad hoc.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.thesisId,
    required this.message,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final NotificationType type;
  final String thesisId;

  /// A pure, already-rendered sentence — generated once by the detector
  /// that wrote this item, from fields the writer already has standing
  /// read access to. Never re-derived on read.
  final String message;

  final bool read;

  /// The SOURCE event's own timestamp (D72), not when this client noticed
  /// it — so the feed sorts correctly even for a client that only
  /// reconnects long after the underlying event happened.
  final DateTime createdAt;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        thesisId: thesisId,
        message: message,
        read: read ?? this.read,
        createdAt: createdAt,
      );

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      type: NotificationType.fromString(map['type'] as String?),
      thesisId: map['thesisId'] as String? ?? '',
      message: map['message'] as String? ?? '',
      read: map['read'] as bool? ?? false,
      createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.value,
        'thesisId': thesisId,
        'message': message,
        'read': read,
        'createdAt': createdAt,
      };
}
