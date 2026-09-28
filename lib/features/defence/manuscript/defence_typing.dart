import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';

/// One person's "is typing" marker in a defence room: written when they
/// start, refreshed every [beat] while they keep at it, deleted when they
/// stop, send or leave.
class DefenceTyping {
  DefenceTyping({
    required this._repo,
    required this.defenceId,
    required this.uid,
    required this.name,
    required this.position,
    this.beat = const Duration(seconds: 5),
  });

  final DefenceRepository _repo;
  final String defenceId;
  final String uid;
  final String name;
  final String position;
  final Duration beat;

  ComposingTarget? _target;
  Timer? _timer;

  bool get isTyping => _target != null;

  /// [active] is whether the box for [target] has focus and text. Turning
  /// one box off leaves a marker for the other box alone.
  void typing(ComposingTarget target, {required bool active}) {
    if (active) {
      final changed = _target != target;
      _target = target;
      if (changed) _write();
      _timer ??= Timer.periodic(beat, (_) => _write());
    } else if (_target == target) {
      stop();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_target == null) return;
    _target = null;
    _quiet(_repo.clearComposing(defenceId: defenceId, uid: uid));
  }

  void dispose() => stop();

  void _write() {
    final target = _target;
    if (target == null) return;
    _quiet(_repo.markComposing(
      defenceId: defenceId,
      uid: uid,
      name: name,
      position: position,
      target: target,
    ));
  }

  /// A marker is decoration: a refused or failed write costs the reader
  /// nothing, and must not surface as an uncaught error (see the title
  /// defence screen's `_presence`).
  static void _quiet(Future<void> write) {
    write.catchError((Object _) {});
  }
}

/// "Dr. Santos is typing…", "Dr. Santos and Prof. Cruz are typing…", or
/// null when nobody is.
String? typingText(List<String> names) {
  if (names.isEmpty) return null;
  if (names.length == 1) return '${names.first} is typing…';
  if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
  return '${names[0]}, ${names[1]} and ${names.length - 2} more are typing…';
}

/// Who else is typing in one box of the room. Re-checks every few seconds
/// so a marker left behind by a closed laptop disappears on its own.
class TypingLine extends StatefulWidget {
  const TypingLine({
    super.key,
    required this.markers,
    required this.target,
    this.myUid,
    this.now,
  });

  final List<DefenceComposing> markers;
  final ComposingTarget target;
  final String? myUid;

  /// The clock, for tests.
  final DateTime Function()? now;

  @override
  State<TypingLine> createState() => _TypingLineState();
}

class _TypingLineState extends State<TypingLine> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = (widget.now ?? DateTime.now)();
    final names = [
      for (final m in widget.markers)
        if (m.target == widget.target &&
            m.uid != widget.myUid &&
            !m.isStaleAt(now))
          m.name,
    ];
    final text = typingText(names);
    if (text == null) return const SizedBox.shrink();
    final seal = Palette.of(context).seal;
    return Padding(
      key: Key('typingLine-${widget.target.name}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.edit_note_rounded, size: 18, color: seal),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: seal, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}
