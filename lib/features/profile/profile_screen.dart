import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// The signed-in person's own details: name, specialization, and for a
/// student their program. Both are typed freely, since the names change.
///
/// A group leader's specialization is copied onto their thesis, so the
/// adviser and panel see it ("Leader specialization: Software Development").
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentUserProvider);
    return PageShell(
      title: 'My profile',
      children: [
        profileAsync.when(
          loading: () => const LoadingState(label: 'Loading your profile…'),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load your profile.',
          ),
          data: (profile) => profile == null
              ? const ErrorState(message: 'Your profile is missing.')
              // Keyed on the account so switching users starts a fresh form.
              : _ProfileForm(key: ValueKey(profile.uid), profile: profile),
        ),
      ],
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({super.key, required this.profile});

  final AppUser profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.profile.fullName);
  late final _program =
      TextEditingController(text: widget.profile.program ?? '');
  late final _specialization =
      TextEditingController(text: widget.profile.specialization ?? '');

  bool _busy = false;
  String? _error;

  bool get _isStudent => widget.profile.role == UserRole.student;

  @override
  void dispose() {
    _name.dispose();
    _program.dispose();
    _specialization.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(userRepositoryProvider).updateOwnProfile(
            uid: widget.profile.uid,
            fullName: _name.text,
            // Faculty have no program box; theirs is kept as it is.
            program: _isStudent ? _program.text : widget.profile.program,
            specialization: _specialization.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Profile saved.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save your profile. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

    return Panel(
      title: roleLabel(profile.role),
      subtitle: profile.email,
      icon: Icons.person_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormRow(
            label: 'Full name',
            child: TextField(
              key: const Key('profileName'),
              controller: _name,
              textCapitalization: TextCapitalization.words,
            ),
          ),
          if ((profile.college ?? '').isNotEmpty)
            FormRow(
              label: 'College',
              child: Text(profile.college!, key: const Key('profileCollege')),
            ),
          if (_isStudent)
            FormRow(
              label: 'Program',
              child: TextField(
                key: const Key('profileProgram'),
                controller: _program,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'e.g. BSIT'),
              ),
            ),
          FormRow(
            label: 'Specialization',
            hint: _isStudent
                ? 'Shown to your adviser and panel if you lead a group.'
                : 'Shown beside your name when groups nominate you.',
            child: TextField(
              key: const Key('profileSpecialization'),
              controller: _specialization,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: _isStudent ? 'e.g. Software Development' : 'e.g. MIT',
              ),
            ),
          ),
          if (_error != null) ...[
            ErrorState(key: const Key('profileError'), message: _error!),
            const SizedBox(height: AppTokens.md),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('saveProfile'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}
