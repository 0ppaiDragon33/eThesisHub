import 'package:flutter/material.dart';

import 'package:ethesishub/core/components/brand.dart';
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
    return AuthScaffold(
      key: const Key('deactivatedScreen'),
      title: 'Account deactivated',
      subtitle: 'This account has been deactivated by the college.',
      children: [
        Icon(Icons.no_accounts_outlined,
            size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        const Text(
          'Your account has been deactivated by the College Research '
          'Coordinator, so it can no longer be used to sign in. If you '
          'think this is a mistake, contact the coordinator to have it '
          'restored.',
        ),
        const SizedBox(height: 24),
        const SignOutButton(),
      ],
    );
  }
}
