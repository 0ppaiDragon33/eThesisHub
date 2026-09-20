import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
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
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in options)
          DropdownMenuItem(
              value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
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

    final text = Theme.of(context).textTheme;

    Widget pair(Widget a, Widget b) => LayoutBuilder(
          builder: (context, c) => c.maxWidth < 480
              ? Column(children: [a, const Gap.md(), b])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: a),
                    const SizedBox(width: AppTokens.md),
                    Expanded(child: b),
                  ],
                ),
        );

    return PageShell(
      kicker: 'Step 1 of 3',
      title: 'Create your thesis group',
      subtitle: 'Next you will nominate an adviser and panel, then submit '
          'candidate titles once the Dean approves.',
      children: [
        Panel(
          title: 'Working title',
          icon: Icons.title_rounded,
          child: FormRow(
            label: 'Working title',
            hint: 'Your initial idea. Candidate titles come later.',
            child: TextField(
              key: const Key('workingTitle'),
              controller: _workingTitle,
              maxLines: 2,
              minLines: 1,
            ),
          ),
        ),
        const Gap.md(),
        Panel(
          title: 'Members',
          subtitle: 'You are already listed as the group leader. Add '
              'everyone else.',
          icon: Icons.groups_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.star_outline_rounded,
                      size: 20, color: Palette.of(context).seal),
                  const SizedBox(width: AppTokens.sm),
                  Text('You, group leader', style: text.labelLarge),
                ],
              ),
              for (var i = 0; i < _members.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: AppTokens.sm + 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: Key('member$i'),
                          controller: _members[i],
                          decoration: InputDecoration(
                            labelText: 'Member ${i + 1}',
                            hintText: 'Surname, First name',
                          ),
                        ),
                      ),
                      if (_members.length > 1)
                        IconButton(
                          tooltip: 'Remove member ${i + 1}',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            final removed = _members[i];
                            setState(() => _members.removeAt(i));
                            // Disposed after the frame that stops using it.
                            WidgetsBinding.instance.addPostFrameCallback(
                                (_) => removed.dispose());
                          },
                        ),
                    ],
                  ),
                ),
              const Gap.sm(),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('addMember'),
                  onPressed: () => setState(
                      () => _members.add(TextEditingController())),
                  icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                  label: const Text('Add member'),
                ),
              ),
            ],
          ),
        ),
        const Gap.md(),
        Panel(
          title: 'Academic record',
          icon: Icons.account_balance_outlined,
          child: Column(
            children: [
              pair(
                _dropdown('college', 'College', _college, kColleges,
                    (v) => setState(() => _college = v)),
                _dropdown('program', 'Program', _program, kPrograms,
                    (v) => setState(() => _program = v)),
              ),
              const Gap.md(),
              pair(
                _dropdown('semester', 'Semester', _semester, kSemesters,
                    (v) => setState(() => _semester = v)),
                _dropdown('academicYear', 'Academic year', _academicYear,
                    kAcademicYears,
                    (v) => setState(() => _academicYear = v)),
              ),
            ],
          ),
        ),
        const Gap.lg(),
        if (_error != null) ...[
          ErrorState(key: const Key('error'), message: _error!),
          const Gap.md(),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('submit'),
            onPressed: (_busy || !signedIn) ? null : _submit,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text(_busy ? 'Creating…' : 'Create group'),
          ),
        ),
      ],
    );
  }
}
