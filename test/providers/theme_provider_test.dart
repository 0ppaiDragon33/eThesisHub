import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/theme_provider.dart';

Future<ProviderContainer> containerWith(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('defaults to system on a first run', () async {
    final c = await containerWith({});
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('cycling steps system -> light -> dark -> system', () async {
    final c = await containerWith({});
    addTearDown(c.dispose);

    c.read(themeModeProvider.notifier).cycle();
    expect(c.read(themeModeProvider), ThemeMode.light);

    c.read(themeModeProvider.notifier).cycle();
    expect(c.read(themeModeProvider), ThemeMode.dark);

    c.read(themeModeProvider.notifier).cycle();
    expect(c.read(themeModeProvider), ThemeMode.system);
  });

  test('the choice persists across a container rebuild', () async {
    // Copies "the choice survives a restart" from sidebar_provider_test.dart.
    final first = await containerWith({});
    first.read(themeModeProvider.notifier).cycle(); // -> light
    first.dispose();

    // Same backing store, fresh container — what a relaunch looks like.
    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);

    expect(second.read(themeModeProvider), ThemeMode.light);
  });

  test('a stored dark value is honoured at startup', () async {
    final c = await containerWith({'theme_mode': 'dark'});
    addTearDown(c.dispose);
    expect(c.read(themeModeProvider), ThemeMode.dark);
  });
}
