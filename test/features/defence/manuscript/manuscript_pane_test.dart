import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/core/widgets/open_document.dart';
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

void main() {
  // An old Word upload cannot be drawn in the manuscript. It opens in the
  // viewer, which says so, and Download hands it to the device.
  testWidgets('an old Word file opens in the viewer, not straight out of the '
      'app', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(_app(opened: opened, result: true));

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documentViewer')), findsOneWidget);
    expect(find.byKey(const Key('noPreview')), findsOneWidget);
    expect(opened, isEmpty, reason: 'nothing leaves the app until Download');

    await tester.tap(find.byKey(const Key('downloadDocument')));
    await tester.pumpAndSettle();
    expect(opened.map((u) => u.toString()),
        ['https://example.test/theses/t1/chapterI/a.docx']);
  });

  testWidgets('a device that cannot open it is told so, not left to escape',
      (tester) async {
    // No app on the device can open the file.
    await tester.pumpWidget(_app(opened: <Uri>[], result: false));

    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('downloadDocument')));
    await tester.pumpAndSettle();

    expect(find.text('Could not open that file.'), findsOneWidget);
  });
}

Widget _app({required List<Uri> opened, required bool result}) {
  return ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(_Storage()),
      externalOpenerProvider.overrideWithValue((url) async {
        opened.add(url);
        return result;
      }),
    ],
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
  );
}
