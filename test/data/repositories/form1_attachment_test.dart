import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';

/// The Form 1 copy a leader may send along with the nomination: written as a
/// snapshot in the submit batch, read back for the signers, and cleared when
/// a reopened thesis is submitted again without one.
FacultyDirectoryEntry faculty(String uid, String name,
        {String role = 'faculty'}) =>
    FacultyDirectoryEntry(uid: uid, fullName: name, role: role);

FormCopy copy({String formId = 'form1', String name = 'Group 3'}) => FormCopy(
      id: 'c1',
      formId: formId,
      name: name,
      overrides: const {'salutation': 'Dear Sir:'},
    );

void main() {
  late FakeFirebaseFirestore db;
  late ThesisRepository repo;

  final adviser = faculty('adv', 'Adviser 1');
  final panel = [
    faculty('p1', 'Panel 1'),
    faculty('p2', 'Panel 2'),
    faculty('p3', 'Panel 3'),
  ];

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = ThesisRepository(db);
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'leader',
      'status': 'draft',
      'workingTitle': 'T',
      'memberNames': <String>[],
      'panelistUids': <String>[],
      'academicYear': '2026-2027',
    });
  });

  Future<void> submit({FormCopy? form1Copy}) => repo.submitNominations(
        thesisId: 't1',
        adviser: adviser,
        panelists: panel,
        exOfficio: const [],
        form1Copy: form1Copy,
        leaderUid: 'leader',
      );

  test('a submission with a copy stores its name and text', () async {
    await submit(form1Copy: copy());

    final doc = await db.doc('theses/t1/attachments/form1').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['formId'], 'form1');
    expect(doc.data()!['copyName'], 'Group 3');
    expect(doc.data()!['overrides'], {'salutation': 'Dear Sir:'});
    expect(doc.data()!['attachedBy'], 'leader');
  });

  test('the attachment is read back for the signers', () async {
    await submit(form1Copy: copy());

    final attached = await repo.watchForm1Attachment('t1').first;
    expect(attached, isNotNull);
    expect(attached!.copyName, 'Group 3');
    expect(attached.overrides, {'salutation': 'Dear Sir:'});
  });

  test('a submission without a copy stores no attachment', () async {
    await submit();

    expect((await db.doc('theses/t1/attachments/form1').get()).exists, isFalse);
    expect(await repo.watchForm1Attachment('t1').first, isNull);
  });

  test('submitting again without a copy clears the earlier one', () async {
    await submit(form1Copy: copy());
    await db.collection('theses').doc('t1').update({'status': 'draft'});

    await submit();

    expect((await db.doc('theses/t1/attachments/form1').get()).exists, isFalse);
  });

  test('only a copy of Form 1 can be attached', () async {
    await expectLater(
      submit(form1Copy: copy(formId: 'form3')),
      throwsArgumentError,
    );
    expect((await db.collection('theses/t1/nominations').get()).docs, isEmpty);
  });
}
