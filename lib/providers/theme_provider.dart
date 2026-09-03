import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/shared_prefs_provider.dart';

const themeModeKey = 'theme_mode';

/// The reader's chosen light/dark/system preference.
///
/// Persisted for the same reason [SidebarExpandedNotifier] persists its
/// choice: picking a theme is a statement about how someone wants to read
/// the app, and re-asking every launch ignores them. Same shape as that
/// provider on purpose -- a `Notifier<ThemeMode>` that reads prefs in
/// `build()` and writes in its setter, with a module-level key constant.
///
/// Defaults to [ThemeMode.system]: matching the OS is the least surprising
/// starting point for a reader who has never touched the control.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPrefsProvider);
    final stored = prefs.getString(themeModeKey);
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// Cycles system -> light -> dark -> system, the order the footer's
  /// toggle button steps through on each tap.
  void cycle() {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    state = next;
    ref.read(sharedPrefsProvider).setString(themeModeKey, next.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
