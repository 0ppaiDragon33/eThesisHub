import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/defence/defence_stage.dart';

Defence d(String id, DefenceType type, {String? redefenceOf}) => Defence(
  id: id,
  thesisId: 't1',
  type: type,
  venue: 'AVR',
  panelUids: const [],
  adviserUid: 'a1',
  leaderUid: 'l1',
  status: DefenceStatus.scheduled,
  createdBy: 'c1',
  redefenceOf: redefenceOf,
);

void main() {
  test('reads its stage from the URL, falling back to Title', () {
    expect(DefenceStage.fromParam('title'), DefenceStage.title);
    expect(DefenceStage.fromParam('preOral'), DefenceStage.preOral);
    expect(DefenceStage.fromParam('final'), DefenceStage.finalDefence);
    expect(DefenceStage.fromParam('redefence'), DefenceStage.redefence);
    expect(DefenceStage.fromParam(null), DefenceStage.title);
    expect(DefenceStage.fromParam('FINAL'), DefenceStage.title);
    expect(DefenceStage.fromParam('nonsense'), DefenceStage.title);
  });

  test('each stage has its own URL', () {
    for (final s in DefenceStage.values) {
      expect(
        DefenceStage.fromParam(Uri.parse(s.route).queryParameters['stage']),
        s,
      );
    }
  });

  test('each scheduled stage holds only its own defences', () {
    final pre = d('p', DefenceType.preOral);
    final fin = d('f', DefenceType.final_);
    final again = d('p_redefence', DefenceType.preOral, redefenceOf: 'p');
    expect([pre, fin, again].where(DefenceStage.preOral.includes), [pre]);
    expect([pre, fin, again].where(DefenceStage.finalDefence.includes), [fin]);
    expect([pre, fin, again].where(DefenceStage.redefence.includes), [again]);
    expect([pre, fin, again].where(DefenceStage.title.includes), isEmpty);
  });

  test('a label carries its count only when there is something', () {
    expect(DefenceStage.preOral.labelFor(0, compact: false), 'Pre-oral');
    expect(DefenceStage.preOral.labelFor(2, compact: false), 'Pre-oral (2)');
    expect(
      DefenceStage.finalDefence.labelFor(1, compact: false),
      'Final defence (1)',
    );
    expect(DefenceStage.finalDefence.labelFor(1, compact: true), 'Final (1)');
    expect(DefenceStage.title.labelFor(0, compact: true), 'Title');
  });

  test('the default stage is the first with something open, else Title', () {
    Map<DefenceStage, int> counts(List<int> n) =>
        {for (var i = 0; i < n.length; i++) DefenceStage.values[i]: n[i]};
    expect(firstStageWithSomethingOpen(counts([0, 0, 0, 0])),
        DefenceStage.title);
    expect(firstStageWithSomethingOpen(counts([2, 1, 0, 0])),
        DefenceStage.title);
    expect(firstStageWithSomethingOpen(counts([0, 1, 3, 0])),
        DefenceStage.preOral);
    expect(firstStageWithSomethingOpen(counts([0, 0, 0, 1])),
        DefenceStage.redefence);
    expect(firstStageWithSomethingOpen(const {}), DefenceStage.title);
  });
}
