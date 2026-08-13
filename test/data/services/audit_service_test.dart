import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/audit_service.dart';

void main() {
  test('log writes an entry attributed to the actor', () async {
    final db = FakeFirebaseFirestore();
    final service = AuditService(db);

    await service.log(
      actorUid: 'uid-1',
      action: 'role.promoted',
      targetType: 'user',
      targetId: 'uid-1',
      metadata: {'to': 'faculty'},
    );

    final logs = await db.collection('auditLogs').get();
    expect(logs.docs, hasLength(1));
    expect(logs.docs.first.data()['actorUid'], 'uid-1');
    expect(logs.docs.first.data()['action'], 'role.promoted');
    expect(logs.docs.first.data()['metadata']['to'], 'faculty');
  });
}
