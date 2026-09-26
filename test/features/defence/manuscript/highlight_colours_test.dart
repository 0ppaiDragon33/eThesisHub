import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';

Defence defence({List<String> panel = const ['p1', 'p2']}) => Defence(
      id: 'd1',
      thesisId: 't1',
      type: DefenceType.preOral,
      venue: 'AVR',
      panelUids: panel,
      adviserUid: 'a1',
      leaderUid: 'l1',
      status: DefenceStatus.inProgress,
      createdBy: 'c1',
    );

DefenceAnnotation note(String id, String uid,
        {ChapterId chapter = ChapterId.chapterI,
        int page = 0,
        double y = 0,
        String name = ''}) =>
    DefenceAnnotation(
      id: id,
      authorUid: uid,
      authorName: name.isEmpty ? uid : name,
      authorPosition: 'Panel Member',
      chapter: chapter,
      version: 1,
      page: page,
      rect: NormRect(x: 0, y: y, w: 0.5, h: 0.05),
      body: id,
    );

void main() {
  test('eight distinct colours', () {
    expect(kHighlightPalette, hasLength(8));
    expect(kHighlightPalette.toSet(), hasLength(8));
  });

  test('adviser, then panel in order, then others by first highlight', () {
    final colours = highlightColours(
      defence: defence(),
      annotations: [note('h1', 'dean1'), note('h2', 'p2'), note('h3', 'c1')],
    );
    expect(colours['a1'], kHighlightPalette[0]);
    expect(colours['p1'], kHighlightPalette[1]);
    expect(colours['p2'], kHighlightPalette[2]);
    expect(colours['dean1'], kHighlightPalette[3]);
    expect(colours['c1'], kHighlightPalette[4]);
  });

  test('the same defence gives everyone the same colours', () {
    final list = [note('h1', 'c1'), note('h2', 'p1')];
    expect(highlightColours(defence: defence(), annotations: list),
        highlightColours(defence: defence(), annotations: list));
  });

  test('wraps after eight', () {
    final panel = [for (var i = 0; i < 8; i++) 'p$i'];
    final colours =
        highlightColours(defence: defence(panel: panel), annotations: []);
    // a1 is 0, p0..p7 are 1..8, so p7 wraps to 0.
    expect(colours['p7'], kHighlightPalette[0]);
  });

  test('numbers follow creation order; the list follows page order', () {
    final oldestFirst = [
      note('late-page', 'p1', chapter: ChapterId.chapterII, page: 4),
      note('early-page', 'p1', chapter: ChapterId.chapterI, page: 2, y: 0.5),
      note('earliest', 'p1', chapter: ChapterId.chapterI, page: 2, y: 0.1),
    ];
    expect(highlightNumbers(oldestFirst),
        {'late-page': 1, 'early-page': 2, 'earliest': 3});
    expect(inPageOrder(oldestFirst).map((a) => a.id),
        ['earliest', 'early-page', 'late-page']);
  });

  test('the legend lists who has highlighted, in colour order', () {
    final list = [
      note('h1', 'c1', name: 'Coordinator'),
      note('h2', 'p1', name: 'Dr. Panel'),
    ];
    final colours = highlightColours(defence: defence(), annotations: list);
    final legend = highlightLegend(list, colours);
    expect(legend.map((a) => a.name), ['Dr. Panel', 'Coordinator']);
    expect(legend.first.colour, kHighlightPalette[1]);
  });

  testWidgets('a tag shows its number', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: HighlightTag(number: 7, colour: Color(0xFF0072B2))));
    expect(find.text('7'), findsOneWidget);
  });
}
