import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

Future<FakeFirebaseFirestore> seed({String status = 'inProgress'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'preOral',
    'panelUids': ['p1'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
  });
  return db;
}

const box = NormRect(x: 0.1, y: 0.2, w: 0.5, h: 0.05);

Future<void> add(DefenceRepository repo,
        {String uid = 'p1', String body = 'Cite it.', NormRect rect = box}) =>
    repo.addAnnotation(
      defenceId: 'd1',
      authorUid: uid,
      authorName: 'Dr. Panel',
      authorPosition: 'Panel Member',
      chapter: ChapterId.chapterII,
      version: 2,
      page: 3,
      rect: rect,
      body: body,
    );

void main() {
  test('adds a highlight with every field, trimmed', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    await add(repo, body: '  Cite it.  ');

    final docs = (await db.collection('defenses/d1/annotations').get()).docs;
    expect(docs, hasLength(1));
    final data = docs.single.data();
    expect(data['authorUid'], 'p1');
    expect(data['chapter'], 'chapterII');
    expect(data['version'], 2);
    expect(data['page'], 3);
    expect(data['rect'], {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.05});
    expect(data['body'], 'Cite it.');
    expect(data['createdAt'], isA<Timestamp>());
  });

  test('refuses an empty or over-long comment, and a tiny box', () async {
    final repo = DefenceRepository(await seed());
    await expectLater(add(repo, body: '  '), throwsArgumentError);
    await expectLater(add(repo, body: 'x' * (kAnnotationMaxLength + 1)),
        throwsArgumentError);
    await expectLater(
        add(repo, rect: const NormRect(x: 0.1, y: 0.1, w: 0.001, h: 0.1)),
        throwsArgumentError);
  });

  test('refuses a highlight unless the defence is in progress', () async {
    for (final status in ['scheduled', 'completed', 'cancelled']) {
      final repo = DefenceRepository(await seed(status: status));
      await expectLater(add(repo), throwsStateError, reason: status);
    }
  });

  test('watches highlights oldest first and skips a malformed one', () async {
    final db = await seed();
    await db.collection('defenses/d1/annotations').doc('b').set({
      'authorUid': 'a1', 'chapter': 'chapterI', 'version': 1, 'page': 0,
      'rect': {'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5}, 'body': 'second',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 26, 9, 2)),
    });
    await db.collection('defenses/d1/annotations').doc('a').set({
      'authorUid': 'p1', 'chapter': 'chapterI', 'version': 1, 'page': 0,
      'rect': {'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5}, 'body': 'first',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 26, 9, 1)),
    });
    await db.collection('defenses/d1/annotations').doc('bad').set({
      'authorUid': 'p1', 'chapter': 'chapterIX', 'version': 1, 'page': 0,
      'rect': {'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5}, 'body': 'lost',
    });

    final list = await DefenceRepository(db).watchAnnotations('d1').first;
    expect(list.map((a) => a.body), ['first', 'second']);
  });

  test('deletes your own highlight only, and only while in progress',
      () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    await add(repo);
    final id = (await db.collection('defenses/d1/annotations').get())
        .docs
        .single
        .id;

    await expectLater(
        repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'a1'),
        throwsStateError);

    await db.collection('defenses').doc('d1').update({'status': 'completed'});
    await expectLater(
        repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'p1'),
        throwsStateError);

    await db.collection('defenses').doc('d1').update({'status': 'inProgress'});
    await repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'p1');
    expect((await db.collection('defenses/d1/annotations').get()).docs,
        isEmpty);
    // A second delete of the same highlight is not an error.
    await repo.deleteAnnotation(defenceId: 'd1', annotationId: id, uid: 'p1');
  });

  test('marks, watches and clears a typing marker', () async {
    final db = await seed();
    final repo = DefenceRepository(db);
    await repo.markComposing(
      defenceId: 'd1',
      uid: 'p1',
      name: 'Dr. Panel',
      position: 'Panel Member',
      target: ComposingTarget.manuscript,
    );
    final markers = await repo.watchComposing('d1').first;
    expect(markers.single.uid, 'p1');
    expect(markers.single.target, ComposingTarget.manuscript);

    await repo.clearComposing(defenceId: 'd1', uid: 'p1');
    await repo.clearComposing(defenceId: 'd1', uid: 'p1');
    expect(await repo.watchComposing('d1').first, isEmpty);
  });
}
