import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/institutional_domain_notice.dart';
import 'package:ethesishub/core/widgets/password_strength_meter.dart';
import 'package:ethesishub/features/auth/registration_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _program = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _program.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final error = await ref.read(registrationControllerProvider).submit(
          fullName: _fullName.text,
          email: _email.text,
          password: _password.text,
          confirmPassword: _confirmPassword.text,
          program: _program.text.trim().isEmpty ? null : _program.text.trim(),
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Renders nothing while the domain restriction is enforced.
                const InstitutionalDomainNotice(),
                TextField(
                  key: const Key('fullName'),
                  controller: _fullName,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Institutional email',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('program'),
                  controller: _program,
                  decoration: const InputDecoration(
                    labelText: 'Program (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  // Rebuilds the meter as they type. The meter is guidance
                  // only — nothing here blocks a submission.
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    helperText: 'At least 8 characters. A phrase of a few '
                        'words works well.',
                  ),
                ),
                PasswordStrengthMeter(_password.text),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('confirmPassword'),
                  controller: _confirmPassword,
                  obscureText: true,
                  decoration:
                      const InputDecoration(labelText: 'Confirm password'),
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
                  child: Text(_busy ? 'Creating…' : 'Create account'),
                ),
                TextButton(
                  key: const Key('goToLogin'),
                  onPressed: () => context.go('/login'),
                  child: const Text('Already have an account? Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
