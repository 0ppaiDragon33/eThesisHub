import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

typedef ManuscriptKey = ({String defenceId, String thesisId, DefenceType type});

/// The defence manuscript's chapters, each with what it shows. Loading until
/// every approved chapter's versions have arrived, so a chapter is never
/// shown as missing when it is merely still loading.
///
/// Also reads this defence's highlights: a chapter reopened for revision
/// after the defence still shows the version the panel marked (see
/// [planManuscript]), and that needs to know which versions they are on.
final manuscriptPartsProvider = Provider.autoDispose
    .family<AsyncValue<List<ManuscriptPart>>, ManuscriptKey>((ref, key) {
  final chaptersAsync = ref.watch(chaptersProvider(key.thesisId));
  final annotationsAsync = ref.watch(defenceAnnotationsProvider(key.defenceId));
  if (chaptersAsync.hasError) {
    return AsyncValue.error(
        chaptersAsync.error!, chaptersAsync.stackTrace ?? StackTrace.current);
  }
  final chapters = chaptersAsync.valueOrNull;
  if (chapters == null) return const AsyncValue.loading();
  // Unreadable highlights mark nothing: the chapters still show as they are.
  final annotations = annotationsAsync.hasError
      ? const <DefenceAnnotation>[]
      : annotationsAsync.valueOrNull;
  if (annotations == null) return const AsyncValue.loading();

  final wanted = manuscriptChapters(key.type);
  final approved = [
    for (final c in chapters)
      if (wanted.contains(c.id) && c.status == ChapterStatus.approved) c,
  ];
  final markedNumbers = <ChapterId, Set<int>>{};
  for (final a in annotations) {
    (markedNumbers[a.chapter] ??= <int>{}).add(a.version);
  }
  final reopened = [
    for (final c in chapters)
      if (wanted.contains(c.id) &&
          c.status != ChapterStatus.approved &&
          markedNumbers.containsKey(c.id))
        c,
  ];
  // Watch every one before deciding, so they load side by side.
  final versionsAsync = {
    for (final c in [...approved, ...reopened])
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

  final markedVersions = <ChapterId, List<ChapterVersion>>{};
  for (final c in reopened) {
    final v = versionsAsync[c.id]!;
    // Unreadable: the chapter keeps its not-approved placeholder.
    if (v.hasError) continue;
    final list = v.valueOrNull;
    if (list == null) return const AsyncValue.loading();
    markedVersions[c.id] = [
      for (final version in list)
        if (markedNumbers[c.id]!.contains(version.version)) version,
    ];
  }

  return AsyncValue.data(planManuscript(
    type: key.type,
    chapters: chapters,
    approvedVersions: approvedVersions,
    markedVersions: markedVersions,
  ));
});

/// Fetches a stored file's bytes: a fresh signed URL (the bucket is
/// private), then the download.
typedef ChapterFileLoader = Future<Uint8List> Function(String storagePath);

final chapterFileLoaderProvider = Provider<ChapterFileLoader>((ref) {
  final storage = ref.watch(storageServiceProvider);
  return (path) async {
    final url = await storage.signedUrl(path);
    return downloadChapterBytes(() => http.get(Uri.parse(url)));
  };
});

/// How long a chapter download may take before the reader is offered
/// Try again instead of a spinner that never ends.
const kChapterDownloadTimeout = Duration(seconds: 60);

/// Runs [request] and returns the body, or a [StorageFailure] the manuscript
/// can show: no connection, no answer within [timeout], or an error status.
Future<Uint8List> downloadChapterBytes(
  Future<http.Response> Function() request, {
  Duration timeout = kChapterDownloadTimeout,
}) async {
  http.Response res;
  try {
    res = await request().timeout(timeout);
  } catch (_) {
    // Also a TimeoutException: to the reader, both are a failed download.
    throw const StorageFailure(
      'Could not download this chapter. Check the connection and try again.',
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
}

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
