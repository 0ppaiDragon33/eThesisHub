import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/data/services/audit_service.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/data/services/supabase_storage_service.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final storageServiceProvider = Provider<StorageService>(
  (ref) => SupabaseStorageService(ref.watch(supabaseClientProvider)),
);

final auditServiceProvider = Provider<AuditService>(
  (ref) => AuditService(ref.watch(firestoreProvider)),
);
