import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/composing_indicator.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/title_comment.dart';

void main() {
  test('CandidateTitle round-trips from a Firestore map', () {
    final c = CandidateTitle.fromMap('ct1', {
      'titleText': 'A Web and Mobile-Based Thesis Management System',
      'justificationPath': 'theses/t1/ct1/uuid.pdf',
      'justificationUrl': 'https://example.test/uuid.pdf',
      'round': 1,
      'submittedAt': DateTime.utc(2026, 8, 16),
    });
    expect(c.id, 'ct1');
    expect(c.titleText, startsWith('A Web'));
    expect(c.round, 1);
    expect(c.submittedAt, DateTime.utc(2026, 8, 16));
  });

  test('TitleComment keeps the role held at the time of writing', () {
    // Resolving the role at render time would let a later promotion rewrite
    // history: someone who commented as a panel member would appear to have
    // commented as coordinator.
    final c = TitleComment.fromMap('cm1', {
      'candidateTitleId': 'ct1',
      'authorUid': 'p1',
      'authorName': 'Dr. Diamante',
      'authorRole': 'Panel Member',
      'body': 'Justify the choice of respondents.',
      'createdAt': DateTime.utc(2026, 8, 16, 10, 30),
    });
    expect(c.authorRole, 'Panel Member');
    expect(c.candidateTitleId, 'ct1');
    expect(c.createdAt, DateTime.utc(2026, 8, 16, 10, 30));
  });

  test('ComposingIndicator is stale after the freshness window', () {
    // There are no Cloud Functions to sweep these, so a laptop closed
    // mid-comment would leave an indicator up forever. Readers expire them.
    final now = DateTime.utc(2026, 8, 16, 10, 30);
    final fresh = ComposingIndicator.fromMap('p1', {
      'name': 'Dr. Diamante', 'role': 'Panel Member',
      'candidateTitleId': 'ct1',
      'updatedAt': now.subtract(const Duration(seconds: 5)),
    });
    final stale = ComposingIndicator.fromMap('p2', {
      'name': 'Dr. Padojinog', 'role': 'Panel Member',
      'candidateTitleId': 'ct1',
      'updatedAt': now.subtract(const Duration(seconds: 40)),
    });
    expect(fresh.isStaleAt(now), isFalse);
    expect(stale.isStaleAt(now), isTrue);
  });

  test('the new title states parse and are distinct', () {
    expect(ThesisStatus.fromString('titlePendingDefence'),
        ThesisStatus.titlePendingDefence);
    expect(ThesisStatus.fromString('titleApproved'),
        ThesisStatus.titleApproved);
    expect(ThesisStatus.fromString('titleRejected'),
        ThesisStatus.titleRejected);
  });

  test('Thesis reads the title-defence fields, and titleRound defaults to 0',
      () {
    // Theses created by M1a predate titleRound entirely.
    final old = Thesis.fromMap('t1', {
      'leaderUid': 'l1', 'memberNames': <String>[], 'workingTitle': 'T',
      'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
      'academicYear': '2026-2027', 'status': 'nominationApproved',
      'panelistUids': <String>[], 'createdAt': DateTime.utc(2026, 8, 1),
    });
    expect(old.titleRound, 0);
    expect(old.approvedTitleId, isNull);

    final current = Thesis.fromMap('t2', {
      'leaderUid': 'l1', 'memberNames': <String>[], 'workingTitle': 'T',
      'college': 'CICT', 'program': 'BSIT', 'semester': 'First',
      'academicYear': '2026-2027', 'status': 'titleApproved',
      'panelistUids': <String>[], 'createdAt': DateTime.utc(2026, 8, 1),
      'titleRound': 2, 'approvedTitleId': 'ct3',
      'titleDecidedBy': 'd1', 'titleDecidedAt': DateTime.utc(2026, 8, 16),
      'titleRejectionRemark': null,
      'presentationPath': 'theses/t2/pres/uuid.pptx',
      'presentationUrl': 'https://example.test/uuid.pptx',
      'titlesSubmittedAt': DateTime.utc(2026, 8, 15),
    });
    expect(current.titleRound, 2);
    expect(current.approvedTitleId, 'ct3');
    expect(current.titleDecidedBy, 'd1');
    expect(current.presentationUrl, contains('uuid.pptx'));
  });
}
