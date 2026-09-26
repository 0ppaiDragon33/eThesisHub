import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';

class FakeRasterizer implements ManuscriptRasterizer {
  FakeRasterizer(this.image, {this.pages = 2});
  final ui.Image image;
  final int pages;
  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async =>
      List.filled(pages, const Size(210, 297));
  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) async => image.clone();
}

ChapterVersion v(int n, {String path = 'theses/t1/chapterI/a.pdf',
        String mime = 'application/pdf'}) =>
    ChapterVersion(
      version: n,
      storagePath: path,
      fileUrl: '',
      uploadedBy: 'l1',
      mimeType: mime,
      sizeBytes: 4,
    );

DefenceAnnotation note(String id,
        {int version = 2, int page = 0, double y = 0.1}) =>
    DefenceAnnotation(
      id: id,
      authorUid: 'p1',
      authorName: 'Dr. Panel',
      authorPosition: 'Panel Member',
      chapter: ChapterId.chapterI,
      version: version,
      page: page,
      rect: NormRect(x: 0.1, y: y, w: 0.5, h: 0.05),
      body: 'b',
    );

final pdfPart = ManuscriptPart(
    chapter: ChapterId.chapterI, kind: ManuscriptPartKind.pdf, version: v(2));

Future<ui.Image> page(WidgetTester tester) async =>
    (await tester.runAsync(() => createTestImage(width: 210, height: 297)))!;

