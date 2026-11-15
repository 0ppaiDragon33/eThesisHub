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

  // A group uploads one manuscript; approving it is the readiness signal.
  test('the approved Chapters I-III manuscript is ready for the pre-oral',
      () {
    expect(
      readinessOf([ch(ChapterId.manuscriptProposal, ChapterStatus.approved)]),
      DefenceReadiness.proposalReady,
    );
  });

  test('a manuscript under review is not ready', () {
    expect(
      readinessOf([ch(ChapterId.manuscriptProposal, ChapterStatus.submitted)]),
      DefenceReadiness.notReady,
    );
    expect(
      readinessOf([ch(ChapterId.manuscriptProposal, ChapterStatus.revise)]),
      DefenceReadiness.notReady,
    );
  });

  test('the approved Chapters I-V manuscript is ready for the final', () {
    expect(
      readinessOf([
        ch(ChapterId.manuscriptProposal, ChapterStatus.approved),
        ch(ChapterId.manuscriptFinal, ChapterStatus.approved),
      ]),
      DefenceReadiness.finalReady,
    );
  });

  // After the pre-oral the proposal manuscript is approved but the full one
  // is not: ready for the pre-oral it already had, not the final.
  test('the full manuscript still under review is not ready for the final',
      () {
    expect(
      readinessOf([
        ch(ChapterId.manuscriptProposal, ChapterStatus.approved),
        ch(ChapterId.manuscriptFinal, ChapterStatus.submitted),
      ]),
      DefenceReadiness.proposalReady,
    );
  });

  test('all five approved is ready for the final', () {
    expect(
      readinessOf([
        for (final id in ChapterId.legacyChapters)
          ch(id, ChapterStatus.approved),
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
