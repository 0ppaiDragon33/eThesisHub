import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';

/// What one chapter contributes to the defence manuscript.
enum ManuscriptPartKind {
  /// Approved, and its approved version is a PDF: its pages.
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
  });

  final ChapterId chapter;
  final ManuscriptPartKind kind;

  /// Set for [ManuscriptPartKind.pdf] and [ManuscriptPartKind.notPdf].
  final ChapterVersion? version;
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
List<ManuscriptPart> planManuscript({
  required DefenceType type,
  required List<ThesisChapter> chapters,
  required Map<ChapterId, ChapterVersion> approvedVersions,
}) {
  final byId = {for (final c in chapters) c.id: c};
  return [
    for (final id in manuscriptChapters(type))
      _partFor(id, byId[id], approvedVersions[id]),
  ];
}

ManuscriptPart _partFor(ChapterId id, ThesisChapter? c, ChapterVersion? v) {
  if (c == null) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.missing);
  }
  if (c.status != ChapterStatus.approved) {
    return ManuscriptPart(chapter: id, kind: ManuscriptPartKind.notApproved);
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
