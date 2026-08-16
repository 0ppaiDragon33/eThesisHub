import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final titleDefenceRepositoryProvider = Provider<TitleDefenceRepository>(
  (ref) => TitleDefenceRepository(ref.watch(firestoreProvider)),
);

/// The candidate titles on one thesis, every round.
final candidateTitlesProvider =
    StreamProvider.family<List<CandidateTitle>, String>((ref, thesisId) {
  return ref.watch(titleDefenceRepositoryProvider)
      .watchCandidateTitles(thesisId);
});

/// Every comment on one thesis, live. Panel members hold this open through
/// the defence so a remark appears for the rest of the panel as it is
/// written — the point being that nobody repeats a point already made.
final titleCommentsProvider =
    StreamProvider.family<List<TitleComment>, String>((ref, thesisId) {
  return ref.watch(titleDefenceRepositoryProvider).watchComments(thesisId);
});
