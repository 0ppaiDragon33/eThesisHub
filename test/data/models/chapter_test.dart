// test/data/models/chapter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';

void main() {
  test('there are the five old chapters, then the two manuscripts', () {
    // The old ids come first and keep their order: records written before
    // manuscripts existed still read as they did.
    expect(ChapterId.values.map((c) => c.value), [
      'chapterI', 'chapterII', 'chapterIII', 'chapterIV', 'chapterV',
      'manuscriptProposal', 'manuscriptFinal',
    ]);
    expect(ChapterId.legacyChapters.length, 5);
    expect(ChapterId.manuscripts,
        [ChapterId.manuscriptProposal, ChapterId.manuscriptFinal]);
  });

  test('the manuscripts are named for the chapters they cover', () {
    expect(ChapterId.manuscriptProposal.label, 'Manuscript — Chapters I–III');
    expect(ChapterId.manuscriptFinal.label, 'Manuscript — Chapters I–V');
    expect(ChapterId.manuscriptProposal.mark, 'I–III');
    expect(ChapterId.manuscriptFinal.mark, 'I–V');
    expect(ChapterId.chapterII.mark, 'II');
    expect(ChapterId.chapterII.heading, 'Related Literature');
    expect(ChapterId.manuscriptFinal.heading, 'Manuscript — Chapters I–V');
  });

  test('only the full manuscript, and old IV and V, wait for the pre-oral',
      () {
    for (final id in ChapterId.values) {
      expect(
          id.needsPassedPreOral,
          const [ChapterId.chapterIV, ChapterId.chapterV,
                 ChapterId.manuscriptFinal].contains(id),
          reason: id.name);
    }
  });

  test('the legacy proposal gate is I-III and the final gate is all five',
      () {
    // For a thesis that uploaded chapter by chapter, before manuscripts.
    expect(ChapterId.proposalChapters,
        [ChapterId.chapterI, ChapterId.chapterII, ChapterId.chapterIII]);
    expect(ChapterId.finalChapters, ChapterId.legacyChapters);
  });

  group('manuscriptShelf: one manuscript at a time', () {
    test('before the pre-oral it is the Chapters I-III manuscript', () {
      final shelf = manuscriptShelf(preOralPassed: false);
      expect(shelf.current, ChapterId.manuscriptProposal);
      expect(shelf.earlier, isNull);
      expect(shelf.legacy, isEmpty);
    });

    test('after the pre-oral it is the Chapters I-V manuscript, and the '
        'proposal one is kept as earlier only if it was uploaded', () {
      expect(manuscriptShelf(preOralPassed: true).current,
          ChapterId.manuscriptFinal);
      expect(manuscriptShelf(preOralPassed: true).earlier, isNull);
      expect(
          manuscriptShelf(
              preOralPassed: true,
              uploaded: [ChapterId.manuscriptProposal]).earlier,
          ChapterId.manuscriptProposal);
    });

    test('a full manuscript already on file is current whatever the '
        'defenses say', () {
      expect(
          manuscriptShelf(
              preOralPassed: false,
              uploaded: [ChapterId.manuscriptFinal]).current,
          ChapterId.manuscriptFinal);
    });

    test('old per-chapter records are listed, in order, and only those '
        'that exist', () {
      final shelf = manuscriptShelf(
          preOralPassed: false,
          uploaded: [ChapterId.chapterIII, ChapterId.chapterI]);
      expect(shelf.legacy, [ChapterId.chapterI, ChapterId.chapterIII]);
      expect(shelf.current, ChapterId.manuscriptProposal);
    });
  });

  test('an unknown chapter id is null, not a silent default', () {
    // fromString must not fall back to chapterI: a typo would then write
    // Chapter III's file over Chapter I's record.
    expect(ChapterId.fromString('chapterVI'), isNull);
    expect(ChapterId.fromString(null), isNull);
    expect(ChapterId.fromString('chapterIII'), ChapterId.chapterIII);
  });

  test('a chapter parses its stored shape', () {
    final c = ThesisChapter.fromMap('chapterII', {
      'type': 'chapterII',
      'currentVersion': 3,
      'status': 'revise',
      'updatedAt': DateTime.utc(2026, 8, 21),
    });
    expect(c.id, ChapterId.chapterII);
    expect(c.currentVersion, 3);
    expect(c.status, ChapterStatus.revise);
    expect(c.updatedAt, DateTime.utc(2026, 8, 21));
  });

  test('an unknown chapter id throws rather than becoming Chapter I', () {
    // The failure this prevents is silent: a mislabelled chapter would
    // write one chapter's record over another's and look correct.
    expect(
      () => ThesisChapter.fromMap('chapterIX', {
        'type': 'chapterIX', 'currentVersion': 1, 'status': 'submitted',
      }),
      throwsArgumentError,
    );
  });

  test('an unknown status reads as submitted, never as approved', () {
    // The safe default is the one that grants nothing. Defaulting to
    // approved would let corrupt data unlock a defence.
    expect(ChapterStatus.fromString('nonsense'), ChapterStatus.submitted);
    expect(ChapterStatus.fromString(null), ChapterStatus.submitted);
  });

  test('a version and a piece of feedback parse their stored shapes', () {
    final v = ChapterVersion.fromMap({
      'version': 2,
      'storagePath': 'theses/t1/chapterI/uuid.pdf',
      'fileUrl': 'https://example.test/uuid.pdf',
      'uploadedBy': 'leader-uid',
      'uploadedAt': DateTime.utc(2026, 8, 21),
      'mimeType': 'application/pdf',
      'sizeBytes': 1024,
    });
    expect(v.version, 2);
    expect(v.sizeBytes, 1024);

    final f = ChapterFeedback.fromMap('fb1', {
      'version': 2,
      'reviewerUid': 'adviser-uid',
      'reviewerName': 'Dr. Armada',
      'reviewerRole': 'Adviser',
      'body': 'Tighten the problem statement.',
      'createdAt': DateTime.utc(2026, 8, 21),
    });
    expect(f.id, 'fb1');
    expect(f.version, 2);
    expect(f.body, 'Tighten the problem statement.');
  });
}
