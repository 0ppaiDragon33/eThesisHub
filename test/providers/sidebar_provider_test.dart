import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ethesishub/providers/shared_prefs_provider.dart';
import 'package:ethesishub/providers/sidebar_provider.dart';

Future<ProviderContainer> containerWith(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('defaults to expanded on a first run', () async {
    final c = await containerWith({});
    addTearDown(c.dispose);
    expect(c.read(sidebarExpandedProvider), isTrue);
  });

  test('toggling flips the state', () async {
    final c = await containerWith({});
    addTearDown(c.dispose);

    c.read(sidebarExpandedProvider.notifier).toggle();
    expect(c.read(sidebarExpandedProvider), isFalse);
  });

  test('the choice survives a restart', () async {
    // The point of persisting it. A reader who collapses the sidebar has
    // said something about how they want to work; asking again every
    // launch ignores them.
    final first = await containerWith({});
    first.read(sidebarExpandedProvider.notifier).toggle();
    first.dispose();

    // Same backing store, fresh container — what a relaunch looks like.
    final prefs = await SharedPreferences.getInstance();
    final second = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(second.dispose);

    expect(second.read(sidebarExpandedProvider), isFalse);
  });

  test('a stored collapsed value is honoured at startup', () async {
    final c = await containerWith({'sidebar_expanded': false});
    addTearDown(c.dispose);
    expect(c.read(sidebarExpandedProvider), isFalse);
  });
}
