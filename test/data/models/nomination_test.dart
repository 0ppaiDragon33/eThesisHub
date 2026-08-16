import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/nomination.dart';

void main() {
  test('parses a nominated panelist', () {
    final n = Nomination.fromMap('uid-1', {
      'nomineeName': 'Dr. Diamante',
      'position': 'panelist',
      'exOfficio': false,
      'conformeStatus': 'pending',
    });
    expect(n.nomineeUid, 'uid-1');
    expect(n.position, NominationPosition.panelist);
    expect(n.exOfficio, isFalse);
    expect(n.conformeStatus, ConformeStatus.pending);
  });

  test('parses an ex officio dean entry', () {
    final n = Nomination.fromMap('uid-2', {
      'nomineeName': 'Dr. Siason',
      'position': 'dean',
      'exOfficio': true,
      'conformeStatus': 'exOfficio',
    });
    expect(n.position, NominationPosition.dean);
    expect(n.exOfficio, isTrue);
    expect(n.conformeStatus, ConformeStatus.exOfficio);
  });

  test('unknown conforme status degrades to pending', () {
    final n = Nomination.fromMap('uid-3', {
      'nomineeName': 'X',
      'position': 'panelist',
      'exOfficio': false,
      'conformeStatus': 'approved',
    });
    expect(n.conformeStatus, ConformeStatus.pending);
  });

  test('toMap round-trips', () {
    final original = Nomination(
      nomineeUid: 'uid-4',
      nomineeName: 'Dr. Armada',
      position: NominationPosition.adviser,
      exOfficio: false,
      conformeStatus: ConformeStatus.accepted,
      respondedAt: DateTime.utc(2026, 8, 14),
    );
    final restored = Nomination.fromMap('uid-4', original.toMap());
    expect(restored.position, NominationPosition.adviser);
    expect(restored.conformeStatus, ConformeStatus.accepted);
    expect(restored.respondedAt, DateTime.utc(2026, 8, 14));
  });

  test('needsConforme reads exOfficio, not conformeStatus', () {
    // Deliberately decorrelated: an accepted nominated member and a pending
    // ex officio seat. If needsConforme wrongly read conformeStatus, the
    // first assertion would fail — which is the point of this test.
    final acceptedMember = Nomination.fromMap('uid-a', {
      'nomineeName': 'Dr. Armada',
      'position': 'adviser',
      'exOfficio': false,
      'conformeStatus': 'accepted',
    });
    final pendingExOfficio = Nomination.fromMap('uid-d', {
      'nomineeName': 'Dr. Siason',
      'position': 'dean',
      'exOfficio': true,
      'conformeStatus': 'pending',
    });

    expect(acceptedMember.needsConforme, isTrue,
        reason: 'a nominated member always needs a Conforme, whatever their '
            'current status');
    expect(pendingExOfficio.needsConforme, isFalse,
        reason: 'an ex officio seat is never asked, whatever its status');
  });

  test('unknown position degrades to panelist', () {
    final n = Nomination.fromMap('uid-5', {
      'nomineeName': 'X',
      'position': 'unknown',
      'exOfficio': false,
      'conformeStatus': 'pending',
    });
    expect(n.position, NominationPosition.panelist);
  });
}
