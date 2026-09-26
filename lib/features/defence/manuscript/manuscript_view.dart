import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';

/// A box the reader has just drawn, before it has a comment.
class DrawnHighlight {
  const DrawnHighlight({
    required this.chapter,
    required this.version,
    required this.page,
    required this.rect,
  });

  final ChapterId chapter;
  final int version;
  final int page;
  final NormRect rect;
}

/// Lets a screen scroll the manuscript to a highlight.
class ManuscriptController extends ChangeNotifier {
  DefenceAnnotation? _target;

  DefenceAnnotation? get target => _target;

  void reveal(DefenceAnnotation a) {
    _target = a;
    notifyListeners();
  }
}

/// The defence manuscript: each chapter's pages one after another, drawn a
/// page at a time as they scroll into view and released when far away, so a
/// long thesis is never held in a phone's memory whole.
class ManuscriptView extends ConsumerStatefulWidget {
  const ManuscriptView({
    super.key,
    required this.parts,
    this.annotations = const [],
    this.colours = const {},
    this.numbers = const {},
    this.canHighlight = false,
    this.highlightClosedReason,
    this.onHighlightDrawn,
    this.onOpenFile,
    this.controller,
  });

  final List<ManuscriptPart> parts;
  final List<DefenceAnnotation> annotations;

  /// By author uid; see [highlightColours].
  final Map<String, Color> colours;

  /// By annotation id; see [highlightNumbers].
  final Map<String, int> numbers;

  /// Whether the Highlight tool is offered at all.
  final bool canHighlight;

  /// Shown where the tool would be, when it is not offered yet.
  final String? highlightClosedReason;
  final void Function(DrawnHighlight)? onHighlightDrawn;
  final void Function(ChapterVersion)? onOpenFile;
  final ManuscriptController? controller;

  static const double headerExtent = 44;
  static const double reopenedExtent = 56;
  static const double noteExtent = 168;

  /// Taller: it carries the reason and a Try again button.
  static const double failedExtent = 208;
  static const double loadingExtent = 240;
  static const double pageGap = 12;
  static const zoomSteps = [1.0, 1.5, 2.0, 3.0];

  @override
  ConsumerState<ManuscriptView> createState() => _ManuscriptViewState();
}

sealed class _Item {
  const _Item(this.part);
  final ManuscriptPart part;
}

class _Header extends _Item {
  const _Header(super.part);
}

/// Above a reopened chapter's pages: why an unapproved chapter shows them.
class _Reopened extends _Item {
  const _Reopened(super.part);
}

class _Page extends _Item {
  const _Page(super.part, this.pdf, this.index);
  final ChapterPdf pdf;
  final int index;
}

enum _NoteKind { loading, failed, notApproved, notPdf, missing }

class _Note extends _Item {
  const _Note(super.part, this.kind, [this.error]);
  final _NoteKind kind;
  final Object? error;
}

class _ManuscriptViewState extends ConsumerState<ManuscriptView> {
  final _scroll = ScrollController();
  int _zoomIndex = 0;
  bool _tool = false;
  String? _pulseId;
  Timer? _pulseTimer;
  List<_Item> _items = const [];
  double _width = 0;

