import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

typedef ManuscriptKey = ({String thesisId, DefenceType type});

/// The defence manuscript's chapters, each with what it shows. Loading until
/// every approved chapter's versions have arrived, so a chapter is never
/// shown as missing when it is merely still loading.
final manuscriptPartsProvider = Provider.autoDispose
    .family<AsyncValue<List<ManuscriptPart>>, ManuscriptKey>((ref, key) {
  final chaptersAsync = ref.watch(chaptersProvider(key.thesisId));
  if (chaptersAsync.hasError) {
    return AsyncValue.error(
        chaptersAsync.error!, chaptersAsync.stackTrace ?? StackTrace.current);
  }
  final chapters = chaptersAsync.valueOrNull;
  if (chapters == null) return const AsyncValue.loading();

  final wanted = manuscriptChapters(key.type);
  final approved = [
    for (final c in chapters)
      if (wanted.contains(c.id) && c.status == ChapterStatus.approved) c,
  ];
  // Watch every one before deciding, so they load side by side.
  final versionsAsync = {
    for (final c in approved)
      c.id: ref.watch(
          chapterVersionsProvider((thesisId: key.thesisId, chapter: c.id))),
  };

  final approvedVersions = <ChapterId, ChapterVersion>{};
  for (final c in approved) {
    final v = versionsAsync[c.id]!;
    if (v.hasError) {
      return AsyncValue.error(v.error!, v.stackTrace ?? StackTrace.current);
    }
    final list = v.valueOrNull;
    if (list == null) return const AsyncValue.loading();
    for (final version in list) {
      if (version.version == c.currentVersion) {
        approvedVersions[c.id] = version;
        break;
      }
    }
  }
  return AsyncValue.data(planManuscript(
    type: key.type,
    chapters: chapters,
    approvedVersions: approvedVersions,
  ));
});

/// Fetches a stored file's bytes: a fresh signed URL (the bucket is
/// private), then the download.
typedef ChapterFileLoader = Future<Uint8List> Function(String storagePath);

final chapterFileLoaderProvider = Provider<ChapterFileLoader>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return (path) async {
    final url = await storage.signedUrl(path);
    http.Response res;
    try {
      res = await http.get(Uri.parse(url));
    } catch (_) {
      throw const StorageFailure(
        'Could not download this chapter. Check the connection and open the '
        'room again.',
        code: 'storage-download',
      );
    }
    if (res.statusCode != 200) {
      throw StorageFailure(
        'Could not download this chapter. The server answered '
        '${res.statusCode}.',
        code: 'storage-download',
      );
    }
    return res.bodyBytes;
  };
});

/// Draws PDF pages. An interface so widget tests can draw without `printing`.
abstract interface class ManuscriptRasterizer {
  /// Every page's size, in any unit: only the shape is used.
  Future<List<Size>> pageSizes(Uint8List pdf);

  /// One page as an image; the caller disposes it.
  Future<ui.Image> renderPage(Uint8List pdf, int index);
}

class PrintingManuscriptRasterizer implements ManuscriptRasterizer {
  const PrintingManuscriptRasterizer();

  /// Tiny: this pass only learns how many pages there are and their shape.
  static const double probeDpi = 12;

  /// Readable at the viewer's largest zoom on a laptop, and one page at a
  /// time, so a long chapter is never held in memory whole.
  static const double pageDpi = 150;

  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async {
    final sizes = <Size>[];
    await for (final page in Printing.raster(pdf, dpi: probeDpi)) {
      sizes.add(Size(page.width.toDouble(), page.height.toDouble()));
    }
    return sizes;
  }

  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) async {
    final page =
        await Printing.raster(pdf, pages: [index], dpi: pageDpi).first;
    return page.toImage();
  }
}

final manuscriptRasterizerProvider = Provider<ManuscriptRasterizer>(
    (ref) => const PrintingManuscriptRasterizer());

/// One chapter's file, downloaded and measured.
class ChapterPdf {
  const ChapterPdf({required this.bytes, required this.pageSizes});

  final Uint8List bytes;
  final List<Size> pageSizes;
}

/// Keyed by storage path, which is unique per version, so a re-approved
/// chapter is fetched afresh. Auto-disposed: a closed room frees the bytes.
final chapterPdfProvider = FutureProvider.autoDispose
    .family<ChapterPdf, String>((ref, storagePath) async {
  final bytes = await ref.watch(chapterFileLoaderProvider)(storagePath);
  final sizes = await ref.watch(manuscriptRasterizerProvider).pageSizes(bytes);
  if (sizes.isEmpty) {
    throw const StorageFailure(
      "This chapter's PDF has no pages that can be shown.",
      code: 'pdf-empty',
    );
  }
  return ChapterPdf(bytes: bytes, pageSizes: sizes);
});
