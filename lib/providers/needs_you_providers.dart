import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Decides whether a fan-in may publish yet.
///
/// `ref.listen(..., fireImmediately: true)` hands its listener an
/// `AsyncLoading` **value**, not `null`. A gate written as
/// `if (source == null) return` therefore passes on the very first frame,
/// and a merge built out of `valueOrNull ?? const []` publishes `data([])`
/// -- "Nothing needs you today" before a single snapshot has landed, and
/// forever after a `permission-denied`. That is the exact "0 is
/// indistinguishable from loading" bug spec §4 and §9 name, and this
/// project has shipped it four times.
///
/// Returns:
/// * `null` -- keep waiting; at least one source has no snapshot yet, so
///   the provider stays `AsyncLoading` (which is what the queue renders as
///   "Checking what needs you…").
/// * an errored [AsyncValue] -- the first source that failed. The caller
///   forwards it with `controller.addError` so the queue shows its error
///   state rather than an empty one.
/// * `data(true)` -- every source has a value; publish.
///
/// Errors are checked before loading so a failure is surfaced even while a
/// sibling source is still in flight: the read is not coming back, and a
/// queue that waits forever is no better than one that lies.
AsyncValue<bool>? _gate(List<AsyncValue<Object?>?> sources) {
  for (final source in sources) {
    if (source != null && source.hasError) {
      return AsyncValue<bool>.error(
        source.error!,
        source.stackTrace ?? StackTrace.empty,
      );
    }
  }
  for (final source in sources) {
    if (source == null || !source.hasValue) return null;
  }
  return const AsyncValue<bool>.data(true);
}

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
/// per source and `ref.onDispose` cleanup -- following the shape proven in
/// `myDefencesProvider`
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
    // Wait for a real VALUE from each top-level source before emitting --
    // not merely for a non-null AsyncValue, which `fireImmediately` supplies
    // on frame one. See [_gate].
    final gate = _gate([noms, advisees, defences]);
    if (gate == null) return;
    if (gate.hasError) {
      controller.addError(gate.error!, gate.stackTrace);
      return;
    }

    // The chapter fan-in is second-order: `syncChapterSubs` opens a
    // subscription per advised thesis the moment the advisee list resolves,
    // but those subscriptions have not delivered their first snapshot yet.
    // Emitting here would under-count the chapters awaiting review -- a
    // transient "nothing needs you" of exactly the kind this gate exists to
    // prevent -- so wait for every open subscription to have reported once.
    for (final id in chapterSubs.keys) {
      if (!chaptersByThesis.containsKey(id)) return;
    }

    final items = <NeedsYouItem>[];

    for (final p in noms!.requireValue) {
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
    for (final d in defences!.requireValue) {
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
          deep: true,
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
          deep: true,
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
  );

  ref.listen<AsyncValue<List<Thesis>>>(
    myAdviseesProvider,
    (previous, next) {
      advisees = next;
      next.whenData(syncChapterSubs);
      emit();
    },
    fireImmediately: true,
  );

  ref.listen<AsyncValue<List<Defence>>>(
    myDefencesProvider,
    (previous, next) {
      defences = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    for (final s in chapterSubs.values) {
      s.cancel();
    }
    controller.close();
  });

  return controller.stream;
});

