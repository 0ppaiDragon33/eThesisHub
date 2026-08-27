import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/documents/chapters_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Future<FakeFirebaseFirestore> seed({
  String status = 'titleApproved',
  Map<String, dynamic>? chapter,
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': status,
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  if (chapter != null) {
    await db.collection('theses').doc('t1')
        .collection('documents').doc('chapterI').set(chapter);
  }
  return db;
}

Widget wrap(FakeFirebaseFirestore db, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        ...overrides,
      ],
      // the app shell supplies the Scaffold in the real app.
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Chapters')),
          body: ChaptersScreen(thesisId: 't1'),
        ),
      ),
    );

void main() {
  testWidgets('all five chapters are listed even when none are uploaded',
      (tester) async {
    // "Not started" is derived from absence: no document is written until
    // the first upload, so the screen must render the full set itself.
    await tester.pumpWidget(wrap(await seed()));
    await tester.pumpAndSettle();

    for (final id in ['chapterI', 'chapterII', 'chapterIII', 'chapterIV',
                      'chapterV']) {
      expect(find.byKey(Key('chapterRow-$id')), findsOneWidget);
    }
    expect(find.textContaining('Not started'), findsNWidgets(5));
  });

  testWidgets('an uploaded chapter shows its status and version',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(chapter: {
      'type': 'chapterI', 'currentVersion': 3, 'status': 'revise',
    })));
    await tester.pumpAndSettle();

    expect(find.textContaining('Needs revision'), findsOneWidget);
    expect(find.textContaining('Version 3'), findsOneWidget);
  });

  testWidgets('chapters are refused before the title is approved, with a way out',
      (tester) async {
    await tester.pumpWidget(wrap(await seed(status: 'titlePendingDefence')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notUnlocked')), findsOneWidget);
    expect(find.byKey(const Key('chapterRow-chapterI')), findsNothing);
    // A refusal with no app bar strands the user: they must reload the app.
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('the thesis stream loading is shown, not collapsed into absent',
      (tester) async {
    // A stream that never emits: the widget stays in the loading state for
    // as long as the test looks at it, without pumpAndSettle racing past it.
    final neverThesis = StreamController<Thesis?>();
    addTearDown(neverThesis.close);

    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        thesisByIdProvider('t1').overrideWith((ref) => neverThesis.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading your thesis…'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('a thesis stream error is shown, framed', (tester) async {
    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        thesisByIdProvider('t1')
            .overrideWith((ref) => Stream<Thesis?>.error(Exception('boom'))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not load this thesis.'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('a thesis that does not exist says so, framed', (tester) async {
    // No thesis doc is ever written: the stream resolves to data(null)
    // rather than loading or erroring.
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('Thesis not found'), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'the chapters stream loading is shown, not collapsed into "Not started"',
      (tester) async {
    final neverChapters = StreamController<List<ThesisChapter>>();
    addTearDown(neverChapters.close);

    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chaptersProvider('t1').overrideWith((ref) => neverChapters.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('Loading your chapters…'), findsOneWidget);
    expect(find.textContaining('Not started'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets(
      'a chapters stream error is shown alone, not alongside contradictory rows',
      (tester) async {
    await tester.pumpWidget(wrap(
      await seed(),
      overrides: [
        chaptersProvider('t1').overrideWith(
            (ref) => Stream<List<ThesisChapter>>.error(Exception('boom'))),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your chapters.'), findsOneWidget);
    expect(find.textContaining('Not started'), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });
}
