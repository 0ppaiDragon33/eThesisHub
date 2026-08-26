import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';

/// "3 things need you today · Second semester 2026–2027".
///
/// The count is the length of the very list rendered below it. Computing it
/// separately would eventually let the two disagree, and a dashboard that
/// contradicts itself is worse than one that shows nothing. While the list
/// is loading this says nothing at all rather than claiming zero.
class NeedsYouHeadline extends StatelessWidget {
  const NeedsYouHeadline({
    super.key,
    required this.items,
    required this.suffix,
  });

  final AsyncValue<List<NeedsYouItem>> items;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final count = items.valueOrNull?.length;

    final lead = switch (count) {
      null => null,
      0 => 'Nothing needs you today',
      1 => '1 thing needs you today',
      _ => '$count things need you today',
    };

    return Text(
      lead == null ? suffix : '$lead · $suffix',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
    );
  }
}

/// The list of things waiting on this reader.
class NeedsYouQueue extends StatelessWidget {
  const NeedsYouQueue({
    super.key,
    required this.items,
    required this.emptyTitle,
    required this.emptyMessage,
  });

  final AsyncValue<List<NeedsYouItem>> items;
  final String emptyTitle;
  final String emptyMessage;

  static Color _colour(BuildContext context, NeedsYouTone tone) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      NeedsYouTone.act => dark ? AppTokens.sealDark : AppTokens.seal,
      NeedsYouTone.waiting => dark ? AppTokens.awaitingDark : AppTokens.awaiting,
      NeedsYouTone.returned => dark ? AppTokens.returnedDark : AppTokens.returned,
    };
  }

  @override
  Widget build(BuildContext context) {
    return items.when(
      // Its own loading and error handling rather than collapsing to
      // `data(const [])`, which renders an empty state indistinguishable
      // from "nothing waiting" — the most repeated bug in this codebase.
      loading: () => const LoadingState(label: 'Checking what needs you…'),
      error: (e, _) => ErrorState(
        error: e,
        message: 'Could not work out what needs you.',
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.done_all_outlined,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        return Card(
          child: Column(
            children: [
              for (final item in list)
                ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.detail),
                  trailing: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppTokens.sm,
                    children: [
                      Chip(
                        label: Text(item.chipLabel),
                        labelStyle: TextStyle(
                          color: _colour(context, item.tone),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        side: BorderSide(
                          color: _colour(context, item.tone)
                              .withValues(alpha: 0.4),
                        ),
                        backgroundColor: _colour(context, item.tone)
                            .withValues(alpha: 0.08),
                      ),
                      FilledButton(
                        onPressed: () => context.go(item.route),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
