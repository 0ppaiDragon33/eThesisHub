import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'We sent a verification link to your institutional email. '
                  'Open it, then return here and continue.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('reload'),
                  onPressed: () async {
                    await auth.currentUser?.reload();
                  },
                  child: const Text("I've verified — continue"),
                ),
                TextButton(
                  key: const Key('resend'),
                  onPressed: auth.sendEmailVerification,
                  child: const Text('Resend link'),
                ),
                TextButton(
                  key: const Key('signout'),
                  onPressed: auth.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
