import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Turns a PDF into one image per page.
typedef PdfRasterizer = Future<List<ui.Image>> Function(Uint8List pdf);

/// Page images sharp enough to read at the viewer's full zoom without
/// costing a phone too much memory (an A4 page is about 1490 × 2100 px).
const double kPreviewDpi = 180;

Future<List<ui.Image>> rasterizePdf(Uint8List pdf) async {
  final pages = <ui.Image>[];
  await for (final page in Printing.raster(pdf, dpi: kPreviewDpi)) {
    pages.add(await page.toImage());
  }
  return pages;
}

/// The printed form's pages, stacked at the width of the viewer, that the
/// reader can pinch to zoom and drag around, with buttons for the same.
///
/// A new [build] re-renders the pages in place: the zoom and the part of the
/// page in view stay where the reader left them, so editing a line near the
/// bottom of the form does not throw the preview back to the top.
class ZoomablePages extends StatefulWidget {
  const ZoomablePages({
    super.key,
    required this.build,
    this.rasterize = rasterizePdf,
  });

  final Future<Uint8List> Function() build;
  final PdfRasterizer rasterize;

  static const double minScale = 1;
  static const double maxScale = 5;

  /// How far one press of the zoom buttons goes.
  static const double step = 1.5;

  @override
  State<ZoomablePages> createState() => _ZoomablePagesState();
}

class _ZoomablePagesState extends State<ZoomablePages> {
  final _transform = TransformationController();
  List<ui.Image> _pages = const [];
  Object? _error;
  bool _rendering = false;

  /// Bumped per render, so a slow render that finishes after a newer one
  /// started is dropped instead of replacing the newer pages.
  int _generation = 0;

  /// The laid-out size of the viewport and of the stacked pages, for the
  /// zoom buttons.
  Size _viewport = Size.zero;
  Size _content = Size.zero;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _render();
  }

  @override
  void didUpdateWidget(covariant ZoomablePages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.build != widget.build) _render();
  }

  @override
  void dispose() {
    _generation++;
    _transform
      ..removeListener(_onTransform)
      ..dispose();
    for (final page in _pages) {
      page.dispose();
    }
    super.dispose();
  }

  // Redraws the zoom buttons' enabled state and the percentage.
  void _onTransform() => setState(() {});

  Future<void> _render() async {
    final generation = ++_generation;
    setState(() => _rendering = true);
    try {
      final pdf = await widget.build();
      if (!mounted || generation != _generation) return;
      final pages = await widget.rasterize(pdf);
      if (!mounted || generation != _generation) {
        for (final page in pages) {
          page.dispose();
        }
        return;
      }
      final old = _pages;
      setState(() {
        _pages = pages;
        _error = null;
        _rendering = false;
      });
      for (final page in old) {
        page.dispose();
      }
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _rendering = false;
      });
    }
  }

  double get _scale => _transform.value.getMaxScaleOnAxis();

  /// Zooms by [factor] about the middle of the viewport, keeping the pages
  /// inside it.
  void _zoomBy(double factor) {
    final current = _scale;
    final target = (current * factor).clamp(
      ZoomablePages.minScale,
      ZoomablePages.maxScale,
    );
    if (target == current) return;
    final focal = _transform.toScene(_viewport.center(Offset.zero));
    final f = target / current;
    final next = _transform.value.multiplied(
      Matrix4.translationValues(focal.dx, focal.dy, 0)
        ..multiply(Matrix4.diagonal3Values(f, f, 1))
        ..multiply(Matrix4.translationValues(-focal.dx, -focal.dy, 0)),
    );
    _transform.value = _clamped(next);
  }

  /// [m] with its translation pulled back so no empty space shows past the
  /// pages' edges.
  Matrix4 _clamped(Matrix4 m) {
    final scale = m.getMaxScaleOnAxis();
    double clampAxis(double t, double viewport, double content) {
      final min = viewport - content * scale;
      return min >= 0 ? 0 : t.clamp(min, 0);
    }

    final translation = m.getTranslation();
    return Matrix4.copy(m)..setTranslationRaw(
      clampAxis(translation.x, _viewport.width, _content.width),
      clampAxis(translation.y, _viewport.height, _content.height),
      0,
    );
  }

  void _fit() => _transform.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    if (_pages.isEmpty) {
      if (_error != null) return _PreviewError(error: _error!);
      return const Center(child: CircularProgressIndicator());
    }

    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final heights = [
          for (final page in _pages) width * page.height / page.width,
        ];
        _viewport = constraints.biggest;
        _content = Size(
          width,
          heights.fold<double>(0, (a, b) => a + b) + gap * (_pages.length - 1),
        );

        return Stack(
          children: [
            InteractiveViewer(
              key: const Key('previewPages'),
              transformationController: _transform,
              constrained: false,
              minScale: ZoomablePages.minScale,
              maxScale: ZoomablePages.maxScale,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    for (var i = 0; i < _pages.length; i++) ...[
                      if (i > 0) const SizedBox(height: gap),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: RawImage(
                          image: _pages[i],
                          width: width,
                          height: heights[i],
                          fit: BoxFit.fill,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_rendering)
              const Positioned(
                top: 8,
                left: 8,
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _ZoomControls(
                scale: _scale,
                onZoomOut: _scale > ZoomablePages.minScale
                    ? () => _zoomBy(1 / ZoomablePages.step)
                    : null,
                onZoomIn: _scale < ZoomablePages.maxScale
                    ? () => _zoomBy(ZoomablePages.step)
                    : null,
                onFit: _scale != ZoomablePages.minScale ? _fit : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.scale,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFit,
  });

  final double scale;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(24),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const Key('previewZoomOut'),
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
            icon: const Icon(Icons.zoom_out),
          ),
          Text(
            '${(scale * 100).round()}%',
            key: const Key('previewZoomLevel'),
            style: Theme.of(context).textTheme.labelMedium,
          ),
          IconButton(
            key: const Key('previewZoomIn'),
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            key: const Key('previewZoomFit'),
            tooltip: 'Fit to width',
            onPressed: onFit,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
        ],
      ),
    );
  }
}

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'The preview could not be drawn: $error',
          key: const Key('previewError'),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
