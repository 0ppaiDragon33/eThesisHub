import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';

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

Widget wrap(FakeFirebaseFirestore db, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        ...overrides,
      ],
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

  // The six tests below close the gap the coordinator's review found: the
  // three tests above all pumpAndSettle immediately, so none of them ever
  // observes a loading or error branch. A regression collapsing any one of
  // the six `isLoading`/`hasError` checks in the screen back into
  // `valueOrNull ?? const []` would compile and pass every test above
  // without ever showing up here -- which is exactly the defect this
  // project has now shipped four times, most recently in the chapters list
  // screen this one mirrors.

  const chapterRef = (thesisId: 't1', chapter: ChapterId.chapterI);

  testWidgets(
      'the chapters stream loading is shown, not collapsed into "Not started"',
      (tester) async {
    // A stream that never emits: pumping once (not pumpAndSettle, which
    // would race past this and resolve the fake Firestore read first) keeps
    // the widget in the loading state for as long as the test looks at it.
    final neverChapters = StreamController<List<ThesisChapter>>();
    addTearDown(neverChapters.close);

    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chaptersProvider('t1').overrideWith((ref) => neverChapters.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading this chapter…'), findsOneWidget);
    expect(find.byKey(const Key('notStarted')), findsNothing);
    expect(find.byKey(const Key('versionRow-1')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'a chapters stream error is shown alone, not alongside contradictory content',
      (tester) async {
    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chaptersProvider('t1').overrideWith(
            (ref) => Stream<List<ThesisChapter>>.error(Exception('boom'))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not load this chapter.'), findsOneWidget);
    expect(find.byKey(const Key('notStarted')), findsNothing);
    expect(find.byKey(const Key('versionRow-1')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'the versions stream loading is shown, not collapsed into an empty list',
      (tester) async {
    final neverVersions = StreamController<List<ChapterVersion>>();
    addTearDown(neverVersions.close);

    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chapterVersionsProvider(chapterRef)
            .overrideWith((ref) => neverVersions.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading versions…'), findsOneWidget);
    expect(find.byKey(const Key('versionRow-1')), findsNothing);
    expect(find.byKey(const Key('versionRow-2')), findsNothing);
    expect(find.byKey(const Key('feedbackRow-f1')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'a versions stream error is shown alone, not alongside an empty-looking list',
      (tester) async {
    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chapterVersionsProvider(chapterRef).overrideWith(
            (ref) => Stream<List<ChapterVersion>>.error(Exception('boom'))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not load the versions of this chapter.'),
        findsOneWidget);
    expect(find.byKey(const Key('versionRow-1')), findsNothing);
    expect(find.byKey(const Key('versionRow-2')), findsNothing);
    // A version-less "No versions yet" beside this error would say two
    // contradictory things about the same read at once.
    expect(find.text('No versions yet'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'the feedback stream loading is shown, not collapsed into an empty list',
      (tester) async {
    final neverFeedback = StreamController<List<ChapterFeedback>>();
    addTearDown(neverFeedback.close);

    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chapterFeedbackProvider(chapterRef)
            .overrideWith((ref) => neverFeedback.stream),
      ],
    ));
    // Two real streams sit ahead of this one in the build (chaptersAsync,
    // versionsAsync), each backed by fake_cloud_firestore rather than
    // overridden, so each needs its own microtask tick to deliver its first
    // snapshot. A single pump() left one of them still loading and the
    // screen showed an earlier branch's message instead of this one -- not
    // pumpAndSettle (which would race the never-emitting controller's
    // stream to a false "settled" state), just enough discrete pumps to let
    // the two real streams resolve while the overridden one stays stuck.
    await tester.pump();
    await tester.pump();

    expect(find.text('Loading feedback…'), findsOneWidget);
    expect(find.byKey(const Key('feedbackRow-f1')), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'a feedback stream error is shown alone, not alongside an empty-looking list',
      (tester) async {
    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chapterFeedbackProvider(chapterRef).overrideWith(
            (ref) => Stream<List<ChapterFeedback>>.error(Exception('boom'))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not load feedback for this chapter.'),
        findsOneWidget);
    expect(find.byKey(const Key('feedbackRow-f1')), findsNothing);
    // A feedback-less "No feedback yet" beside this error would say two
    // contradictory things about the same read at once.
    expect(find.text('No feedback yet'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