  double get _zoom => ManuscriptView.zoomSteps[_zoomIndex];

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onReveal);
  }

  @override
  void didUpdateWidget(covariant ManuscriptView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onReveal);
      widget.controller?.addListener(_onReveal);
    }
    if (!widget.canHighlight) _tool = false;
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onReveal);
    _pulseTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<_Item> _buildItems() {
    final items = <_Item>[];
    for (final part in widget.parts) {
      items.add(_Header(part));
      if (part.reopened) items.add(_Reopened(part));
      switch (part.kind) {
        case ManuscriptPartKind.pdf:
          ref.watch(chapterPdfProvider(part.version!.storagePath)).when(
                data: (pdf) {
                  for (var i = 0; i < pdf.pageSizes.length; i++) {
                    items.add(_Page(part, pdf, i));
                  }
                },
                loading: () => items.add(_Note(part, _NoteKind.loading)),
                error: (e, _) => items.add(_Note(part, _NoteKind.failed, e)),
              );
        case ManuscriptPartKind.notApproved:
          items.add(_Note(part, _NoteKind.notApproved));
        case ManuscriptPartKind.notPdf:
          items.add(_Note(part, _NoteKind.notPdf));
        case ManuscriptPartKind.missing:
          items.add(_Note(part, _NoteKind.missing));
      }
    }
    return items;
  }

  double _extentOf(_Item item, double width) => switch (item) {
        _Header() => ManuscriptView.headerExtent,
        _Reopened() => ManuscriptView.reopenedExtent,
        _Page(:final pdf, :final index) => width *
                pdf.pageSizes[index].height /
                pdf.pageSizes[index].width +
            ManuscriptView.pageGap,
        _Note(kind: _NoteKind.loading) => ManuscriptView.loadingExtent,
        _Note(kind: _NoteKind.failed) => ManuscriptView.failedExtent,
        _Note() => ManuscriptView.noteExtent,
      };

  void _onReveal() {
    final a = widget.controller?.target;
    if (a == null || !_scroll.hasClients) return;
    var offset = 0.0;
    for (final item in _items) {
      if (item is _Page &&
          item.part.chapter == a.chapter &&
          item.part.version?.version == a.version &&
          item.index == a.page) {
        final pageHeight = _extentOf(item, _width) - ManuscriptView.pageGap;
        // The Sliver's own maxScrollExtent is only an estimate until every
        // item between here and there has been laid out once, which a lazy
        // list has not done for a page far below the fold. animateTo clamps
        // each tick to that stale estimate, so it can never reach — let
        // alone discover — a target past it. The total is fully known
        // already from [_items] and [_width], so it is computed directly
        // and jumpTo (which does not clamp) is used instead of an animation.
        final totalExtent = _items.fold(
            0.0, (sum, it) => sum + _extentOf(it, _width));
        final maxScroll = (totalExtent - _scroll.position.viewportDimension)
            .clamp(0.0, double.infinity);
        final to =
            (offset + a.rect.y * pageHeight - 48).clamp(0.0, maxScroll);
        _scroll.jumpTo(to);
        setState(() => _pulseId = a.id);
        _pulseTimer?.cancel();
        _pulseTimer = Timer(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _pulseId = null);
        });
        return;
      }
      offset += _extentOf(item, _width);
    }
  }

  void _setZoom(int index) {
    final old = _zoom;
    final at = _scroll.hasClients ? _scroll.offset : 0.0;
    setState(() => _zoomIndex = index);
    final ratio = _zoom / old;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(
          (at * ratio).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  void _drawn(DrawnHighlight d) {
    setState(() => _tool = false);
    widget.onHighlightDrawn?.call(d);
  }

  @override
  Widget build(BuildContext context) {
    _items = _buildItems();
    final text = Theme.of(context).textTheme;

    final toolbar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          if (widget.canHighlight)
            Flexible(
              child: _tool
                  ? FilledButton.icon(
                      key: const Key('highlightTool'),
                      onPressed: () => setState(() => _tool = false),
                      icon: const Icon(Icons.highlight_alt, size: 18),
                      label: const Text('Drag over a passage',
                          overflow: TextOverflow.ellipsis),
                    )
                  : OutlinedButton.icon(
                      key: const Key('highlightTool'),
                      onPressed: () => setState(() => _tool = true),
                      icon: const Icon(Icons.highlight_alt, size: 18),
                      label: const Text('Highlight'),
                    ),
            )
          else if (widget.highlightClosedReason != null)
            Flexible(
              child: Text(
                widget.highlightClosedReason!,
                key: const Key('highlightClosed'),
                style: text.bodySmall,
              ),
            ),
          const Spacer(),
          IconButton(
            key: const Key('manuscriptZoomOut'),
            tooltip: 'Zoom out',
            onPressed: _zoomIndex > 0 ? () => _setZoom(_zoomIndex - 1) : null,
            icon: const Icon(Icons.zoom_out),
          ),
          Text('${(_zoom * 100).round()}%',
              key: const Key('manuscriptZoomLevel'), style: text.labelMedium),
          IconButton(
            key: const Key('manuscriptZoomIn'),
            tooltip: 'Zoom in',
            onPressed: _zoomIndex < ManuscriptView.zoomSteps.length - 1
                ? () => _setZoom(_zoomIndex + 1)
                : null,
            icon: const Icon(Icons.zoom_in),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        toolbar,
        const Divider(height: 1),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF3A3F47),
            child: LayoutBuilder(builder: (context, constraints) {
              final width = (constraints.maxWidth - 24) * _zoom;
              _width = width;
              final locked = _tool;
              final list = SizedBox(
                width: width + 24,
                child: ListView.builder(
                  key: const Key('manuscriptPages'),
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  physics:
                      locked ? const NeverScrollableScrollPhysics() : null,
                  itemCount: _items.length,
                  itemExtentBuilder: (i, _) =>
                      i < _items.length ? _extentOf(_items[i], width) : null,
                  itemBuilder: (context, i) => _buildItem(_items[i], width),
                ),
              );
              if (_zoomIndex == 0) return list;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                child: list,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildItem(_Item item, double width) {
    final part = item.part;
    final numeral = chapterNumeral(part.chapter);
    final id = part.chapter.name;
    switch (item) {
      case _Header():
        return Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              part.chapter.label.toUpperCase(),
              key: Key('chapterHeader-$id'),
              style: const TextStyle(
                  color: Color(0xFFB8C4CF),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6),
            ),
          ),
        );
      case _Reopened():
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            key: Key('chapterReopened-$id'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF4A5059),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              'Chapter $numeral has been reopened for revision. Showing the '
              'version the panel marked.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFE3E8ED), fontSize: 12),
            ),
          ),
        );
      case _Page(:final pdf, :final index):
        return _PageTile(
          key: Key('pageTile-$id-${part.version!.version}-$index'),
          part: part,
          pdf: pdf,
          index: index,
          width: width,
          annotations: [
            for (final a in widget.annotations)
              if (a.chapter == part.chapter &&
                  a.version == part.version!.version &&
                  a.page == index)
                a,
          ],
          colours: widget.colours,
          numbers: widget.numbers,
          pulseId: _pulseId,
          drawing: _tool,
          onDrawn: _drawn,
        );
      case _Note(:final kind, :final error):
        return _NoteTile(
          key: Key(switch (kind) {
            _NoteKind.loading => 'chapterLoading-$id',
            _NoteKind.failed => 'chapterFailed-$id',
            _NoteKind.notApproved => 'chapterNotApproved-$id',
            _NoteKind.notPdf => 'chapterNotPdf-$id',
            _NoteKind.missing => 'chapterMissing-$id',
          }),
          loading: kind == _NoteKind.loading,
          message: switch (kind) {
            _NoteKind.loading => 'Loading Chapter $numeral…',
            _NoteKind.failed => 'Chapter $numeral could not be loaded.'
                '${error is StorageFailure ? ' ${error.message}' : ''}',
            _NoteKind.notApproved => 'Chapter $numeral is not approved yet.',
            _NoteKind.notPdf => 'Chapter $numeral was uploaded as a Word '
                "file and can't be shown here.",
            _NoteKind.missing => 'Chapter $numeral has not been uploaded.',
          },
          action: switch (kind) {
            _NoteKind.notPdf when widget.onOpenFile != null =>
              OutlinedButton.icon(
                key: Key('openChapterFile-$id'),
                onPressed: () => widget.onOpenFile!(part.version!),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open file'),
              ),
            // A fresh download: the provider is keyed by the path, so
            // invalidating it fetches the file again.
            _NoteKind.failed => OutlinedButton.icon(
                key: Key('retryChapter-$id'),
                onPressed: () => ref
                    .invalidate(chapterPdfProvider(part.version!.storagePath)),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try again'),
              ),
            _ => null,
          },
        );
    }
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    super.key,
    required this.message,
    this.loading = false,
    this.action,
  });

  final String message;
  final bool loading;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ManuscriptView.pageGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading) ...[
                  const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(height: 12),
                ],
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black87)),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageTile extends ConsumerStatefulWidget {
  const _PageTile({
    super.key,
    required this.part,
    required this.pdf,
    required this.index,
    required this.width,
    required this.annotations,
    required this.colours,
    required this.numbers,
    required this.pulseId,
    required this.drawing,
    required this.onDrawn,
  });

  final ManuscriptPart part;
  final ChapterPdf pdf;
  final int index;
  final double width;
  final List<DefenceAnnotation> annotations;
  final Map<String, Color> colours;
  final Map<String, int> numbers;
  final String? pulseId;
  final bool drawing;
  final void Function(DrawnHighlight) onDrawn;

  @override
  ConsumerState<_PageTile> createState() => _PageTileState();
}

