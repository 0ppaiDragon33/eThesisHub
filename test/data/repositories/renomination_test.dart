import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

/// Re-submitting after a coordinator reopens a stalled thesis.
///
/// The rules make this narrow on purpose. A leader may delete a nomination
/// only while the thesis is `draft` AND only one whose `conformeStatus` is
/// `declined`; they may never UPDATE a nomination at all, because the update
/// arm is pinned to `request.auth.uid == nomineeUid` — answering is the
/// nominee's alone.
///
/// So a re-submission that rewrites the whole roster is refused twice over,
/// and it would also reset everyone who had already accepted back to
/// `pending`. The behaviour these tests pin is the one the rules already
/// permit and the one the owner asked for: whoever accepted stays accepted
/// and is not asked again, and only the declined seat is refilled.
FacultyDirectoryEntry faculty(String uid, String name, {String role = 'faculty'}) =>
    FacultyDirectoryEntry(uid: uid, fullName: name, role: role);

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;

  final adviser = faculty('adv', 'Adviser 1');
  final p1 = faculty('p1', 'Panel 1');
  final p2 = faculty('p2', 'Panel 2');
  final p3 = faculty('p3', 'Karu Sama');
  final replacement = faculty('p4', 'Replacement');
  final coordinator = faculty('coord', 'Karl Joshua', role: 'coordinator');
  final dean = faculty('dean', 'Dean', role: 'dean');

  Future<void> seedThesis({required String status}) =>
      db.collection('theses').doc('t1').set({
        'leaderUid': 'leader',
        'status': status,
        'workingTitle': 'T',
        'memberNames': <String>[],
        'panelistUids': <String>[],
        'academicYear': '2026-2027',
      });

  Map<String, dynamic> nom(String uid, String status, {String position = 'panelist'}) => {
        'nomineeUid': uid,
        'nomineeName': uid,
        'position': position,
        'exOfficio': false,
        'conformeStatus': status,
        'respondedAt': null,
        'declineReason': null,
      };

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
  });

  Future<Map<String, Map<String, dynamic>>> nominations() async {
    final snap = await db.collection('theses/t1/nominations').get();
    return {for (final d in snap.docs) d.id: d.data()};
  }

  test('a first submission still writes the whole roster', () async {
    await seedThesis(status: 'draft');

    await repo.submitNominations(
      thesisId: 't1',
      adviser: adviser,
      panelists: [p1, p2, p3],
      exOfficio: [coordinator, dean],
    );

    final noms = await nominations();
    expect(noms.keys.toSet(), {'adv', 'p1', 'p2', 'p3', 'coord', 'dean'});
    expect(noms['p1']!['conformeStatus'], 'pending');
  });

  group('after a reopen', () {
    setUp(() async {
      await seedThesis(status: 'draft');
      // The state a reopen leaves behind: three answers already given, one
      // of them a refusal.
      await db.collection('theses/t1/nominations').doc('adv').set(
          nom('adv', 'accepted', position: 'adviser'));
      await db.collection('theses/t1/nominations').doc('p1').set(
          nom('p1', 'accepted'));
      await db.collection('theses/t1/nominations').doc('p2').set(
          nom('p2', 'pending'));
      await db.collection('theses/t1/nominations').doc('p3').set(
          nom('p3', 'declined'));
      await db.collection('theses/t1/nominations').doc('coord').set(
          {...nom('coord', 'exOfficio', position: 'coordinator'),
           'exOfficio': true});
      await db.collection('theses/t1/nominations').doc('dean').set(
          {...nom('dean', 'exOfficio', position: 'dean'), 'exOfficio': true});
    });

    test('someone who already accepted is not asked again', () async {
      await repo.submitNominations(
        thesisId: 't1',
        adviser: adviser,
        panelists: [p1, p2, replacement],
        exOfficio: [coordinator, dean],
      );

      final noms = await nominations();
      // The whole point: rewriting these would reset a given answer, and the
      // rules would refuse the write anyway.
      expect(noms['adv']!['conformeStatus'], 'accepted');
      expect(noms['p1']!['conformeStatus'], 'accepted');
      expect(noms['p2']!['conformeStatus'], 'pending');
    });

    test('the declined seat is removed and the replacement is asked',
        () async {
      await repo.submitNominations(
        thesisId: 't1',
        adviser: adviser,
        panelists: [p1, p2, replacement],
        exOfficio: [coordinator, dean],
      );

      final noms = await nominations();
      expect(noms.containsKey('p3'), isFalse,
          reason: 'the refusal must not linger and stall the thesis again');
      expect(noms['p4']!['conformeStatus'], 'pending');
    });

    test('the thesis goes back out for conforme', () async {
      await repo.submitNominations(
        thesisId: 't1',
        adviser: adviser,
        panelists: [p1, p2, replacement],
        exOfficio: [coordinator, dean],
      );

      final t = (await db.collection('theses').doc('t1').get()).data()!;
      expect(t['status'], 'nominationPendingConforme');
    });

    // Dropping a seat that was not refused is not a thing this flow does,
    // and the rules would refuse the delete. Failing loudly here beats
    // leaving an orphan nomination that counts as outstanding forever.
    test('dropping a seat that did not decline is refused with a reason',
        () async {
      // p1 accepted and is dropped from the roster. p3 declined and is
      // replaced, which is allowed — so the only thing under test here is
      // the dropped accepted seat.
      await expectLater(
        repo.submitNominations(
          thesisId: 't1',
          adviser: adviser,
          panelists: [p2, replacement, faculty('p5', 'Another')],
          exOfficio: [coordinator, dean],
        ),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message.toString(), 'message', contains('accepted'))),
      );
    });
  });
}
