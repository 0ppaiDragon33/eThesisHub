import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/academic_term.dart';
import 'package:ethesishub/data/repositories/academic_term_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final academicTermRepositoryProvider = Provider<AcademicTermRepository>(
  (ref) => AcademicTermRepository(ref.watch(firestoreProvider)),
);

/// The college's current term, or null until the Coordinator sets one.
final currentTermProvider = StreamProvider<AcademicTerm?>((ref) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(academicTermRepositoryProvider).watchCurrent();
});
