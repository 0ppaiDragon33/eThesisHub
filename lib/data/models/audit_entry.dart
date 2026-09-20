import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in the append-only audit log: who did what, to which record,
/// and when. Written by [AuditService.log]; read only by a coordinator or
/// dean (see `firestore.rules`).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.actorUid,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.metadata,
    required this.at,
  });

  final String id;
  final String actorUid;

  /// The namespaced `domain.event` verb, e.g. `account.deactivated`.
  final String action;
  final String targetType;
  final String targetId;
  final Map<String, dynamic> metadata;

  /// Null only for the brief window between a write and the server stamping
  /// its timestamp, which a freshly-written local copy can still observe.
  final DateTime? at;

  factory AuditEntry.fromMap(String id, Map<String, dynamic> map) {
    return AuditEntry(
      id: id,
      actorUid: map['actorUid'] as String? ?? '',
      action: map['action'] as String? ?? '',
      targetType: map['targetType'] as String? ?? '',
      targetId: map['targetId'] as String? ?? '',
      metadata: (map['metadata'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{},
      at: (map['timestamp'] as Timestamp?)?.toDate(),
    );
  }
}
