/// How a queue row should be coloured — from the MEANING palette, not the
/// accents. This is a verdict about the item, so it uses the vocabulary
/// chips and buttons already use.
enum NeedsYouTone { act, waiting, returned }

/// One thing waiting on the person reading the screen.
///
/// Every dashboard's queue is built from these, so the widget is written
/// once and each role supplies its own list. A row is only ever an item the
/// reader can actually act on — an empty queue is therefore real
/// information rather than a screen that failed to load.
class NeedsYouItem {
  const NeedsYouItem({
    required this.title,
    required this.detail,
    required this.route,
    required this.chipLabel,
    required this.tone,
    this.deep = false,
  });

  final String title;
  final String detail;

  /// Where "Open" goes.
  ///
  /// Rows in this queue point at a mix of destinations (e.g. `/review`,
  /// `/nominations`) and screens below a destination (e.g.
  /// `/defence/{id}`, `/defence/schedule`). [deep] says which this is, so
  /// `NeedsYouQueue` can send the former through `context.go` and the
  /// latter through `context.push` — a blanket rule would either stack
  /// destinations or leave a deep screen unable to pop back here.
  final String route;
  final String chipLabel;
  final NeedsYouTone tone;

  /// True when [route] is a screen below a destination (opened with
  /// `context.push`), false when it is a destination itself (`context.go`).
  final bool deep;
}
