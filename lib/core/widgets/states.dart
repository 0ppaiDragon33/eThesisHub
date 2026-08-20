import 'package:cloud_firestore/cloud_firestore.dart';
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
    this.error,
  });

  final String message;
  final VoidCallback? onRetry;

  /// The underlying failure, shown as a short code beneath the message.
  ///
  /// There are no server-side logs on the Spark plan, so when something is
  /// refused in the field the only place the reason can surface is the
  /// screen. Without it a missing Firestore index and a dropped connection
  /// look identical, and the friendly copy actively misleads: "check your
  /// connection" sent someone hunting a network problem that did not exist.
  ///
  /// Kept to the code alone, never a stack trace or a raw exception string.
  final Object? error;

  /// Firestore's own codes, translated into what to actually do. Anything
  /// unrecognised falls through to the caller's message.
  static String? _hintFor(Object? error) {
    if (error is! FirebaseException) return null;
    return switch (error.code) {
      'failed-precondition' =>
        'This query needs a Firestore index that has not been created yet.',
      'permission-denied' =>
        'The security rules refused this read for your account.',
      'unavailable' => 'Could not reach Firestore.',
      _ => null,
    };
  }

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Message first, then hint: they answer different questions
                // and the caller's is the one that cannot be reconstructed.
                // The hint used to REPLACE the message, so every
                // permission-denied on a screen with four streams rendered
                // an identical box and there was no way to tell which read
                // had failed -- which is exactly the situation this project
                // hit in the field, with no server-side logs to fall back on.
                Text(message,
                    style: text.bodyMedium?.copyWith(color: scheme.error)),
                if (_hintFor(error) != null) ...[
                  const SizedBox(height: AppTokens.xs),
                  Text(_hintFor(error)!,
                      style: text.bodySmall?.copyWith(color: scheme.error)),
                ],
                if (error is FirebaseException) ...[
                  const SizedBox(height: AppTokens.xs),
                  Text(
                    '[${(error as FirebaseException).code}]',
                    key: const Key('errorCode'),
                    style: text.labelSmall?.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
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
