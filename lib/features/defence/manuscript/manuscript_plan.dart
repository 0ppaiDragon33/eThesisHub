import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';

/// What one chapter contributes to the defence manuscript.
enum ManuscriptPartKind {
  /// Its pages: the approved version when approved and a PDF, or, for a
  /// chapter reopened after the defence, the version the panel marked.
  pdf,

  /// Uploaded but not approved: one placeholder page.
  notApproved,

  /// Approved, but uploaded as a Word file before chapters became
  /// PDF-only: a placeholder with an Open file button.
  notPdf,

  /// Never uploaded, or its version record cannot be read.
  missing,
}

class ManuscriptPart {
  const ManuscriptPart({
    required this.chapter,
    required this.kind,
    this.version,
    this.reopened = false,
  });

  final ChapterId chapter;
  final ManuscriptPartKind kind;

  /// Set for [ManuscriptPartKind.pdf] and [ManuscriptPartKind.notPdf].
  final ChapterVersion? version;

  /// No longer approved (reopened for revision after the defence), so
  /// [version] is the one this defence's highlights were drawn on rather
  /// than an approved one.
  final bool reopened;
}

/// The chapters a defence of [type] is about. A re-defence has the same
/// type as the defence it re-does, so it shows the same chapters.
List<ChapterId> manuscriptChapters(DefenceType type) =>
    type == DefenceType.preOral
        ? ChapterId.proposalChapters
        : ChapterId.finalChapters;

String chapterNumeral(ChapterId c) =>
    const ['I', 'II', 'III', 'IV', 'V'][c.index];

bool isPdfVersion(ChapterVersion v) =>
    v.mimeType == 'application/pdf' ||
    v.storagePath.toLowerCase().endsWith('.pdf');

/// The manuscript, chapter by chapter. [approvedVersions] holds, for each
/// approved chapter, the version whose number is its `currentVersion` — an
/// approved chapter cannot take a new upload, so that is the approved one.
///
/// [markedVersions] holds, for each chapter, the version records this
/// defence's highlights are drawn on. A chapter reopened for revision after
/// the defence is no longer approved, but the panel's marks must still be
/// readable, so it shows the highest of those that is a PDF.
List<ManuscriptPart> planManuscript({
  required DefenceType type,
  required List<ThesisChapter> chapters,
  required Map<ChapterId, ChapterVersion> approvedVersions,
  Map<ChapterId, List<ChapterVersion>> markedVersions = const {},
}) {
  final byId = {for (final c in chapters) c.id: c};
  return [
    for (final id in manuscriptChapters(type))
      _partFor(id, byId[id], approvedVersions[id],
          markedVersions[id] ?? const []),
  ];
}

ManuscriptPart _partFor(
  ChapterId id,
  ThesisChapter? c,
  ChapterVersion? v,
  List<ChapterVersion> marked,
) {
  if (c == null) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.missing);
  }
  if (c.status != ChapterStatus.approved) {
    ChapterVersion? shown;
    for (final m in marked) {
      if (isPdfVersion(m) && (shown == null || m.version > shown.version)) {
        shown = m;
      }
    }
    if (shown == null) {
      return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.notApproved);
    }
    return ManuscriptPart(
      chapter: id,
      kind: ManuscriptPartKind.pdf,
      version: shown,
      reopened: true,
    );
  }
  if (v == null) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.missing);
  }
  if (!isPdfVersion(v)) {
    return ManuscriptPart(
        chapter: id, kind: ManuscriptPartKind.notPdf, version: v);
  }
  return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.pdf, version: v);
}

/// Whether [a] sits on the chapter version the manuscript shows now. One
/// drawn before the chapter was reopened and re-approved does not, and is
/// listed as being on an earlier version instead of drawn on the wrong page.
bool isOnCurrentVersion(DefenceAnnotation a, List<ManuscriptPart> parts) =>
    parts.any((p) =>
        p.chapter == a.chapter &&
        p.kind == ManuscriptPartKind.pdf &&
        p.version?.version == a.version);
