import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/models/defence_composing.dart';

void main() {
  const page = Size(400, 600);

  group('NormRect.fromDrag', () {
    test('orders the corners and scales to the page', () {
      final r = NormRect.fromDrag(
          const Offset(300, 120), const Offset(100, 60), page);
      expect(r, const NormRect(x: 0.25, y: 0.1, w: 0.5, h: 0.1));
    });

    test('a drag past the page edge is clipped to it', () {
      final r = NormRect.fromDrag(
          const Offset(40, 540), const Offset(480, 700), page);
      expect(r.x, 0.1);
      expect(r.y, 0.9);
      expect(r.x + r.w, lessThanOrEqualTo(1.001));
      expect(r.y + r.h, lessThanOrEqualTo(1.001));
      expect(r.isValid, isTrue);
    });

    test('rounds to four places', () {
      final r = NormRect.fromDrag(
          const Offset(1, 1), const Offset(101, 101), const Size(300, 300));
      // 1/300 = 0.00333… and 101/300 = 0.33666…, each rounded first.
      expect(r.x, 0.0033);
      expect(r.w, 0.3334);
    });

    test('a tap is not big enough', () {
      final r = NormRect.fromDrag(
          const Offset(100, 100), const Offset(102, 101), page);
      expect(r.isBigEnough, isFalse);
    });
  });

  test('toRect is the inverse of fromDrag', () {
    // Quarters, so the products are exact in floating point.
    const r = NormRect(x: 0.25, y: 0.25, w: 0.5, h: 0.5);
    expect(r.toRect(page), const Rect.fromLTWH(100, 150, 200, 300));
  });

  test('isValid refuses a box off the page or with no area', () {
    expect(const NormRect(x: 0.6, y: 0, w: 0.5, h: 0.1).isValid, isFalse);
    expect(const NormRect(x: 0, y: 0, w: 0, h: 0.1).isValid, isFalse);
    expect(const NormRect(x: -0.1, y: 0, w: 0.5, h: 0.1).isValid, isFalse);
  });

  test('fromMap reads ints and doubles and refuses a partial box', () {
    expect(NormRect.fromMap({'x': 0, 'y': 0.5, 'w': 1, 'h': 0.25}),
        const NormRect(x: 0, y: 0.5, w: 1, h: 0.25));
    expect(NormRect.fromMap({'x': 0, 'y': 0.5, 'w': 1}), isNull);
    expect(NormRect.fromMap('nope'), isNull);
  });

  group('DefenceAnnotation.fromMap', () {
    Map<String, dynamic> raw([Map<String, dynamic> extra = const {}]) => {
          'authorUid': 'p1',
          'authorName': 'Dr. Panel',
          'authorPosition': 'Panel Member',
          'chapter': 'chapterII',
          'version': 2,
          'page': 3,
          'rect': {'x': 0.1, 'y': 0.2, 'w': 0.5, 'h': 0.05},
          'body': 'Cite it.',
          ...extra,
        };

    test('reads every field', () {
      final a = DefenceAnnotation.fromMap('h1', raw())!;
      expect(a.id, 'h1');
      expect(a.chapter, ChapterId.chapterII);
      expect(a.version, 2);
      expect(a.page, 3);
      expect(a.rect, const NormRect(x: 0.1, y: 0.2, w: 0.5, h: 0.05));
      expect(a.body, 'Cite it.');
    });

    test('is null for a record it cannot place', () {
      expect(DefenceAnnotation.fromMap('h1', raw({'chapter': 'chapterVI'})),
          isNull);
      expect(DefenceAnnotation.fromMap('h1', raw({'rect': null})), isNull);
      expect(DefenceAnnotation.fromMap('h1', raw({'page': null})), isNull);
    });
  });

  test('a composing marker is stale after 15 seconds', () {
    final at = DateTime(2026, 9, 26, 9);
    final m = DefenceComposing.fromMap('p1', {
      'name': 'Dr. Panel',
      'position': 'Panel Member',
      'target': 'manuscript',
      'updatedAt': at,
    });
    expect(m.target, ComposingTarget.manuscript);
    expect(m.isStaleAt(at.add(const Duration(seconds: 14))), isFalse);
    expect(m.isStaleAt(at.add(const Duration(seconds: 16))), isTrue);
    expect(ComposingTarget.fromString('bogus'), ComposingTarget.room);
  });
}
