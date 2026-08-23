// test/data/models/defence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/defence.dart';

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
}
