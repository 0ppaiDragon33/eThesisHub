import 'package:ethesishub/data/models/composing_indicator.dart';

/// Where in the defence room someone is writing.
enum ComposingTarget {
  /// The room comment box.
  room,

  /// A highlight's comment.
  manuscript;

  String get value => name;

  static ComposingTarget fromString(String? raw) =>
      raw == 'manuscript' ? ComposingTarget.manuscript : ComposingTarget.room;
}

/// "Someone is typing" in a defence room: [ComposingIndicator]'s mechanism,
/// keyed by uid under `defenses/{id}/composing`. Readers expire it, because
/// nothing sweeps a marker left by a closed laptop.
class DefenceComposing {
  const DefenceComposing({
    required this.uid,
    required this.name,
    required this.position,
    required this.target,
    this.updatedAt,
  });

  final String uid;
  final String name;
  final String position;
  final ComposingTarget target;
  final DateTime? updatedAt;

  bool isStaleAt(DateTime now) {
    final at = updatedAt;
    if (at == null) return true;
    return now.difference(at) > ComposingIndicator.staleAfter;
  }

  factory DefenceComposing.fromMap(String uid, Map<String, dynamic> map) {
    return DefenceComposing(
      uid: uid,
      name: map['name'] as String? ?? '',
      position: map['position'] as String? ?? '',
      target: ComposingTarget.fromString(map['target'] as String?),
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }
}
