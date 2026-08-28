import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Every account in the college.
///
/// Watched ONLY by the coordinator's Users screen (and the dean's, once it
/// exists). The rules deny `list` on `users` to every other role, so
/// watching this from any other screen surfaces a `permission-denied` the
/// reader cannot act on.
final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  // Rebuilt on a change of user: see [signedInUidProvider].
  ref.watch(signedInUidProvider);
  return ref.watch(userRepositoryProvider).watchAllUsers();
});
