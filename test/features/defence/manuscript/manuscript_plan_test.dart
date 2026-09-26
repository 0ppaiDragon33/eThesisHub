import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';

ThesisChapter chapter(ChapterId id, ChapterStatus status, {int current = 1}) =>
    ThesisChapter(id: id, currentVersion: current, status: status);

ChapterVersion version(int n,
        {String mime = 'application/pdf', String path = 'theses/t1/c/a.pdf'}) =>
    ChapterVersion(
      version: n,
      storagePath: path,
      fileUrl: '',
      uploadedBy: 'l1',
      mimeType: mime,
      sizeBytes: 4,
    );

DefenceAnnotation note(ChapterId c, int v) => DefenceAnnotation(
      id: 'h',
      authorUid: 'p1',
      authorName: 'P',
      authorPosition: 'Panel Member',
      chapter: c,
      version: v,
      page: 0,
      rect: const NormRect(x: 0, y: 0, w: 0.5, h: 0.5),
      body: 'b',
    );

void main() {
  test('a pre-oral shows Chapters I to III, a final I to V', () {
    expect(manuscriptChapters(DefenceType.preOral),
        [ChapterId.chapterI, ChapterId.chapterII, ChapterId.chapterIII]);
    expect(manuscriptChapters(DefenceType.final_), ChapterId.values);
  });

  test('numerals', () {
    expect(ChapterId.values.map(chapterNumeral),
        ['I', 'II', 'III', 'IV', 'V']);
  });

  test('each chapter shows its pages or says why not', () {
    final parts = planManuscript(
      type: DefenceType.final_,
      chapters: [
        chapter(ChapterId.chapterI, ChapterStatus.approved, current: 2),
        chapter(ChapterId.chapterII, ChapterStatus.revise),
        chapter(ChapterId.chapterIII, ChapterStatus.approved),
        chapter(ChapterId.chapterV, ChapterStatus.approved),
      ],
      approvedVersions: {
        ChapterId.chapterI: version(2),
        ChapterId.chapterIII: version(1,
            mime: 'application/vnd.openxmlformats-officedocument'
                '.wordprocessingml.document',
            path: 'theses/t1/c/a.docx'),
      },
    );
    expect(parts.map((p) => p.kind), [
      ManuscriptPartKind.pdf,
      ManuscriptPartKind.notApproved,
      ManuscriptPartKind.notPdf,
      ManuscriptPartKind.missing, // IV was never uploaded
      ManuscriptPartKind.missing, // V approved, but its version is unreadable
    ]);
    expect(parts.first.version!.version, 2);
    expect(parts[2].version, isNotNull);
  });

  test('a PDF is recognised by its type or, failing that, its name', () {
    expect(isPdfVersion(version(1)), isTrue);
    expect(isPdfVersion(version(1, mime: 'application/octet-stream')),
        isTrue);
    expect(
        isPdfVersion(version(1,
            mime: 'application/msword', path: 'theses/t1/c/a.doc')),
        isFalse);
  });

  test('a highlight is current only on the version the manuscript shows', () {
    final parts = planManuscript(
      type: DefenceType.preOral,
      chapters: [
        chapter(ChapterId.chapterI, ChapterStatus.approved, current: 3),
      ],
      approvedVersions: {ChapterId.chapterI: version(3)},
    );
    expect(isOnCurrentVersion(note(ChapterId.chapterI, 3), parts), isTrue);
    expect(isOnCurrentVersion(note(ChapterId.chapterI, 2), parts), isFalse);
    expect(isOnCurrentVersion(note(ChapterId.chapterII, 1), parts), isFalse);
  });
}
