import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/title_comment.dart';

/// One commenter's remarks on one candidate, as a single bracketed block:
///
/// ```
/// [Dr. Noel A. Armada — Adviser]
///   Scope is too broad for one semester.
///   Narrow the respondents to one college.
/// ```
class CommentBlock {
  const CommentBlock({
    required this.authorName,
    required this.authorRole,
    required this.bodies,
  });

  final String authorName;
  final String authorRole;
  final List<String> bodies;

  /// The bracket header, exactly as it prints.
  String get header => '[$authorName — $authorRole]';
}

class ConsolidatedCandidate {
  const ConsolidatedCandidate({required this.candidate, required this.blocks});
  final CandidateTitle candidate;
  final List<CommentBlock> blocks;
}

/// Groups comments per commenter under each candidate — parent design §5.3.
///
/// This is what a student reads after the Dean records the decision, and what
/// automates Guidelines §4d, where the adviser consolidates defence comments
/// for the Research Coordinator. Built here; M3 reuses it for the pre-oral
/// and final defences.
///
/// Ordering is the record: candidates in the order given, authors in the
/// order they first commented, and each author's remarks in the order made.
/// Alphabetising anything here would misrepresent a transcript.
///
/// Blocks are keyed by author AND role. The same person commenting under two
/// different positions gets two blocks, because merging them would file a
/// remark under a title its author did not hold at the time.
List<ConsolidatedCandidate> consolidate({
  required List<CandidateTitle> candidates,
  required List<TitleComment> comments,
  int? round,
}) {
  final shown = round == null
      ? candidates
      : candidates.where((c) => c.round == round).toList();

  return [
    for (final c in shown)
      ConsolidatedCandidate(
        candidate: c,
        blocks: _blocksFor(
            comments.where((m) => m.candidateTitleId == c.id).toList()),
      ),
  ];
}

List<CommentBlock> _blocksFor(List<TitleComment> comments) {
  final order = <String>[];
  final grouped = <String, List<TitleComment>>{};

  for (final c in comments) {
    final key = '${c.authorUid}|${c.authorRole}';
    if (!grouped.containsKey(key)) {
      order.add(key);
      grouped[key] = [];
    }
    grouped[key]!.add(c);
  }

  return [
    for (final key in order)
      CommentBlock(
        authorName: grouped[key]!.first.authorName,
        authorRole: grouped[key]!.first.authorRole,
        bodies: grouped[key]!.map((c) => c.body).toList(),
      ),
  ];
}
