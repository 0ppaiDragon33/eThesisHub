import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';

void main() {
  test('a comment records the author and the role held at the time', () async {
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);

    await repo.addComment(
      thesisId: 't1', candidateTitleId: 'ct1',
      authorUid: 'p1', authorName: 'Dr. Diamante', authorRole: 'Panel Member',
      body: 'Justify the choice of respondents.',
    );

    final comments = await repo.watchComments('t1').first;
    expect(comments, hasLength(1));
    expect(comments.single.authorUid, 'p1');
    expect(comments.single.authorRole, 'Panel Member');
    expect(comments.single.candidateTitleId, 'ct1');
  });

  test('an empty comment is refused', () async {
    final repo = TitleDefenceRepository(FakeFirebaseFirestore());
    expect(
      () => repo.addComment(
        thesisId: 't1', candidateTitleId: 'ct1', authorUid: 'p1',
        authorName: 'Dr. Diamante', authorRole: 'Panel Member', body: '   ',
      ),
      throwsArgumentError,
    );
  });

  test('comments come back oldest first', () async {
    // The consolidated output reads as a transcript, so order is the record.
    //
    // Writing through addComment() in creation order isn't a real test here:
    // fake_cloud_firestore's default (no-orderBy) snapshot order already
    // matches insertion order, which in that case also matches createdAt
    // order — so the assertion would pass whether or not watchComments
    // actually sorts. To make the orderBy clause load-bearing, the docs are
    // written directly with explicit createdAt values in an order that
    // DISAGREES with insertion order: the doc inserted first is timestamped
    // latest. Only an actual `orderBy('createdAt')` can produce the
    // oldest-first result below.
    final db = FakeFirebaseFirestore();
    final repo = TitleDefenceRepository(db);
    final comments = db
        .collection('theses')
        .doc('t1')
        .collection('titleComments');

    Future<void> write(String body, DateTime at) => comments.add({
          'candidateTitleId': 'ct1',
          'authorUid': 'p1',
          'authorName': 'Dr. Diamante',
          'authorRole': 'Panel Member',
          'body': body,
          'createdAt': Timestamp.fromDate(at),
        });

    // Inserted in this order: third, first, second — but timestamped so
    // that the true chronological order is first, second, third.
    await write('third', DateTime(2026, 1, 3));
    await write('first', DateTime(2026, 1, 1));
    await write('second', DateTime(2026, 1, 2));

    final result = await repo.watchComments('t1').first;
    expect(result.map((c) => c.body), ['first', 'second', 'third']);
  });
}
