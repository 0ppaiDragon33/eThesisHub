import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/highlights_panel.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';

DefenceAnnotation note(String id, String uid,
        {int page = 0, int version = 2, String body = 'b'}) =>
    DefenceAnnotation(
      id: id,
      authorUid: uid,
      authorName: uid == 'p1' ? 'Dr. Panel' : 'Dr. Adviser',
      authorPosition: uid == 'p1' ? 'Panel Member' : 'Adviser',
      chapter: ChapterId.chapterI,
      version: version,
      page: page,
      rect: const NormRect(x: 0, y: 0, w: 0.5, h: 0.1),
      body: body,
    );

final parts = [
  ManuscriptPart(
    chapter: ChapterId.chapterI,
    kind: ManuscriptPartKind.pdf,
    version: const ChapterVersion(
        version: 2,
        storagePath: 'a.pdf',
        fileUrl: '',
        uploadedBy: 'l1',
        mimeType: 'application/pdf',
        sizeBytes: 4),
  ),
];

Future<void> pumpList(WidgetTester tester, List<DefenceAnnotation> list,
    {bool canDelete = true,
    void Function(DefenceAnnotation)? onSelect,
    void Function(DefenceAnnotation)? onDelete}) {
  return tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HighlightsList(
          annotations: list,
          parts: parts,
          colours: const {'a1': Color(0xFFE69F00), 'p1': Color(0xFF56B4E9)},
          numbers: highlightNumbers(list),
          myUid: 'p1',
          canDelete: canDelete,
          onSelect: onSelect,
          onDelete: onDelete,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('nothing yet', (tester) async {
    await pumpList(tester, []);
    expect(find.byKey(const Key('highlightsEmpty')), findsOneWidget);
  });

  testWidgets('lists in page order, numbered by creation, with a legend',
      (tester) async {
    await pumpList(tester, [
      note('h1', 'a1', page: 4, body: 'later page'),
      note('h2', 'p1', page: 1, body: 'earlier page'),
    ]);
    final rows = tester
        .widgetList<InkWell>(find.byWidgetPredicate((w) =>
            w is InkWell &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('highlightRow-')))
        .map((w) => (w.key! as ValueKey<String>).value)
        .toList();
    expect(rows, ['highlightRow-h2', 'highlightRow-h1']);
    expect(find.text('Dr. Panel, Panel Member · Ch. I p. 2'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('highlightLegend')),
            matching: find.text('Dr. Adviser')),
        findsOneWidget);
  });

  testWidgets('marks a highlight on an earlier version', (tester) async {
    await pumpList(tester, [note('old', 'p1', version: 1)]);
    expect(find.text('On an earlier version of Chapter I'), findsOneWidget);
  });

  testWidgets('delete is offered only on your own, and only when allowed',
      (tester) async {
    DefenceAnnotation? deleted;
    await pumpList(tester, [note('mine', 'p1'), note('theirs', 'a1')],
        onDelete: (a) => deleted = a);
    expect(find.byKey(const Key('deleteHighlight-theirs')), findsNothing);
    await tester.tap(find.byKey(const Key('deleteHighlight-mine')));
    expect(deleted?.id, 'mine');

    await pumpList(tester, [note('mine', 'p1')], canDelete: false);
    expect(find.byKey(const Key('deleteHighlight-mine')), findsNothing);
  });

  testWidgets('tapping a row selects it', (tester) async {
    DefenceAnnotation? selected;
    await pumpList(tester, [note('h1', 'p1')], onSelect: (a) => selected = a);
    await tester.tap(find.byKey(const Key('highlightRow-h1')));
    expect(selected?.id, 'h1');
  });

  testWidgets('the comment dialog returns the text and reports typing',
      (tester) async {
    final typing = <bool>[];
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showHighlightComposer(context,
                  onTyping: typing.add);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final save = find.byKey(const Key('saveHighlight'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
        find.byKey(const Key('highlightBody')), '  Cite the data.  ');
    await tester.pump();
    expect(typing, [true]);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(result, 'Cite the data.');
    expect(typing, [true, false]);
  });

  testWidgets('cancelling the dialog returns nothing', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                result = await showHighlightComposer(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelHighlight')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
