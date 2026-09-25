import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';

void main() {
  test('the enums round-trip and default safely', () {
    expect(ChangeRequestType.adviser.value, 'adviser');
    expect(ChangeRequestType.title.id, 'title');
    expect(ChangeRequestType.fromString('title'), ChangeRequestType.title);
    expect(ChangeRequestType.fromString('nope'), isNull);
    expect(SignoffStatus.fromString('accepted'), SignoffStatus.accepted);
    expect(SignoffStatus.fromString(null), SignoffStatus.pending);
    expect(
      ChangeRequestStage.fromString('pendingDean'),
      ChangeRequestStage.pendingDean,
    );
    expect(ChangeRequestStage.fromString('junk'), isNull);
  });

  test('the roles and first stage differ by type', () {
    expect(signoffRolesFor(ChangeRequestType.adviser), [
      'newAdviser',
      'formerAdviser',
      'coordinator',
      'dean',
    ]);
    expect(signoffRolesFor(ChangeRequestType.title), [
      'adviser',
      'coordinator',
      'dean',
    ]);
    expect(
      firstStageFor(ChangeRequestType.adviser),
      ChangeRequestStage.pendingAdvisers,
    );
    expect(
      firstStageFor(ChangeRequestType.title),
      ChangeRequestStage.pendingAdviser,
    );
  });

  test('nextStage walks the chain and stops at the Dean', () {
    expect(
      nextStage(ChangeRequestStage.pendingAdvisers),
      ChangeRequestStage.pendingCoordinator,
    );
    expect(
      nextStage(ChangeRequestStage.pendingAdviser),
      ChangeRequestStage.pendingCoordinator,
    );
    expect(
      nextStage(ChangeRequestStage.pendingCoordinator),
      ChangeRequestStage.pendingDean,
    );
    expect(nextStage(ChangeRequestStage.pendingDean), isNull);
  });

  test('an adviser request parses its stored shape', () {
    final r = ChangeRequest.fromMap('adviser', {
      'type': 'adviser',
      'stage': 'pendingAdvisers',
      'reasons': 'The adviser moved campus.',
      'leaderUid': 'l1',
      'newAdviserUid': 'a2',
      'newAdviserName': 'Dr. New',
      'formerAdviserUid': 'a1',
      'formerAdviserName': 'Dr. Old',
      'signoffs': {
        'newAdviser': {'status': 'pending'},
        'formerAdviser': {'status': 'accepted'},
        'coordinator': {'status': 'pending'},
        'dean': {'status': 'pending'},
      },
    });
    expect(r.type, ChangeRequestType.adviser);
    expect(r.stage, ChangeRequestStage.pendingAdvisers);
    expect(r.newAdviserUid, 'a2');
    expect(r.formerAdviserName, 'Dr. Old');
    expect(r.signoffs['formerAdviser']!.status, SignoffStatus.accepted);
    expect(r.isOpen, isTrue);
  });

  test('an approved request is not open', () {
    final r = ChangeRequest.fromMap('title', {
      'type': 'title',
      'stage': 'approved',
      'reasons': 'x',
      'leaderUid': 'l1',
      'newTitle': 'A Better Title',
      'signoffs': const {},
    });
    expect(r.isOpen, isFalse);
    expect(r.newTitle, 'A Better Title');
  });
}
