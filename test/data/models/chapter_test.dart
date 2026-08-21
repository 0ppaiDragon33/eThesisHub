// test/data/models/chapter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';

void main() {
  test('there are exactly five chapters, in order', () {
    expect(ChapterId.values.map((c) => c.value), [
      'chapterI', 'chapterII', 'chapterIII', 'chapterIV', 'chapterV',
    ]);
  });

  test('the proposal gate is I-III and the final gate is all five', () {
    // Pre-oral covers the proposal; the final defence adds Results and
    // Conclusions. Two readiness signals from the same five documents.
    expect(ChapterId.proposalChapters,
        [ChapterId.chapterI, ChapterId.chapterII, ChapterId.chapterIII]);
    expect(ChapterId.finalChapters, ChapterId.values);
  });

  test('an unknown chapter id is null, not a silent default', () {
    // fromString must NOT fall back to chapterI: a typo would then write
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
