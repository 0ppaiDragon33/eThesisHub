import 'package:flutter/material.dart';

import 'package:ethesishub/core/widgets/sign_out_button.dart';

/// Shown to a signed-in, verified account whose `users/{uid}.active` is
/// `false` — a coordinator has switched off its access.
///
/// It sits OUTSIDE the app shell, next to the sign-in and verify-email
/// screens rather than beside `/no-profile`, for the reason those screens
/// are outside too: a sidebar full of destinations the account may not open
/// is worse than none. The only action offered is sign-out.
///
/// This is the visible half of deactivation. The authoritative half is
/// firestore.rules; see the router's own note. If the account is
/// reactivated, the redirect that put it here sends it back to its overview
/// on the next profile emission.
class DeactivatedScreen extends StatelessWidget {
  const DeactivatedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('deactivatedScreen'),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.no_accounts_outlined,
                    size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text('Account deactivated',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                const Text(
                  'Your account has been deactivated by the College Research '
                  'Coordinator, so it can no longer be used to sign in. If you '
                  'think this is a mistake, contact the coordinator to have it '
                  'restored.',
                ),
                const SizedBox(height: 24),
                const SignOutButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
