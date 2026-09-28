import 'package:flutter/material.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';

/// Eight colours told apart by most colour-blind readers too (after
/// Okabe and Ito), so each person's highlights are recognisably theirs.
const kHighlightPalette = <Color>[
  Color(0xFFE69F00), // orange
  Color(0xFF56B4E9), // sky blue
  Color(0xFF009E73), // green
  Color(0xFFF0E442), // yellow
  Color(0xFF0072B2), // blue
  Color(0xFFD55E00), // vermilion
  Color(0xFFCC79A7), // pink
  Color(0xFF8C6BB1), // violet
];

/// Each person's colour on this defence: the adviser first, then the panel
/// in the order they were named, then anyone else (the Coordinator, the
/// Dean) in the order of their first highlight. Computed, not stored, so
/// every viewer sees the same colours. [annotations] must be oldest first.
Map<String, Color> highlightColours({
  required Defence defence,
  required List<DefenceAnnotation> annotations,
}) {
  final order = <String>[];
  void add(String uid) {
    if (uid.isNotEmpty && !order.contains(uid)) order.add(uid);
  }

  add(defence.adviserUid);
  defence.panelUids.forEach(add);
  for (final a in annotations) {
    add(a.authorUid);
  }
  return {
    for (var i = 0; i < order.length; i++)
      order[i]: kHighlightPalette[i % kHighlightPalette.length],
  };
}

/// Each highlight's number: its place in creation order, so "see 3" still
/// means the same box after others are added. Removing a highlight
/// renumbers the ones made after it.
Map<String, int> highlightNumbers(List<DefenceAnnotation> oldestFirst) => {
      for (var i = 0; i < oldestFirst.length; i++) oldestFirst[i].id: i + 1,
    };

/// Chapter, then page, then down the page: the order a reader meets them.
List<DefenceAnnotation> inPageOrder(List<DefenceAnnotation> list) =>
    [...list]..sort((a, b) {
        final byChapter = a.chapter.index.compareTo(b.chapter.index);
        if (byChapter != 0) return byChapter;
        final byPage = a.page.compareTo(b.page);
        if (byPage != 0) return byPage;
        final byY = a.rect.y.compareTo(b.rect.y);
        if (byY != 0) return byY;
        return a.rect.x.compareTo(b.rect.x);
      });

class HighlightAuthor {
  const HighlightAuthor({
    required this.uid,
    required this.name,
    required this.colour,
  });

  final String uid;
  final String name;
  final Color colour;
}

/// Who has highlighted, in colour order, with the name from their first one.
List<HighlightAuthor> highlightLegend(
  List<DefenceAnnotation> annotations,
  Map<String, Color> colours,
) {
  final names = <String, String>{};
  for (final a in annotations) {
    names.putIfAbsent(a.authorUid, () => a.authorName);
  }
  return [
    for (final entry in colours.entries)
      if (names.containsKey(entry.key))
        HighlightAuthor(
            uid: entry.key, name: names[entry.key]!, colour: entry.value),
  ];
}

/// A highlight's number in its author's colour, on the box and in the list.
class HighlightTag extends StatelessWidget {
  const HighlightTag({super.key, required this.number, required this.colour});

  final int number;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final ink =
        colour.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$number',
        style: TextStyle(
            color: ink, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}
