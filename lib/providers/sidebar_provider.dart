import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/shared_prefs_provider.dart';

const sidebarExpandedKey = 'sidebar_expanded';

/// Whether the wide-screen sidebar shows labels or only icons.
///
/// Persisted, because collapsing it is a statement about how someone
/// wants to work and re-asking every launch ignores them. Same shape as
/// [facultyModeProvider], which persists the other durable UI choice in
/// this app.
///
/// Defaults to expanded: a first-time reader needs the labels, and the
/// icons alone are not self-explanatory until you have used them.
class SidebarExpandedNotifier extends Notifier<bool> {
  @override
  bool build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return prefs.getBool(sidebarExpandedKey) ?? true;
  }

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool(sidebarExpandedKey, state);
  }
}

final sidebarExpandedProvider =
    NotifierProvider<SidebarExpandedNotifier, bool>(
  SidebarExpandedNotifier.new,
);
