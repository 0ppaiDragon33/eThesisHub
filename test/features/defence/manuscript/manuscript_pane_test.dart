import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_pane.dart';
import 'package:ethesishub/providers/service_providers.dart';

class _Storage implements StorageService {
  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String path) async {}

  @override
  Future<String> signedUrl(String path) async => 'https://example.test/$path';
}

const _channel = MethodChannel('plugins.flutter.io/url_launcher');

void main() {
  testWidgets('a launcher that throws is reported, not left to escape',
      (tester) async {
    // No app on the device can open the file: the launcher throws rather
    // than answering false.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async =>
            throw PlatformException(code: 'ACTIVITY_NOT_FOUND'));
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(ProviderScope(
      overrides: [storageServiceProvider.overrideWithValue(_Storage())],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              key: const Key('open'),
              onPressed: () => openChapterFile(
                context,
                ref,
                const ChapterVersion(
                  version: 1,
                  storagePath: 'theses/t1/chapterI/a.docx',
                  fileUrl: '',
                  uploadedBy: 'l1',
                  mimeType: 'application/msword',
                  sizeBytes: 4,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Could not open that file.'), findsOneWidget);
  });
}
