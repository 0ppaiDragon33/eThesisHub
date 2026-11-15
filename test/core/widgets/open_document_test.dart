import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/widgets/open_document.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/providers/service_providers.dart';

class _Storage implements StorageService {
  _Storage({this.failure});

  final StorageFailure? failure;
  final asked = <String>[];

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
  Future<String> signedUrl(String path) async {
    asked.add(path);
    if (failure != null) throw failure!;
    return 'https://example.test/$path';
  }
}

class _Spy {
  final fetched = <Uri>[];
  final shared = <String>[];
  final opened = <Uri>[];
  bool openerResult = true;
}

/// A button that opens [path]; the platform pieces (rasterising a PDF,
/// the network, the share sheet, the launcher) are replaced by stand-ins.
Future<void> _pump(
  WidgetTester tester,
  _Storage storage,
  _Spy spy, {
  required String path,
  String? label,
}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      storageServiceProvider.overrideWithValue(storage),
      storedDocumentBytesProvider.overrideWithValue((url) async {
        spy.fetched.add(url);
        return Uint8List.fromList([1, 2, 3]);
      }),
      formPreviewBuilderProvider.overrideWithValue((build) {
        // Drive the build so the bytes really are asked for.
        build();
        return const Text('document pages', key: Key('stubPreview'));
      }),
      pdfSharerProvider.overrideWithValue((bytes, filename) async {
        spy.shared.add(filename);
      }),
      externalOpenerProvider.overrideWithValue((url) async {
        spy.opened.add(url);
        return spy.openerResult;
      }),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            key: const Key('open'),
            onPressed: () =>
                openStoredDocument(context, ref, path, label: label),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  group('a PDF opens in the viewer, previewed first', () {
    testWidgets('the preview is drawn and nothing is downloaded yet',
        (tester) async {
      final storage = _Storage();
      final spy = _Spy();
      await _pump(tester, storage, spy,
          path: 'theses/t1/manuscript/abc.pdf', label: 'Final manuscript');

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documentViewer')), findsOneWidget);
      expect(find.byKey(const Key('stubPreview')), findsOneWidget);
      expect(find.text('Final manuscript'), findsOneWidget);
      // The file was read to draw it, and was not handed to the device or
      // saved: that waits for the reader to press Download.
      expect(spy.fetched.map((u) => u.toString()),
          ['https://example.test/theses/t1/manuscript/abc.pdf']);
      expect(spy.shared, isEmpty);
      expect(spy.opened, isEmpty);
    });

    testWidgets('Download, on the preview, saves it under a sensible name',
        (tester) async {
      final spy = _Spy();
      await _pump(tester, _Storage(), spy,
          path: 'theses/t1/manuscript/abc.pdf', label: 'Final manuscript');
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('downloadDocument')));
      await tester.pumpAndSettle();

      // The storage path never carries the person's filename, so the label
      // stands in, and the extension comes from the path.
      expect(spy.shared, ['Final manuscript.pdf']);
    });

    testWidgets('closing the viewer returns to where the reader was',
        (tester) async {
      await _pump(tester, _Storage(), _Spy(),
          path: 'theses/t1/manuscript/abc.pdf');
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('closeDocumentViewer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documentViewer')), findsNothing);
      expect(find.byKey(const Key('open')), findsOneWidget);
    });
  });

  group('a file the app cannot draw says so and downloads from there', () {
    for (final ext in ['pptx', 'docx']) {
      testWidgets('.$ext is not previewed; Download hands it to the device',
          (tester) async {
        final spy = _Spy();
        await _pump(tester, _Storage(), spy,
            path: 'theses/t1/presentation/abc.$ext', label: 'Presentation');

        await tester.tap(find.byKey(const Key('open')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('documentViewer')), findsOneWidget);
        expect(find.byKey(const Key('noPreview')), findsOneWidget);
        expect(find.textContaining('.${ext.toUpperCase()}'), findsOneWidget);
        expect(find.byKey(const Key('stubPreview')), findsNothing);
        // Nothing is fetched to draw what cannot be drawn.
        expect(spy.fetched, isEmpty);
        expect(spy.opened, isEmpty);

        await tester.tap(find.byKey(const Key('downloadDocument')));
        await tester.pumpAndSettle();

        expect(spy.opened.map((u) => u.toString()),
            ['https://example.test/theses/t1/presentation/abc.$ext']);
      });
    }

    testWidgets('a device that cannot open it says so, inside the viewer',
        (tester) async {
      final spy = _Spy()..openerResult = false;
      await _pump(tester, _Storage(), spy,
          path: 'theses/t1/presentation/abc.pptx');
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('downloadDocument')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documentViewerError')), findsOneWidget);
      expect(find.text('Could not open that file.'), findsOneWidget);
    });
  });

  group('a document that may not be opened never reaches the viewer', () {
    testWidgets('a refused link is reported and no viewer opens',
        (tester) async {
      final storage =
          _Storage(failure: const StorageFailure('Not allowed.', code: 'x'));
      await _pump(tester, storage, _Spy(),
          path: 'theses/t1/manuscript/abc.pdf');

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(storage.asked, ['theses/t1/manuscript/abc.pdf']);
      expect(find.byKey(const Key('documentViewer')), findsNothing);
      expect(find.text('Not allowed. [x]'), findsOneWidget);
    });

    testWidgets('an entry with no stored path says so', (tester) async {
      final storage = _Storage();
      await _pump(tester, storage, _Spy(), path: '  ');

      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();

      expect(storage.asked, isEmpty);
      expect(find.byKey(const Key('documentViewer')), findsNothing);
      expect(find.textContaining('does not record where its file'),
          findsOneWidget);
    });
  });

  group('downloadNameFor', () {
    test('takes the extension from the path and the name from the label', () {
      expect(downloadNameFor('a/b/uuid.pdf', 'Final manuscript'),
          'Final manuscript.pdf');
      expect(downloadNameFor('a/b/uuid.PPTX', 'The presentation'),
          'The presentation.pptx');
    });

    test('does not double an extension the label already has', () {
      expect(downloadNameFor('a/b/uuid.pdf', 'Thesis.pdf'), 'Thesis.pdf');
    });

    test('drops characters a filename cannot carry, and falls back',
        () {
      expect(downloadNameFor('a/b/uuid.pdf', 'Version 2: "final"/draft'),
          'Version 2 finaldraft.pdf');
      expect(downloadNameFor('a/b/uuid.pdf', null), 'document.pdf');
      expect(downloadNameFor('a/b/uuid', '???'), 'document');
    });
  });
}
