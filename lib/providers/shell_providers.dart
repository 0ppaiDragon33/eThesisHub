import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/navigation/shell_destination.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The destinations for the signed-in account, or loading while the role
/// is still resolving.
///
/// Returns [AsyncValue] rather than a plain list so the shell can render
/// skeleton rows instead of guessing (spec D26). An unknown role yields an
/// EMPTY list, never a default one (spec D25) — the redirect is what sends
/// that account to `/no-profile`, and a sidebar that had meanwhile guessed
/// "student" would offer destinations the account does not hold.
final shellDestinationsProvider =
    Provider<AsyncValue<List<ShellDestination>>>((ref) {
  final profileAsync = ref.watch(currentUserProvider);
  return profileAsync.when(
    loading: () => const AsyncValue.loading(),
    error: AsyncValue.error,
    data: (profile) {
      if (profile == null) return const AsyncValue.data([]);

      // Watched only for a faculty member. The mode is derived from
      // adviser/panel position queries that no other role has any reason
      // to run — and that `firestore.rules` need not permit them.
      final isFaculty = profile.role == UserRole.faculty;
      final modeAsync = isFaculty
          ? ref.watch(effectiveFacultyModeProvider)
          : const AsyncValue<FacultyMode?>.data(FacultyMode.adviser);

      // The faculty mode decides whether the sidebar offers Advisees or
      // Panels, so for a faculty member it is not optional detail — it is
      // half the list. Held as loading rather than defaulted, which is the
      // rule faculty_dashboard.dart arrived at the hard way: defaulting
      // while it resolves shows a panelist the Advisees destination and
      // then swaps it out from under them on every launch, and a
      // panelist-only member cannot correct it because the mode switch
      // hides itself precisely when you hold no adviser position.
      //
      // A mode that has genuinely FAILED is different from one still
      // arriving: there is no second chance coming, and a shell with no
      // sidebar at all strands the reader on whatever page they are on —
      // the exact failure this milestone exists to close. So an error
      // falls back to adviser and keeps the sidebar. Both routes exist and
      // neither refuses a faculty member, so the worst case is one wrong
      // label, reachable and correctable via the mode switch.
      if (isFaculty && modeAsync.isLoading) {
        return const AsyncValue.loading();
      }

      // Read with `valueOrNull`, and it cannot misroute anyone: this gates
      // Chapters and Defences for a student, so while it is loading the
      // pair is simply not offered yet and arrives a frame later. Holding
      // the whole sidebar in a skeleton on it instead would blank
      // navigation for every role that never has a thesis at all.
      final thesis = ref.watch(myThesisProvider).valueOrNull;

      // A genuinely FAILED mode (as opposed to one still resolving, already
      // handled above) falls back to adviser so the sidebar stays reachable
      // rather than stranding a faculty member with none at all -- the
      // worst case is one wrong label, correctable via the mode switch. A
      // successfully resolved `null`, by contrast, means "neither" and is
      // passed straight through: `destinationsFor` is the one that turns it
      // into "no Advisees, no Panels" rather than an empty screen.
      final facultyMode =
          modeAsync.hasError ? FacultyMode.adviser : modeAsync.valueOrNull;

      return AsyncValue.data(destinationsFor(
        role: profile.role,
        chaptersUnlocked: thesis?.status == ThesisStatus.titleApproved,
        facultyMode: facultyMode,
      ));
    },
  );
});
