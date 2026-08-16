import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

void main() {
  test('returns every thesis this person holds a position on', () async {
    final db = FakeFirebaseFirestore();
    for (final t in ['t1', 't2']) {
      await db.collection('theses/$t/nominations').doc('p1').set({
        'nomineeUid': 'p1', 'nomineeName': 'Dr. Diamante',
        'position': 'panelist', 'exOfficio': false,
        'conformeStatus': 'accepted',
      });
    }
    await db.collection('theses/t3/nominations').doc('other').set({
      'nomineeUid': 'other', 'nomineeName': 'Someone Else',
      'position': 'panelist', 'exOfficio': false,
      'conformeStatus': 'accepted',
    });

    final ids = await TitleDefenceRepository(db).watchMyThesisIds('p1').first;
    expect(ids.toSet(), {'t1', 't2'});
  });

  test('includes ex officio seats', () async {
    // A coordinator or the dean sits on every panel by office and never
    // accepts. Filtering on an accepted Conforme would hide their defences.
    final db = FakeFirebaseFirestore();
    await db.collection('theses/t1/nominations').doc('c1').set({
      'nomineeUid': 'c1', 'nomineeName': 'Dr. Bito-onon',
      'position': 'coordinator', 'exOfficio': true,
      'conformeStatus': 'exOfficio',
    });

    final ids = await TitleDefenceRepository(db).watchMyThesisIds('c1').first;
    expect(ids, ['t1']);
  });
}
