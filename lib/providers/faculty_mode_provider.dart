import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

const facultyModeKey = 'faculty_mode';

class FacultyModeNotifier extends Notifier<FacultyMode> {
  @override
  FacultyMode build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return FacultyMode.fromString(prefs.getString(facultyModeKey));
  }

  void set(FacultyMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider).setString(facultyModeKey, mode.value);
  }
}

final facultyModeProvider =
    NotifierProvider<FacultyModeNotifier, FacultyMode>(FacultyModeNotifier.new);

/// Number of theses where the signed-in faculty member is the adviser.
/// M1 replaces this body with a query over `theses` filtered by adviserUid.
final adviserPositionCountProvider = Provider<int>((ref) => 0);

/// Items awaiting action in whichever mode is NOT currently selected.
/// M1/M3 replace this body with real pending-work counts.
final pendingInOtherModeProvider = Provider<int>((ref) => 0);
