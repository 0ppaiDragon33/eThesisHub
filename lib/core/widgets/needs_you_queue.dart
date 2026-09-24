import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/motion.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/needs_you_item.dart';

Tone toneOf(NeedsYouTone tone) => switch (tone) {
      NeedsYouTone.act => Tone.act,
      NeedsYouTone.waiting => Tone.awaiting,
      NeedsYouTone.returned => Tone.returned,
    };

/// Opens a queue row: destinations are gone to, screens below one are
/// pushed (see `NeedsYouItem.deep`).
void openNeedsYou(BuildContext context, NeedsYouItem item) =>
    item.deep ? context.push(item.route) : context.go(item.route);

/// "3 things need you" — the count is the length of the very list rendered
/// with it, so the two can never disagree. Says nothing while loading.
class NeedsYouHeadline extends StatelessWidget {
  const NeedsYouHeadline({
    super.key,
    required this.items,
    required this.suffix,
  });

  final AsyncValue<List<NeedsYouItem>> items;
  final String suffix;

  static String? leadFor(int? count) => switch (count) {
        null => null,
        0 => 'Nothing needs you today',
        1 => '1 thing needs you today',
        _ => '$count things need you today',
      };

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lead = leadFor(items.valueOrNull?.length);
    final text = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(children: [
        if (lead != null)
          TextSpan(
            text: '$lead · ',
            style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
          ),
        TextSpan(text: suffix),
      ]),
      style: text.bodyMedium?.copyWith(color: p.muted),
    );
  }
}

/// The reader's action inbox.
///
/// The first item is set apart as the next step, with its own filled
/// button; the rest follow as a register. Every row carries its state as a
/// word and an icon as well as a colour.
class NeedsYouQueue extends StatelessWidget {
  const NeedsYouQueue({
    super.key,
    required this.items,
    required this.emptyTitle,
    required this.emptyMessage,
    this.title = 'Waiting on you',
    this.featureFirst = true,
  });

  final AsyncValue<List<NeedsYouItem>> items;
  final String emptyTitle;
  final String emptyMessage;
  final String title;

  /// Whether the first item is drawn as a prominent next step.
  final bool featureFirst;

  @override
  Widget build(BuildContext context) {
    return items.when(
      // Its own loading and error handling rather than collapsing to
      // `data(const [])`, which would read as "nothing waiting".
      loading: () => Panel(
        title: title,
        icon: Icons.inbox_outlined,
        child: const LoadingState(label: 'Checking what needs you…'),
      ),
      error: (e, _) => Panel(
        title: title,
        icon: Icons.inbox_outlined,
        child: ErrorState(
          error: e,
          message: 'Could not work out what needs you.',
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.done_all_rounded,
            title: emptyTitle,
            message: emptyMessage,
          );
        }
        final first = featureFirst ? list.first : null;
        final rest = featureFirst ? list.skip(1).toList() : list;
        return FadeIn(child: Panel(
          title: title,
          icon: Icons.inbox_outlined,
          flush: true,
          emphasis: featureFirst,
          trailing: _CountPill(count: list.length),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (first != null)
                _NextStep(key: Key('needsYouEntry-${first.route}'), item: first),
              for (final item in rest)
                _QueueRow(key: Key('needsYouEntry-${item.route}'), item: item),
            ],
          ),
        ));
      },
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: p.seal,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({super.key, required this.item});

  final NeedsYouItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppTokens.lg - 4),
      decoration: BoxDecoration(
        color: p.seal.withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: p.rule)),
      ),
      child: LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 520;
        final words = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('Next step',
                    style: text.labelMedium?.copyWith(color: p.seal)),
                const SizedBox(width: AppTokens.sm),
                Flexible(
                  child: ToneBadge(
                    label: item.chipLabel,
                    tone: toneOf(item.tone),
                    dense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.sm),
            Text(item.title, style: text.titleLarge),
            const SizedBox(height: AppTokens.xs),
            Text(item.detail, style: text.bodyMedium?.copyWith(color: p.muted)),
          ],
        );
        final button = FilledButton.icon(
          onPressed: () => openNeedsYou(context, item),
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('Open'),
        );
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [words, const SizedBox(height: AppTokens.md), button],
          );
        }
        return Row(
          children: [
            Expanded(child: words),
            const SizedBox(width: AppTokens.lg),
            button,
          ],
        );
      }),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({super.key, required this.item});

  final NeedsYouItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);
    final tone = toneOf(item.tone);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => openNeedsYou(context, item),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.lg - 4, vertical: AppTokens.md - 2),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.rule)),
          ),
          child: LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 520;
            final badge = ToneBadge(
                label: item.chipLabel, tone: tone, dense: true);
            return Row(
              children: [
                Icon(tone.icon, size: 20, color: tone.color(context)),
                const SizedBox(width: AppTokens.md - 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(item.detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall),
                      if (narrow) ...[
                        const SizedBox(height: AppTokens.xs + 2),
                        badge,
                      ],
                    ],
                  ),
                ),
                if (narrow)
                  Icon(Icons.chevron_right_rounded, color: p.muted)
                else ...[
                  const SizedBox(width: AppTokens.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: badge,
                  ),
                  const SizedBox(width: AppTokens.sm),
                  TextButton(
                    onPressed: () => openNeedsYou(context, item),
                    child: const Text('Open'),
                  ),
                ],
              ],
            );
          }),
        ),
      ),
    );
  }
}
