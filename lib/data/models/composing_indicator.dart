/// A marker that someone is currently writing a comment.
///
/// Transient by design: the client deletes it on submit or blur. But a laptop
/// closed mid-comment leaves one behind, and there are no Cloud Functions on
/// the Spark plan to sweep it up — so readers expire them instead. The
/// leftover document is harmless and hides itself.
class ComposingIndicator {
  const ComposingIndicator({
    required this.uid,
    required this.name,
    required this.role,
    required this.candidateTitleId,
    this.updatedAt,
  });

  /// How long an indicator stays believable. The client refreshes roughly
  /// every 5 seconds, so 15 tolerates a missed beat without lingering.
  static const staleAfter = Duration(seconds: 15);

  final String uid;
  final String name;
  final String role;
  final String candidateTitleId;
  final DateTime? updatedAt;

  bool isStaleAt(DateTime now) {
    final at = updatedAt;
    if (at == null) return true;
    return now.difference(at) > staleAfter;
  }

  factory ComposingIndicator.fromMap(String uid, Map<String, dynamic> map) {
    return ComposingIndicator(
      uid: uid,
      name: map['name'] as String? ?? '',
      role: map['role'] as String? ?? '',
      candidateTitleId: map['candidateTitleId'] as String? ?? '',
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}
