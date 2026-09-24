import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/form_copy.dart';
import 'package:ethesishub/data/repositories/form_copy_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final formCopyRepositoryProvider = Provider<FormCopyRepository>(
  (ref) => FormCopyRepository(ref.watch(firestoreProvider)),
);

/// The signed-in person's copies of one form (the family argument is the
/// form id), newest first.
///
/// Awaits the auth state rather than reading its current value: while auth
/// is still settling that value is null, which would read as "no copies"
/// and flash an empty list, the same race `currentUserProvider` avoids.
final myFormCopiesProvider =
    StreamProvider.family<List<FormCopy>, String>((ref, formId) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield const [];
    return;
  }
  yield* ref
      .watch(formCopyRepositoryProvider)
      .watchCopies(user.uid, formId: formId);
});

/// One of the signed-in person's copies (the family argument is the copy
/// id); null once deleted. Awaits auth for the same reason as above: a
/// copy that merely has not loaded yet must not read as "no longer exists".
final formCopyProvider =
    StreamProvider.family<FormCopy?, String>((ref, copyId) async* {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) {
    yield null;
    return;
  }
  yield* ref.watch(formCopyRepositoryProvider).watchCopy(user.uid, copyId);
});
