/// One remark a panel member made about one candidate title.
///
/// Append-only: there is no edit and no delete, in the rules or here. The
/// consolidated output a student eventually reads is therefore a record of
/// what was said, not a summary anyone tidied afterwards.
class TitleComment {
  const TitleComment({
    required this.id,
    required this.candidateTitleId,
    required this.authorUid,
    required this.authorName,
    required this.authorRole,
    required this.body,
    this.createdAt,
  });

  final String id;
  final String candidateTitleId;
  final String authorUid;
  final String authorName;

  /// The position this person held WHEN THEY WROTE IT — "Adviser", "Panel
  /// Member", "Research Coordinator", "Dean". Stored rather than resolved at
  /// render time, so a later change of position cannot rewrite the header on
  /// a remark made months earlier.
  final String authorRole;

  final String body;
  final DateTime? createdAt;

  factory TitleComment.fromMap(String id, Map<String, dynamic> map) {
    return TitleComment(
      id: id,
      candidateTitleId: map['candidateTitleId'] as String? ?? '',
      authorUid: map['authorUid'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      authorRole: map['authorRole'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: map['createdAt'] as DateTime?,
    );
  }
}
