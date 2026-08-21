import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seed({int versions = 2}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  final chapter = db.collection('theses').doc('t1')
      .collection('documents').doc('chapterI');
  await chapter.set({
    'type': 'chapterI', 'currentVersion': versions, 'status': 'revise',
  });
  for (var v = 1; v <= versions; v++) {
    await chapter.collection('versions').doc('$v').set({
      'version': v, 'storagePath': 'p$v', 'fileUrl': 'https://x/$v.pdf',
      'uploadedBy': 'l1', 'mimeType': 'application/pdf', 'sizeBytes': 10,
    });
  }
  await chapter.collection('feedback').doc('f1').set({
    'version': 1, 'reviewerUid': 'a1', 'reviewerName': 'Dr. Armada',
    'reviewerRole': 'Adviser', 'body': 'Tighten the problem statement.',
  });
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(db)],
      child: const MaterialApp(
        home: ChapterDetailScreen(
            thesisId: 't1', chapter: ChapterId.chapterI),
      ),
    );

void main() {
  testWidgets('every version is listed, newest first', (tester) async {
    await tester.pumpWidget(wrap(await seed()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('versionRow-1')), findsOneWidget);
    expect(find.byKey(const Key('versionRow-2')), findsOneWidget);

    final rows = tester.widgetList(find.byType(ListTile)).length;
    expect(rows, greaterThanOrEqualTo(2));

    final first = tester.getTopLeft(find.byKey(const Key('versionRow-2')));
    final second = tester.getTopLeft(find.byKey(const Key('versionRow-1')));
    expect(first.dy, lessThan(second.dy),
        reason: 'the newest version is what a reviewer opens');
  });

  testWidgets('feedback is shown against the version it addresses',
      (tester) async {
    await tester.pumpWidget(wrap(await seed()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feedbackRow-f1')), findsOneWidget);
    expect(find.textContaining('Tighten the problem statement.'),
        findsOneWidget);
    expect(find.textContaining('Version 1'), findsWidgets);
  });

  testWidgets('a chapter with no uploads says so, inside a frame',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set({
      'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
      'panelistUids': <String>[], 'memberNames': <String>[],
      'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
      'semester': 'First', 'academicYear': '2026-2027',
    });
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notStarted')), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