Future<void> pumpView(
  WidgetTester tester,
  Widget view, {
  required ui.Image image,
  int pages = 2,
  ChapterFileLoader? loader,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      chapterFileLoaderProvider
          .overrideWithValue(loader ?? (path) async => Uint8List(4)),
      manuscriptRasterizerProvider
          .overrideWithValue(FakeRasterizer(image, pages: pages)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 400, height: 600, child: view)),
    ),
  ));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('shows each chapter: pages, or a placeholder saying why',
      (tester) async {
    ChapterVersion? opened;
    await pumpView(
      tester,
      ManuscriptView(
        parts: [
          pdfPart,
          const ManuscriptPart(
              chapter: ChapterId.chapterII,
              kind: ManuscriptPartKind.notApproved),
          ManuscriptPart(
              chapter: ChapterId.chapterIII,
              kind: ManuscriptPartKind.notPdf,
              version: v(1, path: 'x.docx', mime: 'application/msword')),
        ],
        onOpenFile: (version) => opened = version,
      ),
      image: await page(tester),
    );

    expect(find.byKey(const Key('chapterHeader-chapterI')), findsOneWidget);
    expect(find.byKey(const Key('drawSurface-chapterI-0')), findsNothing,
        reason: 'no drawing surface unless the tool is on');
    expect(find.text('Ch. I · p. 1'), findsOneWidget);

    await tester.scrollUntilVisible(
        find.byKey(const Key('chapterNotPdf-chapterIII')), 300,
        scrollable: find.descendant(
            of: find.byKey(const Key('manuscriptPages')),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(find.text('Chapter II is not approved yet.'), findsOneWidget);
    expect(
        find.text(
            "Chapter III was uploaded as a Word file and can't be shown here."),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('openChapterFile-chapterIII')));
    expect(opened?.storagePath, 'x.docx');
  });

  testWidgets('a missing chapter says so', (tester) async {
    await pumpView(
      tester,
      const ManuscriptView(parts: [
        ManuscriptPart(
            chapter: ChapterId.chapterIV, kind: ManuscriptPartKind.missing),
      ]),
      image: await page(tester),
    );
    expect(find.text('Chapter IV has not been uploaded.'), findsOneWidget);
  });

  testWidgets('a chapter that fails to load says so and the rest still show',
      (tester) async {
    await pumpView(
      tester,
      ManuscriptView(parts: [
        pdfPart,
        const ManuscriptPart(
            chapter: ChapterId.chapterII,
            kind: ManuscriptPartKind.notApproved),
      ]),
      image: await page(tester),
      loader: (path) async =>
          throw const StorageFailure('Could not download this chapter.',
              code: 'storage-download'),
    );
    expect(find.byKey(const Key('chapterFailed-chapterI')), findsOneWidget);
    expect(find.textContaining('Could not download this chapter.'),
        findsOneWidget);
    expect(find.text('Chapter II is not approved yet.'), findsOneWidget);
  });

  testWidgets('draws a box only on its own page and version', (tester) async {
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        annotations: [note('current'), note('old', version: 1)],
        numbers: const {'current': 1, 'old': 2},
      ),
      image: await page(tester),
    );
    expect(find.byKey(const Key('highlightBox-current')), findsOneWidget);
    expect(find.byKey(const Key('highlightBox-old')), findsNothing);
  });

  testWidgets('the tool is hidden when closed, with the reason',
      (tester) async {
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        highlightClosedReason: 'Highlighting opens when the defence starts.',
      ),
      image: await page(tester),
    );
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.text('Highlighting opens when the defence starts.'),
        findsOneWidget);
  });

  testWidgets('dragging with the tool on reports the box, then turns it off',
      (tester) async {
    DrawnHighlight? drawn;
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        canHighlight: true,
        onHighlightDrawn: (d) => drawn = d,
      ),
      image: await page(tester),
    );
    await tester.tap(find.byKey(const Key('highlightTool')));
    await tester.pump();

    final surface = find.byKey(const Key('drawSurface-chapterI-0'));
    final origin = tester.getTopLeft(surface);
    await tester.dragFrom(origin + const Offset(40, 50), const Offset(200, 30));
    await tester.pump();

    expect(drawn, isNotNull);
    expect(drawn!.chapter, ChapterId.chapterI);
    expect(drawn!.version, 2);
    expect(drawn!.page, 0);
    // The page is 376 wide (400 less the list's 12 + 12 padding), and the
    // drag starts where the finger went down: x 40/376, w 200/376.
    expect(drawn!.rect.x, closeTo(40 / 376, 0.01));
    expect(drawn!.rect.w, closeTo(200 / 376, 0.01));
    expect(find.byKey(const Key('drawSurface-chapterI-0')), findsNothing);
  });

  testWidgets('a tap with the tool on draws nothing', (tester) async {
    DrawnHighlight? drawn;
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        canHighlight: true,
        onHighlightDrawn: (d) => drawn = d,
      ),
      image: await page(tester),
    );
    await tester.tap(find.byKey(const Key('highlightTool')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('drawSurface-chapterI-0')));
    await tester.pump();
    expect(drawn, isNull);
  });

  testWidgets('zoom widens the pages', (tester) async {
    await pumpView(tester, ManuscriptView(parts: [pdfPart]),
        image: await page(tester));
    final before =
        tester.getSize(find.byKey(const Key('pageTile-chapterI-2-0'))).width;
    await tester.tap(find.byKey(const Key('manuscriptZoomIn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('150%'), findsOneWidget);
    final after =
        tester.getSize(find.byKey(const Key('pageTile-chapterI-2-0'))).width;
    expect(after, closeTo(before * 1.5, 1));
  });

  testWidgets('reveal scrolls to a highlight and marks it', (tester) async {
    final controller = ManuscriptController();
    addTearDown(controller.dispose);
    await pumpView(
      tester,
      ManuscriptView(
        parts: [pdfPart],
        annotations: [note('far', page: 5, y: 0.5)],
        numbers: const {'far': 1},
        controller: controller,
      ),
      image: await page(tester),
      pages: 6,
    );
    controller.reveal(note('far', page: 5, y: 0.5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byKey(const Key('manuscriptPages')),
        matching: find.byType(Scrollable)));
    expect(scrollable.position.pixels, greaterThan(2000));
    final box = tester.widget<DecoratedBox>(
        find.byKey(const Key('highlightBox-far')));
    expect((box.decoration as BoxDecoration).border!.top.width, 3);
  });
}
