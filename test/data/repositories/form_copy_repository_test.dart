import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late FormCopyRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FormCopyRepository(db);
  });

  Future<void> seed(String uid, String id, String formId, DateTime updated) =>
      db.doc('users/$uid/formCopies/$id').set({
        'formId': formId,
        'name': id,
        'overrides': <String, String>{},
        'folderId': null,
        'createdAt': Timestamp.fromDate(updated),
        'updatedAt': Timestamp.fromDate(updated),
      });

  test('create writes an unedited copy under the user and returns its id',
      () async {
    final id = await repo.create(
        uid: 'u1', formId: 'form1', name: '  Group 3 – Santos  ');
    final data = (await db.doc('users/u1/formCopies/$id').get()).data()!;
    expect(data['formId'], 'form1');
    expect(data['name'], 'Group 3 – Santos', reason: 'the name is trimmed');
    expect(data['overrides'], isEmpty);
    expect(data['folderId'], isNull);
    expect(data['createdAt'], isA<Timestamp>());
    expect(data['updatedAt'], isA<Timestamp>());
    expect(data.keys.toSet(), {
      'formId', 'name', 'overrides', 'folderId', 'createdAt', 'updatedAt'
    }, reason: 'exactly the fields the rules allow');
  });

  test('a name must be 1 to $kFormCopyNameMax characters', () async {
    expect(() => repo.create(uid: 'u1', formId: 'form1', name: '   '),
        throwsArgumentError);
    expect(
        () => repo.create(
            uid: 'u1', formId: 'form1', name: 'x' * (kFormCopyNameMax + 1)),
        throwsArgumentError);
  });

  test('watchCopies lists only this form\'s copies, newest first', () async {
    await seed('u1', 'old', 'form1', DateTime(2026, 9, 1));
    await seed('u1', 'new', 'form1', DateTime(2026, 9, 3));
    await seed('u1', 'other-form', 'form3', DateTime(2026, 9, 4));
    await seed('u2', 'someone-else', 'form1', DateTime(2026, 9, 5));

    final copies = await repo.watchCopies('u1', formId: 'form1').first;
    expect(copies.map((c) => c.id), ['new', 'old']);
  });

  test('watchCopy reads one copy, and null once it is gone', () async {
    await seed('u1', 'c1', 'form1', DateTime(2026, 9, 1));
    expect((await repo.watchCopy('u1', 'c1').first)!.name, 'c1');
    await repo.delete(uid: 'u1', copyId: 'c1');
    expect(await repo.watchCopy('u1', 'c1').first, isNull);
  });

  test('saveOverrides replaces the stored edits', () async {
    await seed('u1', 'c1', 'form1', DateTime(2026, 9, 1));
    await repo.saveOverrides(
        uid: 'u1', copyId: 'c1', overrides: {'salutation': 'Dear Dean:'});
    await repo.saveOverrides(
        uid: 'u1', copyId: 'c1', overrides: {'closing': 'Thank you.'});
    final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
    expect(data['overrides'], {'closing': 'Thank you.'});
  });

  test('rename trims the new name and refuses an empty one', () async {
    await seed('u1', 'c1', 'form1', DateTime(2026, 9, 1));
    await repo.rename(uid: 'u1', copyId: 'c1', name: ' Renamed ');
    expect((await db.doc('users/u1/formCopies/c1').get()).data()!['name'],
        'Renamed');
    expect(() => repo.rename(uid: 'u1', copyId: 'c1', name: ''),
        throwsArgumentError);
  });

  test('fromMap ignores an override that is not text', () {
    final copy = FormCopy.fromMap('c1', {
      'formId': 'form1',
      'name': 'n',
      'overrides': {'salutation': 'Dear Dean:', 'bad': 3},
      'folderId': null,
    });
    expect(copy.overrides, {'salutation': 'Dear Dean:'});
    expect(copy.updatedAt, isNull);
  });
}
