import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/features/titles/consolidated_comments.dart';

CandidateTitle candidate(String id, String text,
        {int round = 1, int position = 0}) =>
    CandidateTitle(
      id: id, titleText: text, justificationPath: 'p',
      justificationUrl: 'u', round: round, position: position,
    );

TitleComment comment(String id, String titleId, String uid, String name,
        String role, String body, int minute) =>
    TitleComment(
      id: id, candidateTitleId: titleId, authorUid: uid, authorName: name,
      authorRole: role, body: body,
      createdAt: DateTime.utc(2026, 8, 16, 10, minute),
    );

void main() {
  test('groups each author into one block, in the order they first spoke', () {
    final result = consolidate(
      candidates: [candidate('ct1', 'Candidate one')],
      comments: [
        comment('1', 'ct1', 'a1', 'Dr. Armada', 'Adviser', 'Too broad.', 1),
        comment('2', 'ct1', 'p1', 'Dr. Diamante', 'Panel Member',
            'Justify the respondents.', 2),
        comment('3', 'ct1', 'a1', 'Dr. Armada', 'Adviser',
            'Narrow to one college.', 3),
      ],
    );

    expect(result, hasLength(1));
    final blocks = result.single.blocks;
    expect(blocks.map((b) => b.authorName), ['Dr. Armada', 'Dr. Diamante'],
        reason: 'ordered by who spoke first, not alphabetically');
    expect(blocks.first.bodies, ['Too broad.', 'Narrow to one college.'],
        reason: "an author's remarks stay in the order they were made");
    expect(blocks.first.authorRole, 'Adviser');
  });

  test('a candidate with no comments still appears, with no blocks', () {
    // Silence is a finding: the student should see that nobody objected.
    final result = consolidate(
      candidates: [candidate('ct1', 'One'), candidate('ct2', 'Two')],
      comments: [
        comment('1', 'ct1', 'a1', 'Dr. Armada', 'Adviser', 'Too broad.', 1),
      ],
    );
    expect(result, hasLength(2));
    expect(result[1].blocks, isEmpty);
  });

  test('comments are matched to their own candidate', () {
    final result = consolidate(
      candidates: [candidate('ct1', 'One'), candidate('ct2', 'Two')],
      comments: [
        comment('1', 'ct2', 'a1', 'Dr. Armada', 'Adviser', 'This one.', 1),
      ],
    );
    expect(result[0].blocks, isEmpty);
    expect(result[1].blocks.single.bodies, ['This one.']);
  });

  test('filtering by round shows one submission at a time', () {
    // A rejected set is kept. Showing both rounds at once would mix the
    // rejected candidates in with the resubmission.
    final result = consolidate(
      candidates: [
        candidate('old', 'Rejected', round: 1),
        candidate('new', 'Resubmitted', round: 2),
      ],
      comments: const [],
      round: 2,
    );
    expect(result.map((r) => r.candidate.id), ['new']);
  });

  test('the same person keeps the role they had on each comment', () {
    // Two comments, two roles, because a position changed between defences.
    // The blocks must not merge, or the record claims one of them was said
    // under the wrong title.
    final result = consolidate(
      candidates: [candidate('ct1', 'One')],
      comments: [
        comment('1', 'ct1', 'x1', 'Dr. Cruz', 'Panel Member', 'First.', 1),
        comment('2', 'ct1', 'x1', 'Dr. Cruz', 'Research Coordinator',
            'Second.', 2),
      ],
    );
    expect(result.single.blocks, hasLength(2));
    expect(result.single.blocks.map((b) => b.authorRole),
        ['Panel Member', 'Research Coordinator']);
  });
}
