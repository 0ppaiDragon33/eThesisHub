import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

const kColleges = ['CICT', 'CFAS', 'COED', 'COAG', 'CIT'];
const kPrograms = ['BSIT', 'BSCS', 'BSIS'];
const kSemesters = ['First', 'Second'];
const kAcademicYears = ['2026-2027', '2027-2028'];

/// Lets a student leader create their thesis group: a working title, member
/// names typed by the leader (they are not accounts — this text is what
/// later prints on Form 1 under "Very truly yours,"), and the fixed-set
/// college/program/semester/academic year. Calls
/// `ThesisRepository.createThesis`, which builds the exact key-whitelisted,
/// pinned-value map the security rules require.
class CreateThesisScreen extends ConsumerStatefulWidget {
  const CreateThesisScreen({super.key});

  @override
  ConsumerState<CreateThesisScreen> createState() =>
      _CreateThesisScreenState();
}

class _CreateThesisScreenState extends ConsumerState<CreateThesisScreen> {
  final _workingTitle = TextEditingController();
  final _members = <TextEditingController>[TextEditingController()];

  String _college = kColleges.first;
  String _program = kPrograms.first;
  String _semester = kSemesters.first;
  String _academicYear = kAcademicYears.first;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _workingTitle.dispose();
    for (final c in _members) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // guards against a double tap landing two creates

    final title = _workingTitle.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Working title is required.');
      return;
    }

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) {
      setState(() => _error = 'You must be signed in to create a thesis group.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(thesisRepositoryProvider).createThesis(
            leaderUid: uid,
            workingTitle: title,
            memberNames: _members
                .map((c) => c.text.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
            college: _college,
            program: _program,
            semester: _semester,
            academicYear: _academicYear,
          );
      // The success confirmation is navigation, not an in-place message:
      // once this thesis exists, the leader's next stop is the status
      // screen that tracks it. Navigating away also closes off a second
      // tap creating a second thesis — nothing in the security rules stops
      // one leader owning several theses, so leaving this screen is what
      // makes a repeat submit unreachable, not a `_created` flag.
      if (mounted) context.go('/thesis');
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'permission-denied'
            ? 'You do not have permission to create a thesis group. Make '
                'sure your email is verified.'
            : 'Could not create the group. Please try again.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not create the group. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown(String key, String label, String value,
      List<String> options, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      key: Key(key),
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: (v) => onChanged(v!),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read) so the provider is already primed with a
    // settled value by the time the user can tap submit — reading it lazily
    // for the first time inside _submit would race the stream's first
    // event and see a stale `null`.
    final signedIn = ref.watch(authStateProvider).valueOrNull != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create thesis group')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('workingTitle'),
                  controller: _workingTitle,
                  decoration: const InputDecoration(
                    labelText: 'Working title',
                    helperText:
                        'Your initial idea. Candidate titles come later.',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Your groupmates'),
                // Says plainly that the leader is already counted. Labelled
                // "Group members", this read as "list the group", and a
                // leader added themselves again — which printed them twice
                // on Form 1 and pushed a five-person group onto a second
                // sheet.
                Text(
                  'You are already listed as the group leader. Add everyone '
                  'else here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (var i = 0; i < _members.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      key: Key('member$i'),
                      controller: _members[i],
                      decoration: const InputDecoration(
                          labelText: 'Surname, First name'),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('addMember'),
                    onPressed: () => setState(
                        () => _members.add(TextEditingController())),
                    child: const Text('+ Add member'),
                  ),
                ),
                const SizedBox(height: 8),
                _dropdown('college', 'College', _college, kColleges,
                    (v) => setState(() => _college = v)),
                const SizedBox(height: 12),
                _dropdown('program', 'Program', _program, kPrograms,
                    (v) => setState(() => _program = v)),
                const SizedBox(height: 12),
                _dropdown('semester', 'Semester', _semester, kSemesters,
                    (v) => setState(() => _semester = v)),
                const SizedBox(height: 12),
                _dropdown('academicYear', 'Academic year', _academicYear,
                    kAcademicYears, (v) => setState(() => _academicYear = v)),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!,
                        key: const Key('error'),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                FilledButton(
                  key: const Key('submit'),
                  onPressed: (_busy || !signedIn) ? null : _submit,
                  child: Text(_busy ? 'Creating…' : 'Create group'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
