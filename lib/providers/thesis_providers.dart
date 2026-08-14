import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final facultyDirectoryRepositoryProvider =
    Provider<FacultyDirectoryRepository>(
  (ref) => FacultyDirectoryRepository(ref.watch(firestoreProvider)),
);

/// Faculty a student may nominate. Excludes the dean and coordinators,
/// who sit on every panel ex officio.
final selectableFacultyProvider =
    StreamProvider<List<FacultyDirectoryEntry>>((ref) {
  return ref.watch(facultyDirectoryRepositoryProvider).watchSelectableFaculty();
});
