import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// What is waiting on the signed-in student.
///
/// Only items they can act on. A chapter sitting with the adviser is NOT
/// here — it is on a tile, where a number is the honest representation of
/// "someone else has it". An empty queue is therefore real information.
final studentNeedsYouProvider =
    StreamProvider<List<NeedsYouItem>>((ref) async* {
  final thesis = await ref.watch(myThesisProvider.future);
  if (thesis == null) {
    yield const [];
    return;
  }

  final items = <NeedsYouItem>[];

  if (thesis.status == ThesisStatus.draft) {
    items.add(NeedsYouItem(
      title: thesis.workingTitle,
      detail: 'Still a draft — nominate an adviser and panel to begin.',
      route: '/thesis/nominate?id=${thesis.id}',
      chipLabel: 'Nominate',
      tone: NeedsYouTone.act,
    ));
  }

  if (thesis.status == ThesisStatus.titleRejected) {
    items.add(NeedsYouItem(
      title: thesis.workingTitle,
      detail: 'Your candidate titles were returned. Submit a new set.',
      route: '/thesis/titles?id=${thesis.id}',
      chipLabel: 'Resubmit',
      tone: NeedsYouTone.returned,
    ));
  }

  // Chapters only exist once a title is approved, so this stream is only
  // subscribed after that point. Reached through the repository directly
  // rather than `chaptersProvider(...).stream` -- that getter is deprecated
  // in this Riverpod version, and going straight to the repository (as
  // `currentUserProvider` does for its own nested stream) avoids it without
  // losing the dependency on `documentRepositoryProvider`.
  if (thesis.status == ThesisStatus.titleApproved) {
    await for (final chapters in ref
        .watch(documentRepositoryProvider)
        .watchChapters(thesis.id)) {
      yield [
        ...items,
        for (final c in chapters)
          if (c.status == ChapterStatus.revise)
            NeedsYouItem(
              title: c.id.label,
              detail: 'Returned by your adviser — revise and re-upload.',
              route: '/thesis/chapters?id=${thesis.id}',
              chipLabel: 'Revise',
              tone: NeedsYouTone.returned,
            ),
      ];
    }
    return;
  }

  yield items;
});
