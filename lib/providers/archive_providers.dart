import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/data/repositories/archive_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

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