/// What is waiting on the signed-in dean: nominations the Coordinator has
/// recommended, and candidate title sets ready for a defence decision.
///
/// Each row routes to exactly where the dean dashboard's own destinations
/// already send that same thesis -- `/review` for an approval (see the
/// `goToReview` button in `dean_dashboard.dart`) and `/defence/{id}` for a
/// title defence (see `DefenceQueue`) -- reused verbatim so a row here is
/// never a dead end.
///
/// A live fan-in over two [thesesByStatusProvider] streams, following the
/// shape proven in [facultyNeedsYouProvider]: one `ref.listen` subscription
/// per source and `ref.onDispose` cleanup. Do
/// NOT collapse this into an `await for` over one stream with `.first` read
/// against the other -- that shape only advances when the FIRST stream
/// emits, and a change that touches only the second source never arrives.
/// This project has shipped that exact bug once already.
final deanNeedsYouProvider = StreamProvider<List<NeedsYouItem>>((ref) {
  final controller = StreamController<List<NeedsYouItem>>();

  AsyncValue<List<Thesis>>? approvals;
  AsyncValue<List<Thesis>>? titleDefences;

  void emit() {
    // Wait for a real VALUE from each source before emitting -- not merely
    // for a non-null AsyncValue, which `fireImmediately` supplies on frame
    // one. See [_gate].
    final gate = _gate([approvals, titleDefences]);
    if (gate == null) return;
    if (gate.hasError) {
      controller.addError(gate.error!, gate.stackTrace);
      return;
    }

    final items = <NeedsYouItem>[
      for (final t in approvals!.requireValue)
        NeedsYouItem(
          title: t.workingTitle,
          detail: 'Recommended by the Coordinator, waiting on your '
              'approval.',
          route: '/review',
          chipLabel: 'Approve',
          tone: NeedsYouTone.act,
        ),
      for (final t in titleDefences!.requireValue)
        NeedsYouItem(
          title: t.workingTitle,
          detail: 'Presented their candidate titles -- decide the outcome.',
          route: '/defence/${t.id}',
          chipLabel: 'Decide',
          tone: NeedsYouTone.act,
          deep: true,
        ),
    ];

    controller.add(items);
  }

  ref.listen<AsyncValue<List<Thesis>>>(
    thesesByStatusProvider(ThesisStatus.nominationPendingDean),
    (previous, next) {
      approvals = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.listen<AsyncValue<List<Thesis>>>(
    thesesByStatusProvider(ThesisStatus.titlePendingDefence),
    (previous, next) {
      titleDefences = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.onDispose(controller.close);

  return controller.stream;
});

/// What is waiting on the signed-in coordinator: nominations that have
/// cleared every Conforme, candidate title sets ready for a defence
/// decision, and theses that have cleared the chapter gate for a defence
/// but have none scheduled yet.
///
/// Each row routes to exactly where the coordinator dashboard's own
/// destinations already send that same thesis -- `/review` for a
/// recommendation (see the `goToReview` button in `coordinator_dashboard.
/// dart`), `/defence/{id}` for a title defence (see `DefenceQueue`), and
/// `/defence/schedule?id={id}` for scheduling a defence (see the
/// `schedule-{id}` button in `defence_readiness.dart`'s `_ReadinessRow`) --
/// reused verbatim so a row here is never a dead end.
///
/// A live fan-in over four sources, following the shape proven in
/// [facultyNeedsYouProvider] and [deanNeedsYouProvider]: one `ref.listen`
/// subscription per top-level source and `ref.onDispose` cleanup. Do NOT collapse this into an `await for` over one
/// stream with `.first` read against another -- that shape only advances
/// when the FIRST stream emits, and a change that touches only a later
/// source never arrives. This project has shipped that exact bug once
/// already.
///
/// The "ready for a defence but none scheduled" source is itself a second,
/// nested fan-in, the same shape [facultyNeedsYouProvider] uses for its
/// chapter subscriptions: which theses to watch chapters for is only known
/// once the `titleApproved` list has emitted, and that list can grow or
/// shrink, so the per-thesis chapter subscriptions are opened and closed to
/// track it. Readiness itself is computed with [readinessOf] -- the exact
/// function `defence_readiness.dart` uses to decide the same question for
/// its own screen -- rather than re-deriving what "ready" means here. Two
/// definitions of readiness that could drift apart would be worse than
/// reusing the one that already exists.
///
/// Reads defences straight from [defenceRepositoryProvider] rather than
/// through [myDefencesProvider]: that provider awaits `currentUserProvider.
/// future` first (a known, out-of-scope quirk), and nothing on a needs-you
/// queue may depend on `users/{uid}` existing to resolve at all.
final coordinatorNeedsYouProvider = StreamProvider<List<NeedsYouItem>>((ref) {
  final controller = StreamController<List<NeedsYouItem>>();

  AsyncValue<List<Thesis>>? recommendations;
  AsyncValue<List<Thesis>>? titleDefences;
  AsyncValue<List<Thesis>>? readyCandidates;
  AsyncValue<List<Defence>>? defences;

  // thesisId -> its chapters, kept live by a subscription opened/closed as
  // the ready-candidate list itself changes (see the fan-in note above).
  final chaptersByThesis = <String, List<ThesisChapter>>{};
  final chapterSubs = <String, StreamSubscription<List<ThesisChapter>>>{};

  void emit() {
    // Wait for a real VALUE from each top-level source before emitting --
    // not merely for a non-null AsyncValue, which `fireImmediately` supplies
    // on frame one. See [_gate].
    final gate =
        _gate([recommendations, titleDefences, readyCandidates, defences]);
    if (gate == null) return;
    if (gate.hasError) {
      controller.addError(gate.error!, gate.stackTrace);
      return;
    }

    // The chapter fan-in is second-order: `syncChapterSubs` opens a
    // subscription per ready candidate the moment that list resolves, but
    // those subscriptions have not delivered a first snapshot yet, and a
    // candidate whose chapters are still unknown is silently skipped by the
    // readiness filter below. Wait for every open subscription to have
    // reported once.
    for (final id in chapterSubs.keys) {
      if (!chaptersByThesis.containsKey(id)) return;
    }

    final scheduledThesisIds = {
      for (final d in defences!.requireValue)
        if (!d.status.isTerminal) d.thesisId,
    };

    final items = <NeedsYouItem>[
      for (final t in recommendations!.requireValue)
        NeedsYouItem(
          title: t.workingTitle,
          detail: 'Every nominee has accepted their Conforme, waiting on '
              'your recommendation.',
          route: '/review',
          chipLabel: 'Recommend',
          tone: NeedsYouTone.act,
        ),
      for (final t in titleDefences!.requireValue)
        NeedsYouItem(
          title: t.workingTitle,
          detail: 'Presented their candidate titles -- decide the outcome.',
          route: '/defence/${t.id}',
          chipLabel: 'Decide',
          tone: NeedsYouTone.act,
          deep: true,
        ),
      for (final t in readyCandidates!.requireValue)
        if (!scheduledThesisIds.contains(t.id) &&
            chaptersByThesis[t.id] != null &&
            readinessOf(chaptersByThesis[t.id]!) != DefenceReadiness.notReady)
          NeedsYouItem(
            title: t.workingTitle,
            detail: 'Its chapters have cleared the gate for a defence -- '
                'schedule one.',
            route: '/defence/schedule?id=${t.id}',
            chipLabel: 'Schedule',
            tone: NeedsYouTone.act,
            deep: true,
          ),
    ];

    controller.add(items);
  }

  // Opens a chapter subscription for every currently ready-candidate thesis
  // that does not already have one, and closes any whose thesis fell off
  // the list -- the candidate list is the only thing that decides which
  // chapter streams should be open.
  void syncChapterSubs(List<Thesis> currentCandidates) {
    final ids = currentCandidates.map((t) => t.id).toSet();
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

  ref.listen<AsyncValue<List<Thesis>>>(
    thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator),
    (previous, next) {
      recommendations = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.listen<AsyncValue<List<Thesis>>>(
    thesesByStatusProvider(ThesisStatus.titlePendingDefence),
    (previous, next) {
      titleDefences = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.listen<AsyncValue<List<Thesis>>>(
    thesesByStatusProvider(ThesisStatus.titleApproved),
    (previous, next) {
      readyCandidates = next;
      next.whenData(syncChapterSubs);
      emit();
    },
    fireImmediately: true,
  );

  ref.listen<AsyncValue<List<Defence>>>(
    allDefencesProvider,
    (previous, next) {
      defences = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.onDispose(() {
    for (final s in chapterSubs.values) {
      s.cancel();
    }
    controller.close();
  });

  return controller.stream;
});
