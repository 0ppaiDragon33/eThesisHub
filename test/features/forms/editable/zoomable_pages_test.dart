import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/forms/editable/zoomable_pages.dart';

/// A stand-in rasteriser: two A4-shaped pages per render, counting renders.
/// Hands out clones of one image, because the viewer disposes the pages it
/// replaces.
class FakeRasterizer {
  FakeRasterizer(this.page);

  final ui.Image page;
  int renders = 0;

  Future<List<ui.Image>> call(Uint8List pdf) async {
    renders++;
    return [page.clone(), page.clone()];
  }
}

/// An A4-shaped page image. Test images decode on the real event loop.
Future<ui.Image> a4Page(WidgetTester tester) async =>
    (await tester.runAsync(() => createTestImage(width: 210, height: 297)))!;

Future<Uint8List> emptyPdf() async => Uint8List(0);

double scaleOf(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byKey(const Key('previewPages')))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

Offset translationOf(WidgetTester tester) {
  final t = tester
      .widget<InteractiveViewer>(find.byKey(const Key('previewPages')))
      .transformationController!
      .value
      .getTranslation();
  return Offset(t.x, t.y);
}

Future<void> pumpPages(
  WidgetTester tester,
  FakeRasterizer raster,
  Future<Uint8List> Function() build,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: ZoomablePages(build: build, rasterize: raster.call),
        ),
      ),
    ),
  );
  // Test images decode on the real event loop.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

void main() {
  testWidgets('shows the pages once they are drawn', (tester) async {
    final raster = FakeRasterizer(await a4Page(tester));
    await pumpPages(tester, raster, emptyPdf);

    expect(find.byType(RawImage), findsNWidgets(2));
    expect(scaleOf(tester), 1);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('the buttons zoom in, out and back to fit', (tester) async {
    final raster = FakeRasterizer(await a4Page(tester));
    await pumpPages(tester, raster, emptyPdf);

    IconButton button(String key) =>
        tester.widget<IconButton>(find.byKey(Key(key)));
    expect(
      button('previewZoomOut').onPressed,
      isNull,
      reason: 'already at the fit width',
    );

    await tester.tap(find.byKey(const Key('previewZoomIn')));
    await tester.pump();
    expect(scaleOf(tester), closeTo(1.5, 1e-9));
    expect(find.text('150%'), findsOneWidget);
    expect(button('previewZoomOut').onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('previewZoomIn')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('previewZoomOut')));
    await tester.pump();
    expect(scaleOf(tester), closeTo(1.5, 1e-9));

    await tester.tap(find.byKey(const Key('previewZoomFit')));
    await tester.pump();
    expect(scaleOf(tester), 1);
    expect(translationOf(tester), Offset.zero);
  });

  testWidgets('zooming never shows empty space past the pages', (tester) async {
    final raster = FakeRasterizer(await a4Page(tester));
    await pumpPages(tester, raster, emptyPdf);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('previewZoomIn')));
      await tester.pump();
    }
    expect(scaleOf(tester), ZoomablePages.maxScale);
    final t = translationOf(tester);
    expect(t.dx, lessThanOrEqualTo(0));
    expect(t.dy, lessThanOrEqualTo(0));
    // The zoomed pages still cover the right edge of the viewport.
    expect(t.dx + 400 * ZoomablePages.maxScale, greaterThanOrEqualTo(400));
  });

  testWidgets('a re-render keeps the zoom and the part in view', (
    tester,
  ) async {
    final raster = FakeRasterizer(await a4Page(tester));
    await pumpPages(tester, raster, emptyPdf);

    await tester.tap(find.byKey(const Key('previewZoomIn')));
    await tester.pump();
    final before = translationOf(tester);

    // The editor hands over a new build function after an edit.
    Future<Uint8List> edited() async => Uint8List(1);
    await pumpPages(tester, raster, edited);

    expect(raster.renders, 2);
    expect(scaleOf(tester), closeTo(1.5, 1e-9));
    expect(translationOf(tester), before);
  });

  testWidgets('a render that fails says so', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ZoomablePages(
            build: () async => throw StateError('no fonts'),
            rasterize: FakeRasterizer(await a4Page(tester)).call,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('previewError')), findsOneWidget);
  });

  testWidgets('a slow render that finishes late is dropped', (tester) async {
    final slow = Completer<Uint8List>();
    final raster = FakeRasterizer(await a4Page(tester));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ZoomablePages(
              build: () => slow.future,
              rasterize: raster.call,
            ),
          ),
        ),
      ),
    );
    await pumpPages(tester, raster, emptyPdf);
    expect(raster.renders, 1);

    slow.complete(Uint8List(2));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(raster.renders, 1, reason: 'the stale build is never rasterised');
  });
}