class _PageTileState extends ConsumerState<_PageTile> {
  ui.Image? _image;
  Object? _error;
  Offset? _start;
  Offset? _end;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    try {
      final image = await ref
          .read(manuscriptRasterizerProvider)
          .renderPage(widget.pdf.bytes, widget.index);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Widget _box(DefenceAnnotation a, Size page) {
    final colour = widget.colours[a.authorUid] ?? kHighlightPalette.last;
    final number = widget.numbers[a.id];
    return Positioned.fromRect(
      rect: a.rect.toRect(page),
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                key: Key('highlightBox-${a.id}'),
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.28),
                  border: Border.all(
                      color: colour, width: widget.pulseId == a.id ? 3 : 1.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (number != null)
              Positioned(
                top: -10,
                right: -10,
                child: HighlightTag(number: number, colour: colour),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shape = widget.pdf.pageSizes[widget.index];
    final height = widget.width * shape.height / shape.width;
    final pageSize = Size(widget.width, height);
    final chapterId = widget.part.chapter.name;

    Widget page = Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2), blurRadius: 4),
              ],
            ),
            child: _image != null
                ? RawImage(image: _image, fit: BoxFit.fill)
                : Center(
                    child: _error != null
                        ? const Text('This page could not be drawn.',
                            style: TextStyle(color: Colors.black54))
                        : const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
          ),
        ),
        for (final a in widget.annotations) _box(a, pageSize),
        if (_start != null && _end != null)
          Positioned.fromRect(
            rect: Rect.fromPoints(_start!, _end!),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.blue, width: 1.5),
                ),
              ),
            ),
          ),
        Positioned(
          right: 6,
          bottom: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Ch. ${chapterNumeral(widget.part.chapter)} · '
                'p. ${widget.index + 1}',
                style: const TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.drawing) {
      page = GestureDetector(
        key: Key('drawSurface-$chapterId-${widget.index}'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (d) => setState(() {
          _start = d.localPosition;
          _end = d.localPosition;
        }),
        onPanUpdate: (d) => setState(() => _end = d.localPosition),
        onPanEnd: (_) {
          final start = _start;
          final end = _end;
          setState(() {
            _start = null;
            _end = null;
          });
          if (start == null || end == null) return;
          final rect = NormRect.fromDrag(start, end, pageSize);
          if (!rect.isBigEnough) return;
          widget.onDrawn(DrawnHighlight(
            chapter: widget.part.chapter,
            version: widget.part.version!.version,
            page: widget.index,
            rect: rect,
          ));
        },
        onPanCancel: () => setState(() {
          _start = null;
          _end = null;
        }),
        child: page,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: ManuscriptView.pageGap),
      child: SizedBox(width: widget.width, height: height, child: page),
    );
  }
}
