import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/needs_you_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Provider-level, not widget-level, deliberately.
///
/// The three widget tests named "a loading queue is distinguishable from an
/// empty one" each override the very provider under test with their own
/// never-emitting stream, so they exercise `NeedsYouQueue` and say nothing
/// about the fan-ins. These do the opposite: they drive the real fan-in
/// with controlled sources and read the provider's own `AsyncValue`.
///
/// The bug they pin: `ref.listen(..., fireImmediately: true)` hands the
/// listener an `AsyncLoading` VALUE, which is not null. A gate written as
/// `if (source == null) return` therefore passes on the first frame, and
/// `valueOrNull ?? const []` publishes `data([])` -- "Nothing needs you
/// today" before a single snapshot has landed, and forever after a
/// `permission-denied`.

/// Lets every pending microtask and the fan-in's own listeners run.
Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A stream that is subscribed but never produces anything.
Stream<T> never<T>() => StreamController<T>().stream;

void main() {
  group('facultyNeedsYouProvider', () {
    test('stays loading while its sources are loading, never data([])',
        () async {
      final container = ProviderContainer(overrides: [
        signedInUidProvider.overrideWithValue('f1'),
        myPendingNominationsProvider.overrideWith(
            (ref) => never<List<({String thesisId, Nomination nomination})>>()),
        myAdviseesProvider.overrideWith((ref) => never<List<Thesis>>()),
        myDefencesProvider.overrideWith((ref) => never<List<Defence>>()),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<NeedsYouItem>>>[];
      container.listen(facultyNeedsYouProvider, (_, next) => states.add(next),
          fireImmediately: true);
      await settle();

      expect(container.read(facultyNeedsYouProvider), isA<AsyncLoading>());
      expect(
        states.any((s) => s is AsyncData<List<NeedsYouItem>> && s.value.isEmpty),
        isFalse,
        reason: 'published an empty queue before any source had a snapshot',
      );
    });

    test('surfaces a source error rather than an empty queue', () async {
      final container = ProviderContainer(overrides: [
        signedInUidProvider.overrideWithValue('f1'),
        myPendingNominationsProvider.overrideWith((ref) =>
            Stream<List<({String thesisId, Nomination nomination})>>.error(
                StateError('permission-denied'))),
        myAdviseesProvider.overrideWith((ref) => never<List<Thesis>>()),
        myDefencesProvider.overrideWith((ref) => never<List<Defence>>()),
      ]);
      addTearDown(container.dispose);

      container.listen(facultyNeedsYouProvider, (_, _) {},
          fireImmediately: true);
      await settle();

      expect(container.read(facultyNeedsYouProvider).hasError, isTrue);
    });
  });

  group('deanNeedsYouProvider', () {
    test('stays loading while its sources are loading, never data([])',
        () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingDean)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<NeedsYouItem>>>[];
      container.listen(deanNeedsYouProvider, (_, next) => states.add(next),
          fireImmediately: true);
      await settle();

      expect(container.read(deanNeedsYouProvider), isA<AsyncLoading>());
      expect(
        states.any((s) => s is AsyncData<List<NeedsYouItem>> && s.value.isEmpty),
        isFalse,
        reason: 'published an empty queue before any source had a snapshot',
      );
    });

    test('surfaces a source error rather than an empty queue', () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingDean).overrideWith(
            (ref) => Stream<List<Thesis>>.error(
                StateError('permission-denied'))),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
      ]);
      addTearDown(container.dispose);

      container.listen(deanNeedsYouProvider, (_, _) {}, fireImmediately: true);
      await settle();

      expect(container.read(deanNeedsYouProvider).hasError, isTrue);
    });
  });

  group('coordinatorNeedsYouProvider', () {
    test('stays loading while its sources are loading, never data([])',
        () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titleApproved)
            .overrideWith((ref) => never<List<Thesis>>()),
        allDefencesProvider.overrideWith((ref) => never<List<Defence>>()),
      ]);
      addTearDown(container.dispose);

      final states = <AsyncValue<List<NeedsYouItem>>>[];
      container.listen(
          coordinatorNeedsYouProvider, (_, next) => states.add(next),
          fireImmediately: true);
      await settle();

      expect(
          container.read(coordinatorNeedsYouProvider), isA<AsyncLoading>());
      expect(
        states.any((s) => s is AsyncData<List<NeedsYouItem>> && s.value.isEmpty),
        isFalse,
        reason: 'published an empty queue before any source had a snapshot',
      );
    });

    test('surfaces a source error rather than an empty queue', () async {
      final container = ProviderContainer(overrides: [
        thesesByStatusProvider(ThesisStatus.nominationPendingCoordinator)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titlePendingDefence)
            .overrideWith((ref) => never<List<Thesis>>()),
        thesesByStatusProvider(ThesisStatus.titleApproved)
            .overrideWith((ref) => never<List<Thesis>>()),
        allDefencesProvider.overrideWith((ref) =>
            Stream<List<Defence>>.error(StateError('permission-denied'))),
      ]);
      addTearDown(container.dispose);

      container.listen(coordinatorNeedsYouProvider, (_, _) {},
          fireImmediately: true);
      await settle();

      expect(container.read(coordinatorNeedsYouProvider).hasError, isTrue);
    });
  });
}
