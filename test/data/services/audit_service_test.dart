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
    final data = logs.docs.first.data();

    expect(data['actorUid'], 'uid-1');
    expect(data['action'], 'role.promoted');
    expect(data['targetType'], 'user');
    expect(data['targetId'], 'uid-1');
    expect(data['metadata']['to'], 'faculty');

    // The deployed Firestore rule uses hasOnly, so an extra or missing key
    // breaks every audit write in production. This assertion prevents
    // regressions where a field is added without updating the rule.
    expect(
      data.keys,
      unorderedEquals([
        'actorUid',
        'action',
        'targetType',
        'targetId',
        'metadata',
        'timestamp',
      ]),
      reason: 'auditLogs rules use hasOnly — an extra or missing key breaks '
          'every audit write in production',
    );
  });
}
