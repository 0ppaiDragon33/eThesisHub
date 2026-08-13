import 'package:cloud_firestore/cloud_firestore.dart';

class AuditService {
  AuditService(this._db);

  final FirebaseFirestore _db;

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
