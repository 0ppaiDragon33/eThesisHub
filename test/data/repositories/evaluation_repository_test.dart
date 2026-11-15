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
      evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist',
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

  // The denormalization the sibling ruling asks for: a grade sheet
  // naming a uid names nobody, and resolving the name on read would let a
  // later rename rewrite who marked a defence already in the record.
  test('a submitted evaluation stores the evaluator name it was given',
      () async {
    final repo = DefenceRepository(await seed());

    await repo.submitEvaluation(
      defenceId: 'd1',
      evaluatorUid: 'p1',
      evaluatorName: 'Dr. Ana Reyes',
      scores: perfect(),
      comments: const {},
      rating: PassFail.pass,
    );

    final mine = await repo.watchMyEvaluation('d1', 'p1').first;
    expect(mine!.evaluatorName, 'Dr. Ana Reyes');
  });

  // The group can read this document and not the sheet, so it must carry
  // the remarks and not one score.
  test('a submit also writes the remarks on their own score-free document',
      () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    await repo.submitEvaluation(
      defenceId: 'd1',
      evaluatorUid: 'p1',
      evaluatorName: 'Dr. Ana Reyes',
      scores: perfect(),
      comments: const {'title': '  Narrow it.  ', 'result': '   '},
      rating: PassFail.pass,
    );

    final remarks = await repo.watchRemarks('d1').first;
    expect(remarks, hasLength(1));
    expect(remarks.single.evaluatorName, 'Dr. Ana Reyes');
    expect(remarks.single.comments, {'title': 'Narrow it.'});

    final raw = await db
        .collection('defenses')
        .doc('d1')
        .collection('remarks')
        .doc('p1')
        .get();
    expect(raw.data()!.keys,
        unorderedEquals(['evaluatorName', 'comments', 'updatedAt']));
  });

  test('a second submit edits the same document, not a new one', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist', scores: perfect(),
      comments: const {}, rating: PassFail.pass);
    final first = await repo.watchMyEvaluation('d1', 'p1').first;

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist',
      // 74: under the passing mark, so it can be rated Fail.
      scores: {...perfect(), 'personality': 0, 'alertness': 9},
      comments: const {}, rating: PassFail.fail);

    final all = await repo.watchEvaluations('d1').first;
    expect(all.length, 1);
    expect(all.single.total, 74);
    expect(all.single.rating, PassFail.fail);

    // The rules pin submittedAt to its stored value on an update. A
    // regression that re-stamps it on every write would be denied in
    // production but would still pass here if this were unchecked.
    expect(all.single.submittedAt, first!.submittedAt);
    expect(all.single.updatedAt, isNot(first.updatedAt));
  });

  test('the adviser cannot score the defense they guided', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'a1', evaluatorName: 'Dr. Panelist', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('a uid outside the panel cannot score the defense', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'stranger', evaluatorName: 'Dr. Panelist', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  // 2026-10-01: the Coordinator and the Dean grade every defence too.
  test('the Coordinator and the Dean score as office holders', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    for (final uid in ['coord1', 'dean1']) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: uid, evaluatorName: uid,
        scores: perfect(), comments: const {}, rating: PassFail.pass,
        officeHolder: true,
      );
    }
    expect((await repo.watchEvaluations('d1').first).map((e) => e.evaluatorUid),
        ['coord1', 'dean1']);
  });

  test('being an office holder never lets the adviser score', () async {
    final repo = DefenceRepository(await seed());
    await expectLater(
      repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'a1', evaluatorName: 'Dr. Adviser',
        scores: perfect(), comments: const {}, rating: PassFail.pass,
        officeHolder: true),
      throwsA(isA<StateError>()),
    );
  });

  group('Pass needs a total of at least 75', () {
    // 74: 100 less personality (10) and 16 of alertness's 25.
    Map<String, int> seventyFour() =>
        {...perfect(), 'personality': 0, 'alertness': 9};

    test('Pass under 75 is refused', () async {
      final repo = DefenceRepository(await seed());
      await expectLater(
        repo.submitEvaluation(
          defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'P',
          scores: seventyFour(), comments: const {}, rating: PassFail.pass),
        throwsArgumentError,
      );
    });

    // The other half of the lock: at or above the mark the sheet can only
    // be rated Pass.
    test('Fail at 75 or more is refused', () async {
      final repo = DefenceRepository(await seed());
      await expectLater(
        repo.submitEvaluation(
            defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'P',
            scores: perfect(), comments: const {}, rating: PassFail.fail),
        throwsArgumentError,
      );
      // Exactly 75 is Pass-only too.
      await expectLater(
        repo.submitEvaluation(
            defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'P',
            scores: {...perfect(), 'personality': 0, 'alertness': 10},
            comments: const {}, rating: PassFail.fail),
        throwsArgumentError,
      );
      expect(await repo.watchEvaluations('d1').first, isEmpty);
    });

    test('Fail under 75, and Pass at exactly 75, are accepted', () async {
      final repo = DefenceRepository(await seed());
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'P',
        scores: seventyFour(), comments: const {}, rating: PassFail.fail);
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p2', evaluatorName: 'P',
        scores: {...perfect(), 'personality': 0, 'alertness': 10},
        comments: const {}, rating: PassFail.pass);
      expect(await repo.watchEvaluations('d1').first, hasLength(2));
    });
  });

  test('a missing criterion is refused before it reaches Firestore',
      () async {
    final repo = DefenceRepository(await seed());
    final short = perfect()..remove('personality');

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist', scores: short,
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a score above its own weight is refused', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist',
        scores: {...perfect(), 'title': 6}, comments: const {},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist',
        scores: {...perfect(), 'alertness': -1}, comments: const {},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a comment on a Section B criterion is refused', () async {
    final repo = DefenceRepository(await seed());

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist', scores: perfect(),
        comments: const {'alertness': 'no such field'},
        rating: PassFail.pass),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a blank comment is dropped rather than stored empty', () async {
    final repo = DefenceRepository(await seed());

    await repo.submitEvaluation(
      defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist', scores: perfect(),
      comments: const {'title': '   ', 'result': ' ok '},
      rating: PassFail.pass);

    final mine = await repo.watchMyEvaluation('d1', 'p1').first;
    expect(mine!.comments.containsKey('title'), isFalse);
    expect(mine.comments['result'], 'ok');
  });

  // fake_cloud_firestore enforces NO rules, so without this check every
  // test would pass against a write the emulator denies.
  test('a defense that has not started cannot be scored', () async {
    final repo = DefenceRepository(await seed(status: 'scheduled'));

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('a released evaluation can no longer be edited', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    expect(
      () => repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist', scores: perfect(),
        comments: const {}, rating: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  // fake_cloud_firestore returns INSERTION order, so these are written
  // out of order deliberately, otherwise an unsorted implementation
  // would pass this test.
  test('evaluations come back ordered by evaluator uid', () async {
    final db = await seed();
    final repo = DefenceRepository(db);

    for (final uid in ['p3', 'p1', 'p2']) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: uid, evaluatorName: 'Dr. Panelist', scores: perfect(),
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

  /// Every grader's sheet: the three panelists, the Coordinator and the Dean.
  ///
  /// Sheets AND the record on the defence, as `submitEvaluation` leaves
  /// them: release is judged on `submittedUids`.
  Future<FakeFirebaseFirestore> seedWith(List<String> uids,
      {bool record = true}) async {
    final db = await seed();
    for (final uid in uids) {
      await db.doc('defenses/d1/evaluations/$uid').set({'total': 80});
    }
    if (record) {
      await db.doc('defenses/d1').update({'submittedUids': uids});
    }
    return db;
  }

  Future<FakeFirebaseFirestore> seedAllIn() =>
      seedWith(['p1', 'p2', 'p3', 'c1', 'dn1']);

  test('release waits until every grader has submitted', () async {
    final db = await seedWith(['p1', 'p2', 'p3', 'c1']);
    final repo = DefenceRepository(db);
    await expectLater(
      repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1'),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('1 still outstanding'))),
    );
    expect((await repo.watchDefence('d1').first)!.evaluationsReleased, isFalse);
  });

  // The count alone is not the gate: five sheets is the required five, but
  // p3 never graded. Two office holders and a stranger made up the number.
  test('release refuses a full count that is missing a panelist', () async {
    final db = await seedWith(['p1', 'p2', 'c1', 'dn1', 'c2']);
    final repo = DefenceRepository(db);
    await expectLater(
      repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1'),
      throwsA(isA<StateError>()),
    );
    expect((await repo.watchDefence('d1').first)!.evaluationsReleased, isFalse);
  });

  // Sheets saved before the record existed: on file, not on the list the
  // rules read, so the rules would refuse. Refused here first, with the way
  // out spelled out.
  test('release refuses sheets that were never recorded, and says what to do',
      () async {
    final db =
        await seedWith(['p1', 'p2', 'p3', 'c1', 'dn1'], record: false);
    final repo = DefenceRepository(db);
    await expectLater(
      repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1'),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('save it once more'))),
    );
  });

  test('submitting records the grader on the defense, once', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    for (var i = 0; i < 2; i++) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: 'p1', evaluatorName: 'Dr. Panelist',
        scores: perfect(), comments: const {}, rating: PassFail.pass);
    }
    final d = await repo.watchDefence('d1').first;
    expect(d!.submittedUids, ['p1']);
  });

  test('graders submitting through the app unlock the release', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    for (final uid in ['p1', 'p2', 'p3']) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: uid, evaluatorName: 'Dr. $uid',
        scores: perfect(), comments: const {}, rating: PassFail.pass);
    }
    for (final uid in ['c1', 'dn1']) {
      await repo.submitEvaluation(
        defenceId: 'd1', evaluatorUid: uid, evaluatorName: 'Office $uid',
        scores: perfect(), comments: const {}, rating: PassFail.pass,
        officeHolder: true);
    }
    await repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1');
    expect((await repo.watchDefence('d1').first)!.evaluationsReleased, isTrue);
  });

  test('release marks the defense and cannot be repeated', () async {
    final repo = DefenceRepository(await seedAllIn());

    await repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1');
    final d = await repo.watchDefence('d1').first;
    expect(d!.evaluationsReleased, isTrue);

    expect(
        () => repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1'),
        throwsA(isA<StateError>()));
  });

  test('a defense still running cannot have its grades released',
      () async {
    final repo = DefenceRepository(await seed(status: 'inProgress'));
    expect(
        () => repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'a1'),
        throwsA(isA<StateError>()));
  });

  // Mirrors firestore.rules: defence().adviserUid == request.auth.uid.
  // fake_cloud_firestore enforces no rules, so without this test a
  // coordinator or panelist calling releaseEvaluations would appear to
  // succeed here while production denies them.
  test('only the adviser of record may release the evaluations', () async {
    final repo = DefenceRepository(await seed());
    expect(
        () => repo.releaseEvaluations(defenceId: 'd1', adviserUid: 'p1'),
        throwsA(isA<StateError>()));
  });

  // §8b has the panel deliberate over the grades, so they must be
  // able to see them first.
  test('no verdict before release', () async {
    final repo = DefenceRepository(await seed());
    expect(
      () => repo.recordVerdict(
          defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });

  test('after release the verdict is recorded with its scribe', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    await repo.recordVerdict(
        defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass);

    final d = await repo.watchDefence('d1').first;
    expect(d!.panelVerdict, PassFail.pass);
    expect(d.verdictRecordedBy, 'a1');
    expect(d.hasVerdict, isTrue);
  });

  test('a recorded verdict is final', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    await repo.recordVerdict(
        defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass);

    expect(
      () => repo.recordVerdict(
          defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.fail),
      throwsA(isA<StateError>()),
    );
  });

  // The verdict follows the mean of the submitted sheets: Pass needs the
  // passing mark, and at or above it only Pass can be recorded.
  group('the verdict has to agree with the mean', () {
    Future<DefenceRepository> withTotals(List<int> totals) async {
      final db = await seed(releasedAt: DateTime(2026, 9, 23));
      for (var i = 0; i < totals.length; i++) {
        await db
            .doc('defenses/d1/evaluations/g$i')
            .set({'total': totals[i]});
      }
      return DefenceRepository(db);
    }

    test('Pass is refused under 75', () async {
      final repo = await withTotals([100, 48]); // mean 74
      await expectLater(
        repo.recordVerdict(
            defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('only Fail'))),
      );
      expect((await repo.watchDefence('d1').first)!.hasVerdict, isFalse);
    });

    test('Fail is refused at 75 or more, including exactly 75', () async {
      for (final totals in [
        [100, 100],
        [100, 50], // exactly 75
      ]) {
        final repo = await withTotals(totals);
        await expectLater(
          repo.recordVerdict(
              defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.fail),
          throwsA(isA<StateError>().having(
              (e) => e.message, 'message', contains('only Pass'))),
          reason: '$totals',
        );
        expect(
            (await repo.watchDefence('d1').first)!.hasVerdict, isFalse);
      }
    });

    test('the matching verdict is recorded: Pass at 75, Fail at 74',
        () async {
      final pass = await withTotals([100, 50]);
      await pass.recordVerdict(
          defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.pass);
      expect((await pass.watchDefence('d1').first)!.panelVerdict,
          PassFail.pass);

      final fail = await withTotals([100, 48]);
      await fail.recordVerdict(
          defenceId: 'd1', adviserUid: 'a1', verdict: PassFail.fail);
      expect((await fail.watchDefence('d1').first)!.panelVerdict,
          PassFail.fail);
    });
  });

  test('only the adviser of record may record the verdict', () async {
    final repo =
        DefenceRepository(await seed(releasedAt: DateTime(2026, 9, 23)));

    expect(
      () => repo.recordVerdict(
          defenceId: 'd1', adviserUid: 'p1', verdict: PassFail.pass),
      throwsA(isA<StateError>()),
    );
  });
}
