import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final facultyDirectoryRepositoryProvider =
    Provider<FacultyDirectoryRepository>(
  (ref) => FacultyDirectoryRepository(ref.watch(firestoreProvider)),
);

/// Every nominable directory entry — faculty, coordinators and the dean
/// alike. Backs the nomination pickers, which offer coordinators and the
/// dean as ordinary nominees "for the sake of records" even though they also
/// get an automatic ex-officio seat that nobody picks and nobody accepts.
final allDirectoryProvider = StreamProvider<List<FacultyDirectoryEntry>>((ref) {
  return ref.watch(facultyDirectoryRepositoryProvider).watchAllDirectory();
});

final thesisRepositoryProvider = Provider<ThesisRepository>(
  (ref) => ThesisRepository(ref.watch(firestoreProvider)),
);

/// The signed-in leader's thesis, or null if they have not created one.
final myThesisProvider = StreamProvider<Thesis?>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(thesisRepositoryProvider).watchThesisForLeader(uid);
});

/// Nominations awaiting this faculty member's Conforme, each paired with the
/// id of the thesis it belongs to so the inbox can act on it directly.
final myPendingNominationsProvider =
    StreamProvider<List<({String thesisId, Nomination nomination})>>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(thesisRepositoryProvider).watchMyPendingNominations(uid);
});
