import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/composing_indicator.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

final titleDefenceRepositoryProvider = Provider<TitleDefenceRepository>(
  (ref) => TitleDefenceRepository(ref.watch(firestoreProvider)),
);

/// The candidate titles on one thesis, every round.
final candidateTitlesProvider =
    StreamProvider.family<List<CandidateTitle>, String>((ref, thesisId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(titleDefenceRepositoryProvider)
      .watchCandidateTitles(thesisId);
});

/// Every comment on one thesis, live. Panel members hold this open through
/// the defence so a remark appears for the rest of the panel as it is
/// written — the point being that nobody repeats a point already made.
final titleCommentsProvider =
    StreamProvider.family<List<TitleComment>, String>((ref, thesisId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(titleDefenceRepositoryProvider).watchComments(thesisId);
});

/// Who is currently writing, stale entries included. Filter with
/// `isStaleAt(DateTime.now())` at the point of display.
final composingProvider =
    StreamProvider.family<List<ComposingIndicator>, String>((ref, thesisId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(titleDefenceRepositoryProvider).watchComposing(thesisId);
});

/// Thesis ids the signed-in faculty member holds a position on.
final myThesisIdsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(titleDefenceRepositoryProvider).watchMyThesisIds(uid);
});

/// The theses at title defence that the signed-in reader can open
/// (spec 2026-09-25 §6.2), per role:
/// - Coordinator and Dean: every one.
/// - Faculty: the ones they advise **or** sit on, each once. An adviser in
///   adviser mode never sees the Panels page, so advised theses must come
///   from [myAdviseesProvider], not only from nominations.
/// - Student: their own thesis, while it is at title defence.
final myTitleDefencesProvider = Provider<AsyncValue<List<Thesis>>>((ref) {
  final me = ref.watch(currentUserProvider);
  if (!me.hasValue) {
    return me.hasError
        ? AsyncError(me.error!, me.stackTrace ?? StackTrace.empty)
        : const AsyncLoading();
  }

  bool atTitleDefence(Thesis t) =>
      t.status == ThesisStatus.titlePendingDefence;

  switch (me.value?.role) {
    case UserRole.coordinator || UserRole.dean:
      return ref.watch(
          thesesByStatusProvider(ThesisStatus.titlePendingDefence));
    case UserRole.student:
      return ref.watch(myThesisProvider).whenData(
          (t) => t != null && atTitleDefence(t) ? [t] : const <Thesis>[]);
    case UserRole.faculty:
      final advised = ref.watch(myAdviseesProvider);
      final ids = ref.watch(myThesisIdsProvider);
      for (final a in [advised, ids]) {
        if (a.hasError && !a.hasValue) {
          return AsyncError(a.error!, a.stackTrace ?? StackTrace.empty);
        }
      }
      if (!advised.hasValue || !ids.hasValue) return const AsyncLoading();

      final byId = {for (final t in advised.value!) t.id: t};
      for (final id in ids.value!) {
        if (byId.containsKey(id)) continue;
        final t = ref.watch(thesisByIdProvider(id));
        if (!t.hasValue && !t.hasError) return const AsyncLoading();
        // A thesis the reader can no longer read (a declined nomination) or
        // that no longer exists is simply not theirs to open.
        final thesis = t.valueOrNull;
        if (thesis != null) byId[id] = thesis;
      }
      return AsyncData(byId.values.where(atTitleDefence).toList());
    case null:
      return const AsyncData(<Thesis>[]);
  }
});
