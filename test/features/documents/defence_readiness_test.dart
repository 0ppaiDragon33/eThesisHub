import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/defence_readiness.dart';

ThesisChapter ch(ChapterId id, ChapterStatus s) =>
    ThesisChapter(id: id, currentVersion: 1, status: s);

void main() {
  test('nothing approved is not ready', () {
    expect(readinessOf([ch(ChapterId.chapterI, ChapterStatus.submitted)]),
        DefenceReadiness.notReady);
  });

  test('chapters I-III approved is ready for the pre-oral', () {
    expect(
      readinessOf([
        ch(ChapterId.chapterI, ChapterStatus.approved),
        ch(ChapterId.chapterII, ChapterStatus.approved),
        ch(ChapterId.chapterIII, ChapterStatus.approved),
      ]),
      DefenceReadiness.proposalReady,
    );
  });

  test('two of the three is NOT ready', () {
    // The gate is all three. A partial set that read as ready would put a
    // group in front of a panel with a chapter nobody had approved.
    expect(
      readinessOf([
        ch(ChapterId.chapterI, ChapterStatus.approved),
        ch(ChapterId.chapterII, ChapterStatus.approved),
        ch(ChapterId.chapterIII, ChapterStatus.revise),
      ]),
      DefenceReadiness.notReady,
    );
  });

  test('all five approved is ready for the final', () {
    expect(
      readinessOf([
        for (final id in ChapterId.values) ch(id, ChapterStatus.approved),
      ]),
      DefenceReadiness.finalReady,
    );
  });

  test('a missing chapter counts as not approved', () {
    // Absence is how "not started" is represented, so an empty list must
    // never satisfy a gate by vacuous truth.
    expect(readinessOf(const []), DefenceReadiness.notReady);
  });
}
