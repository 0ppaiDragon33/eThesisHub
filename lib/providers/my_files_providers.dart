import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/models/personal_file.dart';
import 'package:ethesishub/data/models/personal_folder.dart';
import 'package:ethesishub/data/repositories/my_files_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/form_copy_providers.dart';

final myFilesRepositoryProvider = Provider<MyFilesRepository>(
  (ref) => MyFilesRepository(ref.watch(firestoreProvider)),
);

// Each awaits the auth state rather than reading its current value: while
// auth is still settling that value is null, which would read as "nothing
// here" and flash an empty page (the race `currentUserProvider` avoids).

final myFoldersProvider =
    StreamProvider<List<PersonalFolder>>((ref) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(myFilesRepositoryProvider).watchFolders(user.uid);
});

final myPersonalFilesProvider =
    StreamProvider<List<PersonalFile>>((ref) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(myFilesRepositoryProvider).watchFiles(user.uid);
});

final myAllFormCopiesProvider = StreamProvider<List<FormCopy>>((ref) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref.watch(formCopyRepositoryProvider).watchAllCopies(user.uid);
});
