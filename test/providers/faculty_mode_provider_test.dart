import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderContainer> containerWith(Map<String, Object> seed) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('defaults to adviser mode', () async {
    final container = await containerWith({});
    addTearDown(container.dispose);

    expect(container.read(facultyModeProvider), FacultyMode.adviser);
  });

  test('restores the persisted mode', () async {
    final container = await containerWith({'faculty_mode': 'panelist'});
    addTearDown(container.dispose);

    expect(container.read(facultyModeProvider), FacultyMode.panelist);
  });

  test('set updates state and persists', () async {
    final container = await containerWith({});
    addTearDown(container.dispose);

    container.read(facultyModeProvider.notifier).set(FacultyMode.panelist);

    expect(container.read(facultyModeProvider), FacultyMode.panelist);
    expect(
      container.read(sharedPrefsProvider).getString('faculty_mode'),
      'panelist',
    );
  });
}
