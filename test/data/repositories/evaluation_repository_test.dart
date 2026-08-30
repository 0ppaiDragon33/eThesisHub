import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

Map<String, int> perfect() =>
    {for (final c in evaluationCriteria) c.key: c.weight};

Future<FakeFirebaseFirestore> seed({
  String status = 'completed',
  DateTime? releasedAt,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR',
    'panelUids': <String>['p1', 'p2', 'p3'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    if (releasedAt != null)
      'evaluationsReleasedAt': Timestamp.fromDate(releasedAt),
  });
  return db;
}

void main() {
  test('a submitted evaluation reads back with its computed total',
      () async {
    final repo = DefenceRepository(await seed());

    await repo.submitEvaluation(
      defenceId: 'd1',
      evaluatorUid: 'p1',
      scores: perfect(),
      comments: const {'title': 'Narrow it.'},
      rating: PassFail.pass,
    );

    final mine = await repo.watchMyEvaluation('d1', 'p1').first;
    expect(mine!.total, 100);
    expect(mine.rating, PassFail.pass);
    expect(mine.comments['title'], 'Narrow it.');
    expect(mine.sectionTotal(EvaluationSection.content), 50);
  });

  test('a second submit edits the same document, not a new one', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
      comments: const {}, rating: PassFail.pass);
    final first = await repo.watchMyEvaluation('d1', 'p1').first;

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1',
      scores: {...perfect(), 'title': 1}, comments: const {},
      rating: PassFail.fail);

    final all = await repo.watchEvaluations('d1').first;
    expect(all.length, 1);
    expect(all.single.total, 96);
    expect(all.single.rating, PassFail.fail);

    // The rules pin submittedAt to its stored value on an update. A
    // regression that re-stamps it on every write would be denied in
    // production but would still pass here if this were unchecked.
    expect(all.single.submittedAt, first!.submittedAt);
    expect(all.single.updatedAt, isNot(first.updatedAt));
  });

  test('the adviser cannot score the defence they guided', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'a1', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('a uid outside the panel cannot score the defence', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'stranger', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('a missing criterion is refused before it reaches Firestore',
      () async {
    final repo = DefenceRepository(await seed());
    final short = perfect()..remove('personality');

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: short,
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a score above its own weight is refused', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1',
        scores: {...perfect(), 'title': 6}, comments: const {},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1',
        scores: {...perfect(), 'alertness': -1}, comments: const {},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a comment on a Section B criterion is refused', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
        comments: const {'alertness': 'no such field'},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a blank comment is dropped rather than stored empty', () async {
    final repo = DefenceRepository(await seed());

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
      comments: const {'title': '   ', 'result': ' ok '},
      rating: PassFail.pass);

    final mine = await repo.watchMyEvaluation('d1', 'p1').first;
    expect(mine!.comments.containsKey('title'), isFalse);
    expect(mine.comments['result'], 'ok');
  });

  // fake_cloud_firestore enforces NO rules, so without this check every
  // test would pass against a write the emulator denies.
  test('a defence that has not started cannot be scored', () async {
    final repo = DefenceRepository(await seed(status: 'scheduled'));

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('a released evaluation can no longer be edited', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  // fake_cloud_firestore returns INSERTION order, so these are written
  // out of order deliberately -- otherwise an unsorted implementation
  // would pass this test.
  test('evaluations come back ordered by evaluator uid', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    for (final uid in ['p3', 'p1', 'p2']) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: uid, scores: perfect(),
        comments: const {}, rating: PassFail.pass);
    }

    final all = await repo.watchEvaluations('d1').first;
    expect(all.map((e) => e.evaluatorUid), ['p1', 'p2', 'p3']);
  });

  test('no evaluation yet reads as null, not as an empty sheet', () async {
    final repo = DefenceRepository(await seed());
    expect(await repo.watchMyEvaluation('d1', 'p1').first, isNull);
    expect(await repo.watchEvaluations('d1').first, isEmpty);
  });
}
