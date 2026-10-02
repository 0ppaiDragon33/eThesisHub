import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/security/rate_limiter.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Ask for a password reset link: the email, one button, and a "check your
/// email" page once it is sent.
///
/// An address with no account reads the same as one with an account, so this
/// page cannot be used to find out who is registered.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.email});

  /// What the sign-in page already had in its email box.
  final String? email;

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email ?? '');

  String? _error;
  bool _busy = false;

  /// The address a link was sent to; non-null shows the "check your email"
  /// page.
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email.');
      return;
    }

    final cooldown = ref.read(authLimitsProvider).passwordReset;
    final key = AuthLimits.emailKey(email);
    final wait = cooldown.remaining(key);
    if (wait != null) {
      setState(
        () => _error =
            'A link was just sent. Wait ${waitText(wait)} to send another.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).sendPasswordReset(email);
      cooldown.start(key);
      if (mounted) setState(() => _sentTo = email);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'user-not-found':
          // Same page as a real send: do not reveal who has an account.
          cooldown.start(key);
          setState(() => _sentTo = email);
        case 'invalid-email':
          setState(() => _error = 'Enter a valid email address.');
        case 'too-many-requests':
          setState(() => _error = 'Too many requests. Try again later.');
        default:
          setState(
            () => _error = 'Could not send the link. Please try again.',
          );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the link. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToSignIn() => context.go('/login');

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    if (sentTo != null) return _sent(context, sentTo);

    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'We will email you a link to choose a new one.',
      children: [
        FormRow(
          label: 'Email',
          child: TextField(
            key: const Key('email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            autofocus: true,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: 'you@isufst.edu.ph',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
        ),
        if (_error != null) ...[
          ErrorState(message: _error!),
          const SizedBox(height: AppTokens.md),
        ],
        FilledButton(
          key: const Key('sendReset'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 50)),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send reset link'),
        ),
        const SizedBox(height: AppTokens.md),
        Align(
          child: TextButton(
            key: const Key('backToSignIn'),
            onPressed: _backToSignIn,
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }

  Widget _sent(BuildContext context, String email) {
    final text = Theme.of(context).textTheme;
    return AuthScaffold(
      title: 'Check your email',
      children: [
        Text(
          'If $email has an account, a reset link is on its way. '
          'It may take a minute.',
          key: const Key('resetSent'),
          style: text.bodyMedium,
        ),
        const SizedBox(height: AppTokens.lg),
        if (_error != null) ...[
          ErrorState(message: _error!),
          const SizedBox(height: AppTokens.md),
        ],
        FilledButton(
          key: const Key('backToSignIn'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 50)),
          onPressed: _backToSignIn,
          child: const Text('Back to sign in'),
        ),
        const SizedBox(height: AppTokens.md),
        Align(
          child: TextButton(
            key: const Key('resendReset'),
            onPressed: _busy ? null : _send,
            child: const Text('Send it again'),
          ),
        ),
      ],
    );
  }
}
