import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

/// Sign-out action shared by every dashboard's app bar, and by
/// [LoginScreen] for the "signed in but no profile" dead-end case.
///
/// Failures are shown in a snackbar rather than left to escape, and
/// post-await context use is guarded with `mounted`.
class SignOutButton extends ConsumerWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      key: const Key('signOut'),
      icon: const Icon(Icons.logout),
      tooltip: 'Sign out',
      onPressed: () => _signOut(context, ref),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to sign out. Please try again.')),
      );
    }
  }
}
