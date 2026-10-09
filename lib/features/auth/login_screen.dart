import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/security/rate_limiter.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/password_field.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/welcome_overlay.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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

  String _lockedMessage(Duration left) =>
      'Too many attempts. Try again in ${waitText(left)}.';

  /// "Incorrect email or password." with an attempts-left warning once it is
  /// close to the lock. [left] is tries remaining before a lock.
  String _incorrectMessage(int left) {
    const base = 'Incorrect email or password.';
    if (left <= 0 || left > 3) return base;
    return '$base $left ${left == 1 ? 'attempt' : 'attempts'} left before a '
        'temporary lock.';
  }

  Future<void> _submit() async {
    final limits = ref.read(authLimitsProvider);
    final locked = limits.loginLock(_email.text);
    if (locked != null) {
      setState(() => _error = _lockedMessage(locked));
      return;
    }

    // Held before signing in: once sign-in succeeds the router replaces this
    // screen, so the shell, not this screen, shows the welcome. Every
    // failure below clears it again.
    final welcome = ref.read(welcomePendingProvider.notifier);
    welcome.state = true;

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
      limits.loginSucceeded(_email.text);

      // Apply any pending faculty invite at first login.
      final user = credential.user;
      if (user != null && user.email != null) {
        try {
          final role = await ref.read(userRepositoryProvider).promoteFromInvite(
                uid: user.uid,
                email: user.email!,
              );
          if (role != null) {
            try {
              await ref.read(auditServiceProvider).log(
                    actorUid: user.uid,
                    action: 'role.promoted',
                    targetType: 'user',
                    targetId: user.uid,
                    metadata: {'role': role.value},
                  );
            } catch (_) {
              // Audit logging must never block sign-in.
            }
          }

          // Keep the faculty directory current. Written by the subject's own
          // client because Spark has no Cloud Functions. Also backfills anyone
          // promoted before this module shipped. Best-effort — the directory
          // entry must never block sign-in. Same guard as the audit log above.
          try {
            final profile =
                await ref.read(userRepositoryProvider).fetchUser(user.uid);
            if (profile != null) {
              await ref
                  .read(facultyDirectoryRepositoryProvider)
                  .upsertOwnEntry(profile);
            }
          } catch (_) {}
        } on FirebaseException catch (e) {
          // PERMISSION_DENIED is expected if email isn't verified yet.
          // Allow sign-in to continue; user can be promoted on next login.
          if (e.code != 'permission-denied') {
            rethrow;
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      welcome.state = false;
      // Only a wrong credential counts toward the lock; a network error or a
      // server-side refusal is not the person guessing.
      final wrongCredential = e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'user-not-found';
      if (wrongCredential) limits.loginFailed(_email.text);
      final lockedNow = wrongCredential ? limits.loginLock(_email.text) : null;
      // How many tries remain before the lock, shown as it gets close so the
      // lock is never a surprise.
      final left = wrongCredential ? limits.loginAttemptsLeft(_email.text) : 0;
      if (!mounted) return;
      setState(() {
        _error = lockedNow != null
            ? _lockedMessage(lockedNow)
            : switch (e.code) {
          'wrong-password' || 'invalid-credential' =>
            _incorrectMessage(left),
          'user-not-found' => _incorrectMessage(left),
          'too-many-requests' => 'Too many attempts. Try again later.',
          _ => 'Sign-in failed. Please try again.',
        };
      });
    } on FirebaseException {
      welcome.state = false;
      // Handle Firestore errors (e.g., internal errors during invite read).
      // This must come after FirebaseAuthException since it's a subtype.
      if (!mounted) return;
      setState(() {
        _error = 'Sign-in failed. Please try again.';
      });
    } catch (_) {
      // Catch any other unexpected errors
      welcome.state = false;
      if (!mounted) return;
      setState(() {
        _error = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Resetting a password has its own page; the email typed here goes with it.
  void _forgotPassword() {
    final email = _email.text.trim();
    context.go(email.isEmpty
        ? '/forgot-password'
        : Uri(path: '/forgot-password', queryParameters: {'email': email})
            .toString());
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Use your ISUFST account.',
      children: [
        FormRow(
          label: 'Email',
          child: TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'you@isufst.edu.ph',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
        ),
        FormRow(
          label: 'Password',
          child: PasswordField(
            fieldKey: const Key('password'),
            controller: _password,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_busy) _submit();
            },
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('reset'),
            onPressed: _busy ? null : _forgotPassword,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: AppTokens.sm),
        if (_error != null) ...[
          ErrorState(message: _error!),
          const SizedBox(height: AppTokens.md),
        ],
        FilledButton(
          key: const Key('submit'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 50)),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
        const SizedBox(height: AppTokens.lg),
        const Divider(),
        const SizedBox(height: AppTokens.md),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('New to eThesisHub?',
                style: Theme.of(context).textTheme.bodyMedium),
            TextButton(
              key: const Key('goToRegister'),
              onPressed: () => context.go('/register'),
              child: const Text('Create an account'),
            ),
          ],
        ),
      ],
    );
  }
}
