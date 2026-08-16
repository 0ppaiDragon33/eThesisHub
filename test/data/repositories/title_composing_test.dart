import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

void main() {
  test('marking composing is keyed by uid, so it cannot duplicate', () async {
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);

    await repo.markComposing(
        thesisId: 't1',
        uid: 'p1',
        name: 'Dr. Diamante',
        role: 'Panel Member',
        candidateTitleId: 'ct1');
    await repo.markComposing(
        thesisId: 't1',
        uid: 'p1',
        name: 'Dr. Diamante',
        role: 'Panel Member',
        candidateTitleId: 'ct2');

    final live = await repo.watchComposing('t1').first;
    expect(live, hasLength(1), reason: 'one person, one indicator');
    expect(live.single.candidateTitleId, 'ct2',
        reason: 'the later heartbeat wins');
  });

  test('clearing removes it', () async {
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);
    await repo.markComposing(
        thesisId: 't1',
        uid: 'p1',
        name: 'Dr. Diamante',
        role: 'Panel Member',
        candidateTitleId: 'ct1');
    await repo.clearComposing(thesisId: 't1', uid: 'p1');
    expect(await repo.watchComposing('t1').first, isEmpty);
  });

  test('clearing an indicator that is not there is not an error', () async {
    // The client clears on blur and on submit, so a double clear is normal.
    final repo = TitleDefenceRepository(FakeFirebaseFirestore());
    await repo.clearComposing(thesisId: 't1', uid: 'nobody');
  });
}
