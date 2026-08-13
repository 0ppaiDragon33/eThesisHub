import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  String? _message;
  bool _busy = false;

  Future<void> _handleContinue() async {
    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      await auth.currentUser?.reload();
      if (!mounted) return;

      final user = auth.currentUser;
      if (user == null) {
        setState(() {
          _busy = false;
          _message = 'Session expired. Please sign in again.';
        });
        return;
      }

      if (!user.emailVerified) {
        setState(() {
          _busy = false;
          _message =
              'Email not verified yet. Check your inbox for the verification link.';
        });
        return;
      }

      // User is now verified; apply any pending invite.
      if (user.email != null) {
        try {
          await ref.read(userRepositoryProvider).promoteFromInvite(
                uid: user.uid,
                email: user.email!,
              );
        } on FirebaseException catch (e) {
          // permission-denied is fine (no invite), but other errors matter.
          if (e.code != 'permission-denied') {
            rethrow;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Email verified! You can now proceed.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Verification failed. Please try again.';
      });
    }
  }

  Future<void> _handleResend() async {
    try {
      await ref.read(authServiceProvider).sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification link resent. Check your email.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to resend link. Please try again.')),
      );
    }
  }

  Future<void> _handleSignOut() async {
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to sign out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  key: const Key('reload'),
                  onPressed: _busy ? null : _handleContinue,
                  child: Text(_busy ? 'Checking…' : "I've verified — continue"),
                ),
                TextButton(
                  key: const Key('resend'),
                  onPressed: _busy ? null : _handleResend,
                  child: const Text('Resend link'),
                ),
                TextButton(
                  key: const Key('signout'),
                  onPressed: _busy ? null : _handleSignOut,
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
