import 'package:flutter/material.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/tone.dart';

/// When a remark was written, as every comment and highlight list shows it:
/// "Sep 29, 4:05 PM", small and muted. Nothing while the server time is
/// still on its way, rather than a misleading local guess.
class CommentTime extends StatelessWidget {
  const CommentTime(this.at, {super.key});

  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    final t = at;
    if (t == null) return const SizedBox.shrink();
    return Text(
      Dates.dayTime(t),
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Palette.of(context).muted),
    );
  }
}

/// A remark's text with its time beneath it.
class CommentWithTime extends StatelessWidget {
  const CommentWithTime({super.key, required this.body, required this.at});

  final String body;
  final DateTime? at;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
        if (at != null) ...[
          const SizedBox(height: 2),
          CommentTime(at),
        ],
      ],
    );
  }
}
