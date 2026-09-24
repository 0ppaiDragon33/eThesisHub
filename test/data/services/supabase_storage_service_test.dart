import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/data/services/supabase_storage_service.dart';

/// functions_client 2.7.1 never returns a non-2xx [FunctionResponse] from
/// `invoke` — it throws a [FunctionException] instead. These tests exercise
/// [SupabaseStorageService] against a real [SupabaseClient] whose HTTP layer
/// is a [MockClient], so the refusal comes from the same code path a device
/// hits: through `functions.invoke` throwing, not a hand-built response.
void main() {
  SupabaseClient buildClient(http.Client mockHttp) => SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: mockHttp,
      );

  MockFirebaseAuth buildAuth() => MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1', email: 'u1@isufst.edu.ph'),
      );

  http.Response jsonRefusal(int status, String error) => http.Response(
        jsonEncode({'error': error}),
        status,
        headers: {'content-type': 'application/json'},
      );

  test(
      'deletePersonal throws the personal-forbidden StorageFailure on a '
      '403 refusal', () async {
    final mockHttp = MockClient((request) async => jsonRefusal(403, 'forbidden'));
    final service = SupabaseStorageService(buildClient(mockHttp), buildAuth());

    await expectLater(
      service.deletePersonal('personal/u1/f1/x.png'),
      throwsA(
        isA<StorageFailure>()
            .having((e) => e.code, 'code', 'storage-forbidden')
            .having(
              (e) => e.message,
              'message',
              'Only the person who added this file can open or delete it.',
            ),
      ),
    );
  });

  test('signedUrl on a thesis path keeps the existing thesis 403 message',
      () async {
    final mockHttp = MockClient((request) async => jsonRefusal(403, 'forbidden'));
    final service = SupabaseStorageService(buildClient(mockHttp), buildAuth());

    await expectLater(
      service.signedUrl('theses/t1/chapters/c1/v1.pdf'),
      throwsA(
        isA<StorageFailure>()
            .having((e) => e.code, 'code', 'storage-forbidden')
            .having(
              (e) => e.message,
              'message',
              'You do not have access to this document. Only the group, '
                  'their adviser, the panel and the research office can '
                  'open it.',
            ),
      ),
    );
  });
}
