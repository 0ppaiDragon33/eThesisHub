import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/repositories/archive_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => ArchiveRepository(ref.watch(firestoreProvider)),
);

/// Every published thesis, newest first.
///
/// One query, and filtering happens on the client (D54) — Firestore has no
/// substring search, so `where('title', isGreaterThanOrEqualTo: q)` would
/// match prefixes only and a student typing "fisheries" would never find
/// "A Study of Coastal Fisheries". At a college's scale this is correct;
/// at thousands of entries it needs an index service.
final archiveProvider = StreamProvider<List<ArchiveEntry>>((ref) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(archiveRepositoryProvider).watchArchive();
});

final archiveEntryProvider =
    StreamProvider.family<ArchiveEntry?, String>((ref, thesisId) {
  ref.watch(signedInUidProvider);
  return ref.watch(archiveRepositoryProvider).watchEntry(thesisId);
});

/// Decides whether the queue's fan-in may publish yet.
///
/// Follows [facultyNeedsYouProvider]'s `_gate` in
/// `lib/providers/needs_you_providers.dart` verbatim — that helper is
/// library-private to its own file, so this is a second copy rather than a
/// shared one. `ref.listen(..., fireImmediately: true)` hands its listener
/// an `AsyncLoading` **value**, not `null`, so a gate written as
/// `if (source == null) return` passes on the very first frame and a merge
/// built out of `valueOrNull ?? const []` publishes `data([])` — an empty
/// queue — before a single snapshot has landed, and forever after a
/// `permission-denied`. This project has shipped that exact "0 is
/// indistinguishable from loading" bug more than once, so this waits for a
/// real VALUE from every source, and surfaces the first error before
/// waiting on any source still in flight.
AsyncValue<bool>? _queueGate(List<AsyncValue<Object?>?> sources) {
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

/// The coordinator's publish queue: every thesis that passed a final
/// defence, has uploaded its manuscript, and is not yet in the archive.
///
/// A three-way live fan-in over [allThesesProvider], [allDefencesProvider]
/// and [archiveProvider] — one `ref.listen(fireImmediately: true)`
/// subscription per source, gated by [_queueGate], following the shape
/// proven in `facultyNeedsYouProvider`
/// (`lib/providers/needs_you_providers.dart`). Do NOT collapse this into an
/// `await for` over one stream with `.first` read against the others: that
/// shape only advances when the FIRST stream emits, so a change touching
/// only a later source — a manuscript upload, or a retraction — would never
/// arrive. This project has shipped that exact bug once already.
///
/// "Not yet in the archive" is read off [archiveProvider] itself, the third
/// fan-in source, rather than off `thesis.status == archived` — the archive
/// collection is the literal record of what has been published, and
/// [ArchiveRepository.publish] writes both in the same batch, so the two
/// can never disagree.
final archiveQueueProvider = StreamProvider<List<Thesis>>((ref) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);

  final controller = StreamController<List<Thesis>>();

  AsyncValue<List<Thesis>>? theses;
  AsyncValue<List<Defence>>? defences;
  AsyncValue<List<ArchiveEntry>>? archive;

  void emit() {
    // Wait for a real VALUE from each source before emitting -- not merely
    // for a non-null AsyncValue, which `fireImmediately` supplies on frame
    // one. See [_queueGate].
    final gate = _queueGate([theses, defences, archive]);
    if (gate == null) return;
    if (gate.hasError) {
      controller.addError(gate.error!, gate.stackTrace);
      return;
    }

    final archivedIds = {
      for (final e in archive!.requireValue) e.thesisId,
    };

    // A thesis "passed a final defence" if ANY of its final defences carries
    // a Pass verdict -- there is at most one that matters in practice (a
    // thesis is archived and leaves the queue the moment its manuscript
    // lands), but nothing here assumes exactly one final defence exists.
    final passedFinalThesisIds = {
      for (final d in defences!.requireValue)
        if (d.type == DefenceType.final_ && d.panelVerdict == PassFail.pass)
          d.thesisId,
    };

    final queue = [
      for (final t in theses!.requireValue)
        if (passedFinalThesisIds.contains(t.id) &&
            t.hasManuscript &&
            !archivedIds.contains(t.id))
          t,
    ];

    controller.add(queue);
  }

  ref.listen<AsyncValue<List<Thesis>>>(
    allThesesProvider,
    (previous, next) {
      theses = next;
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

  ref.listen<AsyncValue<List<ArchiveEntry>>>(
    archiveProvider,
    (previous, next) {
      archive = next;
      emit();
    },
    fireImmediately: true,
  );

  ref.onDispose(controller.close);

  return controller.stream;
});
