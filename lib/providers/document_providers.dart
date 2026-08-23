import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/repositories/document_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

typedef ChapterRef = ({String thesisId, ChapterId chapter});

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(firestoreProvider)),
);

final chaptersProvider =
    StreamProvider.family<List<ThesisChapter>, String>((ref, thesisId) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(documentRepositoryProvider).watchChapters(thesisId);
});

final chapterVersionsProvider =
    StreamProvider.family<List<ChapterVersion>, ChapterRef>((ref, r) {
  ref.watch(signedInUidProvider);
  return ref
      .watch(documentRepositoryProvider)
      .watchVersions(r.thesisId, r.chapter);
});

final chapterFeedbackProvider =
    StreamProvider.family<List<ChapterFeedback>, ChapterRef>((ref, r) {
  ref.watch(signedInUidProvider);
  return ref
      .watch(documentRepositoryProvider)
      .watchFeedback(r.thesisId, r.chapter);
});
