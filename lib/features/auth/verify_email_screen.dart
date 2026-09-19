import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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

      // The email is verified, but `reload()` above only refreshed the local
      // User — the cached ID token still says `email_verified: false`, and
      // the security rules read the TOKEN. Force a fresh one now, before the
      // invite write below and before the user reaches any create screen, so
      // Firestore does not refuse a genuinely-verified account. Without this
      // a just-verified student was told, on creating their thesis group,
      // that their email was not verified.
      await ref.read(authServiceProvider).refreshIdToken();
      if (!mounted) return;

      // User is now verified; apply any pending invite.
      if (user.email != null) {
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
          // permission-denied is fine (no invite), but other errors matter.
          if (e.code != 'permission-denied') {
            rethrow;
          }
        }
      }

      if (!mounted) return;

      // authStateChanges() does not emit on reload(), so the cached User in
      // authStateProvider still reports emailVerified == false even though
      // auth.currentUser is now verified. Invalidating forces a fresh
      // subscription that picks up the current (verified) user, which fires
      // the router's refresh notifier and lets the redirect proceed.
      ref.invalidate(authStateProvider);

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
    return AuthScaffold(
      title: 'Verify your email',
      // No subtitle: the paragraph below already says it, and says what to do
      // next as well. Two paraphrases of one sentence is the duplication this
      // direction removes.
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.mark_email_unread_outlined,
                size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppTokens.md),
            const Expanded(
              child: Text(
                'We sent a verification link to your institutional email. '
                'Open it, then return here and continue.',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.lg),
        if (_message != null) ...[
          ErrorState(message: _message!),
          const SizedBox(height: AppTokens.md),
        ],
        FilledButton(
          key: const Key('reload'),
          onPressed: _busy ? null : _handleContinue,
          child: Text(_busy ? 'Checking…' : "I've verified — continue"),
        ),
        const SizedBox(height: AppTokens.sm),
        OutlinedButton(
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
    );
  }
}
