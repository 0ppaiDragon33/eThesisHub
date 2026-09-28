import 'dart:math' as math;
import 'dart:ui';

import 'package:ethesishub/data/models/chapter.dart';

/// The longest comment a highlight may carry. The same number is in
/// `firestore.rules`, which cannot import Dart.
const kAnnotationMaxLength = 2000;

/// A box on a page, as fractions 0–1 of the page's width and height, so it
/// lands on the same passage at any zoom or screen size.
class NormRect {
  const NormRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  /// The smallest side worth keeping. A tap or a slip of the finger draws
  /// something narrower than this.
  static const minSide = 0.01;

  /// The box between two points dragged on a page of [page] size, clipped
  /// to the page and rounded to four places.
  factory NormRect.fromDrag(Offset a, Offset b, Size page) {
    double fx(double v) => (v / page.width).clamp(0.0, 1.0);
    double fy(double v) => (v / page.height).clamp(0.0, 1.0);
    final left = _round(fx(math.min(a.dx, b.dx)));
    final right = _round(fx(math.max(a.dx, b.dx)));
    final top = _round(fy(math.min(a.dy, b.dy)));
    final bottom = _round(fy(math.max(a.dy, b.dy)));
    return NormRect(
      x: left,
      y: top,
      w: _round(right - left),
      h: _round(bottom - top),
    );
  }

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;

  /// Mirrors the rules' `validRect`, including its hair of slack at the edge.
  bool get isValid =>
      x >= 0 &&
      y >= 0 &&
      w > 0 &&
      h > 0 &&
      x + w <= 1.001 &&
      y + h <= 1.001;

  bool get isBigEnough => w >= minSide && h >= minSide;

  Rect toRect(Size page) => Rect.fromLTWH(
      x * page.width, y * page.height, w * page.width, h * page.height);

  Map<String, double> toMap() => {'x': x, 'y': y, 'w': w, 'h': h};

  static NormRect? fromMap(Object? raw) {
    if (raw is! Map) return null;
    double? n(Object? v) => v is num ? v.toDouble() : null;
    final x = n(raw['x']);
    final y = n(raw['y']);
    final w = n(raw['w']);
    final h = n(raw['h']);
    if (x == null || y == null || w == null || h == null) return null;
    return NormRect(x: x, y: y, w: w, h: h);
  }

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'NormRect($x, $y, $w, $h)';
}

/// One highlight on the defence manuscript: a box on one page of one
/// chapter version, with a comment. Append-only, like the room comments;
/// its author may delete it while the defence is open.
///
/// `authorPosition` is stored, not derived, for the reason [DefenceComment]
/// gives: the position held at this defence must not change later.
class DefenceAnnotation {
  const DefenceAnnotation({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.authorPosition,
    required this.chapter,
    required this.version,
    required this.page,
    required this.rect,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String authorUid;
  final String authorName;
  final String authorPosition;
  final ChapterId chapter;

  /// The chapter version the box was drawn on. A chapter reopened and
  /// re-approved later has a new version, and the box no longer fits it.
  final int version;

  /// 0-based, within that chapter's own file.
  final int page;
  final NormRect rect;
  final String body;
  final DateTime? createdAt;

  /// Null for a record this build cannot place (an unknown chapter, a
  /// malformed box), so one bad document hides itself instead of breaking
  /// the whole list.
  static DefenceAnnotation? fromMap(String id, Map<String, dynamic> map) {
    final chapter = ChapterId.fromString(map['chapter'] as String?);
    final rect = NormRect.fromMap(map['rect']);
    final version = (map['version'] as num?)?.toInt();
    final page = (map['page'] as num?)?.toInt();
    if (chapter == null || rect == null || version == null || page == null) {
      return null;
    }
    return DefenceAnnotation(
      id: id,
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorPosition: map['authorPosition'] as String? ?? '',
      chapter: chapter,
      version: version,
      page: page,
      rect: rect,
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
