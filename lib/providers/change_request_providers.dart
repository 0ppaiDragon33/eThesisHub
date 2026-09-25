import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/repositories/change_request_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final changeRequestRepositoryProvider = Provider<ChangeRequestRepository>(
  (ref) => ChangeRequestRepository(ref.watch(firestoreProvider)),
);
