import 'package:flutter/material.dart';

import 'package:ethesishub/core/config/password_policy.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

/// Live feedback on a password's strength — guidance, never a gate.
///
/// The bar rewards length rather than punctuation, because that is what
/// actually makes a password hard to guess, and the line beneath it says
/// what would improve *this* password rather than reciting rules. Nothing
/// here can stop a submission: the blocking rules live in
/// [PasswordPolicy.validate] and are deliberately few.
///
/// Renders nothing for an empty field, so it appears as you type instead of
/// greeting you with a red bar before you have typed anything.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter(this.password, {super.key});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    final strength = PasswordPolicy.strengthOf(password);
    final advice = PasswordPolicy.adviceFor(password);
    final dark = Theme.of(context).brightness == Brightness.dark;

    final (color, label, filled) = switch (strength) {
      PasswordStrength.weak => (
          dark ? AppTokens.returnedDark : AppTokens.returned,
          'Weak',
          1,
        ),
      PasswordStrength.fair => (
          dark ? AppTokens.awaitingDark : AppTokens.awaiting,
          'Fair',
          2,
        ),
      PasswordStrength.strong => (
          dark ? AppTokens.endorsedDark : AppTokens.endorsed,
          'Strong',
          3,
        ),
    };

    return Padding(
      key: const Key('passwordStrength'),
      padding: const EdgeInsets.only(top: AppTokens.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i < filled
                          ? color
                          : Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: AppTokens.xs),
              ],
              const SizedBox(width: AppTokens.sm),
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: color),
              ),
            ],
          ),
          if (advice.isNotEmpty) ...[
            const SizedBox(height: AppTokens.xs),
            Text(advice, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
