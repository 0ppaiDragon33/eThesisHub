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
  });

  final String title;
  final String detail;

  /// Where "Open" goes. A go_router location, pushed with `context.go`.
  final String route;
  final String chipLabel;
  final NeedsYouTone tone;
}
