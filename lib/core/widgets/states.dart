import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// Nothing here yet — and what to do about it.
///
/// An empty queue previously rendered as blank space, which reads as a
/// screen that failed to load. An empty screen is an invitation to act, so
/// this always says what would put something here, and offers the action
/// when there is one to offer.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: AppTokens.md),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AppTokens.sm),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[
            const SizedBox(height: AppTokens.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Something went wrong — said plainly, with a way forward.
///
/// Errors do not apologise and are never vague about what happened. The one
/// case worth naming specifically is a permission denial, because on this
/// system that almost always means the account is not verified or does not
/// hold the role, and telling someone that is the difference between a
/// dead end and a next step.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppTokens.md),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(AppTokens.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.error),
          const SizedBox(width: AppTokens.sm),
          Expanded(
            child: Text(message,
                style: text.bodyMedium?.copyWith(color: scheme.error)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

/// A loading state that holds its place rather than collapsing the layout.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.xl),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (label != null) ...[
            const SizedBox(height: AppTokens.md),
            Text(label!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}
