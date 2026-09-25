// test/data/models/defence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';

void main() {
  test('the stored type strings are preOral and final', () {
    // `final` is a Dart keyword, so the enum constant cannot be named for
    // its own stored value. The stored string is what the rules match on,
    // so it must not drift to 'final_'.
    expect(DefenceType.preOral.value, 'preOral');
    expect(DefenceType.final_.value, 'final');
    expect(DefenceType.fromString('final'), DefenceType.final_);
    expect(DefenceType.fromString('final_'), isNull);
    expect(DefenceType.fromString(null), isNull);
  });

  test('only inProgress accepts comments', () {
    // This is the whole point of the lifecycle: a comment filed while
    // scheduled or completed is not a record of what was said in the room.
    expect(DefenceStatus.scheduled.acceptsComments, isFalse);
    expect(DefenceStatus.inProgress.acceptsComments, isTrue);
    expect(DefenceStatus.completed.acceptsComments, isFalse);
  });

  test('an unknown status reads as scheduled, never inProgress', () {
    // The safe default grants nothing. Defaulting to inProgress would let
    // corrupt data open a defence for comments.
    expect(DefenceStatus.fromString('nonsense'), DefenceStatus.scheduled);
    expect(DefenceStatus.fromString(null), DefenceStatus.scheduled);
  });

  test('a defence parses its stored shape', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'preOral',
      'scheduledAt': DateTime.utc(2026, 9, 1, 9),
      'venue': 'CICT AVR',
      'panelUids': ['p1', 'p2', 'p3'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'inProgress',
      'createdBy': 'c1',
      'createdAt': DateTime.utc(2026, 8, 22),
    });
    expect(d.id, 'd1');
    expect(d.type, DefenceType.preOral);
    expect(d.panelUids, ['p1', 'p2', 'p3']);
    expect(d.leaderUid, 'l1');
    expect(d.status, DefenceStatus.inProgress);
    expect(d.venue, 'CICT AVR');
  });

  test('isReleased is false until consolidatedAt is set', () {
    // consolidatedAt is what opens the log to the group, so its absence is
    // load-bearing: a defence with no timestamp must never read as released.
    final unreleased = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'status': 'completed',
      'panelUids': <String>[],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'createdBy': 'c1',
      'venue': 'AVR',
    });
    expect(unreleased.isReleased, isFalse);

    final released = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'status': 'completed',
      'panelUids': <String>[],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'createdBy': 'c1',
      'venue': 'AVR',
      'consolidatedAt': DateTime.utc(2026, 9, 2),
    });
    expect(released.isReleased, isTrue);
  });

  test('a comment parses its stored shape', () {
    final c = DefenceComment.fromMap('cm1', {
      'authorUid': 'p1',
      'authorName': 'Dr. Diamante',
      'authorPosition': 'Panel Member',
      'body': 'Justify the choice of respondents.',
      'createdAt': DateTime.utc(2026, 9, 1, 9, 15),
    });
    expect(c.id, 'cm1');
    expect(c.authorPosition, 'Panel Member');
    expect(c.body, 'Justify the choice of respondents.');
  });

  test('a cancelled defence is terminal and accepts no comments', () {
    // Cancelled rather than deleted: the defence record is evidence, and a
    // hard delete leaves nothing to explain a gap in the history.
    expect(DefenceStatus.cancelled.acceptsComments, isFalse);
    expect(DefenceStatus.cancelled.isTerminal, isTrue);
    expect(DefenceStatus.cancelled.isEditable, isFalse);
    expect(DefenceStatus.fromString('cancelled'), DefenceStatus.cancelled);
  });

  test('only a scheduled defence is editable', () {
    expect(DefenceStatus.scheduled.isEditable, isTrue);
    expect(DefenceStatus.inProgress.isEditable, isFalse);
    expect(DefenceStatus.completed.isEditable, isFalse);
  });

  test('the open grace window is 30 minutes', () {
    // Pinned because firestore.rules carries the same number as a literal.
    // If the two disagree the button looks enabled and the write is denied.
    expect(defenceOpenGrace, const Duration(minutes: 30));
  });

  // The four M4 fields are absent on every defence created before this
  // milestone, so absent must read as "not yet", never as an error and
  // never as a value.
  test('a defence with no evaluation fields is unreleased and unjudged',
      () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
    });

    expect(d.evaluationsReleasedAt, isNull);
    expect(d.evaluationsReleased, isFalse);
    expect(d.panelVerdict, isNull);
    expect(d.hasVerdict, isFalse);
    expect(d.verdictRecordedBy, isNull);
    expect(d.verdictRecordedAt, isNull);
  });

  test('a released, judged defence reads all four back', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
      'evaluationsReleasedAt': DateTime(2026, 9, 23, 14),
      'panelVerdict': 'pass',
      'verdictRecordedBy': 'a1',
      'verdictRecordedAt': DateTime(2026, 9, 23, 15),
    });

    expect(d.evaluationsReleased, isTrue);
    expect(d.panelVerdict, PassFail.pass);
    expect(d.hasVerdict, isTrue);
    expect(d.verdictRecordedBy, 'a1');
    expect(d.verdictRecordedAt, DateTime(2026, 9, 23, 15));
  });

  // Release and consolidation are separate acts on separate gates. A
  // defence whose comments are released has not thereby released its
  // grades, and vice versa.
  test('releasing the comments does not release the evaluations', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
      'consolidatedAt': DateTime(2026, 9, 23, 13),
    });

    expect(d.isReleased, isTrue);
    expect(d.evaluationsReleased, isFalse);
  });

  test('an unreadable verdict is null rather than a pass', () {
    final d = Defence.fromMap('d1', {
      'thesisId': 't1',
      'type': 'final',
      'venue': 'AVR',
      'panelUids': <String>['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
      'createdBy': 'c1',
      'panelVerdict': 'PASSED',
    });

    expect(d.panelVerdict, isNull);
    expect(d.hasVerdict, isFalse);
  });

  Defence defence(
    String id, {
    DefenceType type = DefenceType.preOral,
    PassFail? verdict,
    String? redefenceOf,
    DefenceStatus status = DefenceStatus.completed,
  }) =>
      Defence(
        id: id,
        thesisId: 't1',
        type: type,
        venue: 'AVR',
        panelUids: const ['p1'],
        adviserUid: 'a1',
        leaderUid: 'l1',
        status: status,
        createdBy: 'c1',
        panelVerdict: verdict,
        redefenceOf: redefenceOf,
      );

  group('re-defence', () {
    test('reads redefenceOf, and a defence without it is not a re-defence',
        () {
      final plain = Defence.fromMap('d1', {'type': 'final'});
      expect(plain.redefenceOf, isNull);
      expect(plain.isRedefence, isFalse);

      final again = Defence.fromMap('d1_redefence', {
        'type': 'final',
        'redefenceOf': 'd1',
      });
      expect(again.redefenceOf, 'd1');
      expect(again.isRedefence, isTrue);
    });

    test('names all four kinds', () {
      expect(defence('a').label, 'Pre-oral defence');
      expect(defence('a', type: DefenceType.final_).label, 'Final defence');
      expect(defence('a', redefenceOf: 'x').label, 'Pre-oral re-defence');
      expect(defence('a', type: DefenceType.final_, redefenceOf: 'x').label,
          'Final re-defence');
    });

    test('a re-defence has the id derived from the failed defence', () {
      expect(Defence.redefenceIdFor('abc'), 'abc_redefence');
    });

    test('a failed defence with no re-defence awaits one', () {
      final failed = defence('d1', verdict: PassFail.fail);
      expect(awaitingRedefence([failed]), [failed]);
    });

    test('a failed defence that has its re-defence awaits nothing', () {
      final failed = defence('d1', verdict: PassFail.fail);
      final again = defence('d1_redefence', redefenceOf: 'd1',
          status: DefenceStatus.scheduled);
      expect(awaitingRedefence([failed, again]), isEmpty);
      expect(hasRedefence(failed, [failed, again]), isTrue);
    });

    test('a cancelled re-defence still uses up the one re-defence', () {
      // The rules refuse a second document at the same derived id, so the
      // app must not offer a re-defence it cannot create.
      final failed = defence('d1', verdict: PassFail.fail);
      final cancelled = defence('d1_redefence', redefenceOf: 'd1',
          status: DefenceStatus.cancelled);
      expect(awaitingRedefence([failed, cancelled]), isEmpty);
    });

    test('a failed re-defence, a pass and no verdict await nothing', () {
      expect(
        awaitingRedefence([
          defence('r', verdict: PassFail.fail, redefenceOf: 'x'),
          defence('p', verdict: PassFail.pass),
          defence('n'),
        ]),
        isEmpty,
      );
    });
  });
}
