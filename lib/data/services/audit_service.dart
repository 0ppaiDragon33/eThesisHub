import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/audit_entry.dart';

/// How many entries the log viewer streams. The audit log only grows, so an
/// unbounded read would cost more every day; the viewer shows the recent
/// past and nothing older ages out of the record, only out of view.
const int kAuditFeedLimit = 100;

class AuditService {
  AuditService(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _logs =>
      _db.collection('auditLogs');

  /// The most recent entries, newest first. Readable only by a coordinator
  /// or dean, enforced in `firestore.rules`.
  Stream<List<AuditEntry>> watchRecent({int limit = kAuditFeedLimit}) {
    return _logs
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => AuditEntry.fromMap(d.id, d.data())).toList());
  }

  Future<void> log({
    required String actorUid,
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? metadata,
  }) {
    return _db.collection('auditLogs').add({
      'actorUid': actorUid,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'metadata': metadata ?? <String, dynamic>{},
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
