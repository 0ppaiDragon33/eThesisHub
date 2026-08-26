import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
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

/// What is waiting on the signed-in faculty member.
///
/// Deliberately mode-blind. The tiles above it are mode-aware, matching D5,
/// but a Conforme request or a consolidation you owe must not hide behind
/// the Adviser/Panelist switch: the person who needs to see it has no reason
/// to think of looking in the other mode. If you ever find yourself reaching
/// for `facultyModeProvider` in here, that is the bug.
///
/// Merges four sources with a live fan-in -- one `.listen()` subscription
/// per source, `ref.onDispose` cleanup, `onError: controller.addError` on
/// every one of them -- following the shape proven in `myDefencesProvider`
/// (`lib/providers/defence_providers.dart:32`). Do NOT collapse this into an
/// `await for` over one stream with `.first` read against another: that
/// shape only advances when the FIRST stream emits, and a change that
/// touches only a later source never arrives. This project has shipped that
/// exact bug once already.
///
/// The chapter source is itself a second, nested fan-in: which theses to
/// watch is only known once `myAdviseesProvider` has emitted, and that list
/// can grow or shrink, so the per-thesis chapter subscriptions are opened
/// and closed to track it rather than fixed at provider-build time.
final facultyNeedsYouProvider =
    StreamProvider<List<NeedsYouItem>>((ref) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) {
    return Stream.value(const <NeedsYouItem>[]);
  }

  final controller = StreamController<List<NeedsYouItem>>();

  AsyncValue<List<({String thesisId, Nomination nomination})>>? noms;
  AsyncValue<List<Thesis>>? advisees;
  AsyncValue<List<Defence>>? defences;

  // thesisId -> its chapters, kept live by a subscription opened/closed as
  // the advisee list itself changes (see the fan-in note above).
  final chaptersByThesis = <String, List<ThesisChapter>>{};
  final chapterSubs = <String, StreamSubscription<List<ThesisChapter>>>{};

  void emit() {
    // Wait for one snapshot from each top-level source before emitting, so
    // the queue never renders a partial merge as though it were complete.
    if (noms == null || advisees == null || defences == null) return;

    final items = <NeedsYouItem>[];

    for (final p in (noms!.valueOrNull ?? const [])) {
      final position = p.nomination.position.value;
      final label = position.isEmpty
          ? position
          : position[0].toUpperCase() + position.substring(1);
      items.add(NeedsYouItem(
        title: 'Nomination as $label',
        detail: 'A group has nominated you and is waiting on your Conforme.',
        route: '/nominations',
        chipLabel: 'Reply',
        tone: NeedsYouTone.act,
      ));
    }

    for (final entry in chaptersByThesis.entries) {
      for (final chapter in entry.value) {
        if (chapter.status != ChapterStatus.submitted) continue;
        items.add(NeedsYouItem(
          title: chapter.id.label,
          detail: 'Submitted by the group and waiting on your review.',
          route: '/thesis/chapters?id=${entry.key}',
          chipLabel: 'Review',
          tone: NeedsYouTone.waiting,
        ));
      }
    }

    final now = DateTime.now();
    for (final d in (defences!.valueOrNull ?? const [])) {
      if (d.adviserUid == uid &&
          d.status == DefenceStatus.completed &&
          d.consolidatedAt == null) {
        items.add(NeedsYouItem(
          title: d.type.label,
          detail: 'The defence concluded — release your consolidation to '
              'the group.',
          route: '/defence/${d.id}',
          chipLabel: 'Consolidate',
          tone: NeedsYouTone.act,
        ));
      }

      final at = d.scheduledAt;
      final scheduledToday = at != null &&
          at.year == now.year &&
          at.month == now.month &&
          at.day == now.day;
      if (d.status == DefenceStatus.inProgress || scheduledToday) {
        items.add(NeedsYouItem(
          title: d.type.label,
          detail: d.status == DefenceStatus.inProgress
              ? 'This defence is in progress now.'
              : 'Scheduled for today at ${d.venue}.',
          route: '/defence/${d.id}',
          chipLabel: 'Join',
          tone: NeedsYouTone.act,
        ));
      }
    }

    controller.add(items);
  }

  // Opens a chapter subscription for every currently advised thesis that
  // does not already have one, and closes any whose thesis fell off the
  // list -- the advisee list is the only thing that decides which chapter
  // streams should be open.
  void syncChapterSubs(List<Thesis> currentAdvisees) {
    final ids = currentAdvisees.map((t) => t.id).toSet();
    for (final id in chapterSubs.keys.toList()) {
      if (!ids.contains(id)) {
        chapterSubs.remove(id)?.cancel();
        chaptersByThesis.remove(id);
      }
    }
    for (final id in ids) {
      if (chapterSubs.containsKey(id)) continue;
      chapterSubs[id] = ref
          .watch(documentRepositoryProvider)
          .watchChapters(id)
          .listen((chapters) {
        chaptersByThesis[id] = chapters;
        emit();
      }, onError: controller.addError);
    }
  }

  ref.listen<AsyncValue<List<({String thesisId, Nomination nomination})>>>(
    myPendingNominationsProvider,
    (previous, next) {
      noms = next;
      emit();
    },
    fireImmediately: true,
    onError: (e, st) => controller.addError(e, st),
  );

  ref.listen<AsyncValue<List<Thesis>>>(
    myAdviseesProvider,
    (previous, next) {
      advisees = next;
      next.whenData(syncChapterSubs);
      emit();
    },
    fireImmediately: true,
    onError: (e, st) => controller.addError(e, st),
  );

  ref.listen<AsyncValue<List<Defence>>>(
    myDefencesProvider,
    (previous, next) {
      defences = next;
      emit();
    },
    fireImmediately: true,
    onError: (e, st) => controller.addError(e, st),
  );

  ref.onDispose(() {
    for (final s in chapterSubs.values) {
      s.cancel();
    }
    controller.close();
  });

  return controller.stream;
});
