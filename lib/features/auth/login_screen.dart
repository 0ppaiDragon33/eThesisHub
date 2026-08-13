import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final credential = await auth.signIn(
        email: _email.text,
        password: _password.text,
      );

      // Apply any pending faculty invite at first login.
      final user = credential.user;
      if (user != null && user.email != null) {
        try {
          await ref.read(userRepositoryProvider).promoteFromInvite(
                uid: user.uid,
                email: user.email!,
              );
        } on FirebaseException catch (e) {
          // PERMISSION_DENIED is expected if email isn't verified yet.
          // Allow sign-in to continue; user can be promoted on next login.
          if (e.code != 'permission-denied') {
            rethrow;
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          'wrong-password' || 'invalid-credential' =>
            'Incorrect email or password.',
          'user-not-found' => 'Incorrect email or password.',
          'too-many-requests' => 'Too many attempts. Try again later.',
          _ => 'Sign-in failed. Please try again.',
        };
      });
    } on FirebaseException {
      // Handle Firestore errors (e.g., internal errors during invite read).
      // This must come after FirebaseAuthException since it's a subtype.
      if (!mounted) return;
      setState(() {
        _error = 'Sign-in failed. Please try again.';
      });
    } catch (_) {
      // Catch any other unexpected errors
      if (!mounted) return;
      setState(() {
        _error = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first, then tap Reset.');
      return;
    }
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset link sent to $email')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to send reset link. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  key: const Key('submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Signing in…' : 'Sign in'),
                ),
                TextButton(
                  key: const Key('reset'),
                  onPressed: _busy ? null : _resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
