import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/config/specializations.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// The signed-in person's own details: name, and for a student their program
/// and specialization (picked from the program's list), for faculty their
/// specialization as free text.
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
  late final _facultySpecialization =
      TextEditingController(text: widget.profile.specialization ?? '');

  late String? _program = _initialProgram();
  late String? _specialization = _initialSpecialization();

  bool _busy = false;
  String? _error;

  bool get _isStudent => widget.profile.role == UserRole.student;

  String? _initialProgram() {
    final p = widget.profile.program?.trim().toUpperCase();
    return kPrograms.contains(p) ? p : null;
  }

  String? _initialSpecialization() {
    final s = widget.profile.specialization;
    return specializationsFor(_initialProgram()).contains(s) ? s : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _facultySpecialization.dispose();
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
            program: _isStudent ? _program : widget.profile.program,
            specialization: _isStudent
                ? _specialization
                : _facultySpecialization.text,
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
    final options = specializationsFor(_program);

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
          if (_isStudent) ...[
            FormRow(
              label: 'Program',
              child: DropdownButtonFormField<String>(
                key: const Key('profileProgram'),
                initialValue: _program,
                isExpanded: true,
                hint: const Text('Choose your program'),
                items: [
                  for (final p in kPrograms)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (v) => setState(() {
                  _program = v;
                  // A specialization belongs to its program.
                  if (!specializationsFor(v).contains(_specialization)) {
                    _specialization = null;
                  }
                }),
              ),
            ),
            if (options.isNotEmpty)
              FormRow(
                label: 'Specialization',
                hint: 'Shown to your adviser and panel if you lead a group.',
                child: DropdownButtonFormField<String?>(
                  // Rebuilt when the program changes its options.
                  key: ValueKey('profileSpecialization-$_program'),
                  initialValue: _specialization,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    for (final s in options)
                      DropdownMenuItem<String?>(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => _specialization = v),
                ),
              ),
          ] else
            FormRow(
              label: 'Specialization',
              hint: 'Shown beside your name when groups nominate you.',
              child: TextField(
                key: const Key('profileFacultySpecialization'),
                controller: _facultySpecialization,
                decoration: const InputDecoration(hintText: 'e.g. MIT'),
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
