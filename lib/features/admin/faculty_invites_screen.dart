import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/faculty_invite.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/admin/users_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

/// Lets a Research Coordinator promote someone to faculty, coordinator or
/// dean without opening the Firebase Console.
///
/// The coordinator is this system's administrator — the project owner
/// collapsed six roles into five precisely so the coordinator absorbs that
/// job — and issuing invites is the clearest thing that makes them one.
/// Until this screen existed the whole promotion path lived outside the app.
///
/// An invite is not a role grant. It records that an address *may* claim a
/// role; the account itself is only promoted when that person signs in and
/// applies it, which is also what marks the invite consumed. That indirection
/// is deliberate: it means no coordinator ever writes another account's
/// `role` field, and the security rules enforce exactly that.
///
/// A coordinator can never invite themselves — `firestore.rules` refuses it —
/// which is what closes the self-elevation path found and fixed earlier on
/// this project.
class FacultyInvitesScreen extends ConsumerStatefulWidget {
  const FacultyInvitesScreen({super.key});

  @override
  ConsumerState<FacultyInvitesScreen> createState() =>
      _FacultyInvitesScreenState();
}

class _FacultyInvitesScreenState extends ConsumerState<FacultyInvitesScreen> {
  final _email = TextEditingController();
  final _specialization = TextEditingController();

  UserRole _role = UserRole.faculty;
  String _college = 'CICT';

  String? _error;
  String? _notice;
  bool _busy = false;

  static const _colleges = ['CICT', 'CFAS', 'COED', 'COAG', 'CIT'];

  /// The three roles the rules accept on an invite. `student` is absent by
  /// design — an account starts as a student and is only ever promoted.
  static const _invitableRoles = [
    UserRole.faculty,
    UserRole.coordinator,
    UserRole.dean,
  ];

  @override
  void dispose() {
    _email.dispose();
    _specialization.dispose();
    super.dispose();
  }

  Future<void> _invite(String myUid, String myEmail) async {
    if (_busy) return;

    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter the institutional email address.');
      return;
    }
    // Refused by the rules too — this is the client half of the same guard,
    // here only so the coordinator gets a reason rather than a denial.
    if (email == myEmail.toLowerCase()) {
      setState(() => _error =
          'You cannot invite yourself. Ask another coordinator to change '
          'your own role.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await ref.read(userRepositoryProvider).createInvite(
            email: email,
            role: _role,
            invitedBy: myUid,
            college: _college,
            specialization: _specialization.text.trim(),
          );
      // Best-effort, after the invite is written, swallowing its own failure
      // so the log never blocks issuing an invite.
      try {
        await ref.read(auditServiceProvider).log(
              actorUid: myUid,
              action: 'invite.issued',
              targetType: 'invite',
              targetId: email,
              metadata: {'role': _role.value},
            );
      } catch (_) {/* audit must never block the action */}
      if (!mounted) return;
      setState(() {
        _notice = 'Invited $email as ${roleLabel(_role)}. They will hold that role '
            'the next time they sign in with a verified address.';
        _email.clear();
        _specialization.clear();
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.code == 'permission-denied'
            ? 'You do not have permission to issue invites.'
            : 'Could not issue the invite. Please try again.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not issue the invite. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retract(FacultyInvite invite) async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(userRepositoryProvider).deleteInvite(invite.email);
      if (mounted) {
        setState(() => _notice = 'Retracted the invite for ${invite.email}.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not retract that invite.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside the handler: reading an auth provider
    // for the first time inside a submit races the stream's first event and
    // yields a stale null, which a generic catch then swallows.
    final me = ref.watch(authStateProvider).valueOrNull;
    final invitesAsync = ref.watch(facultyInvitesProvider);

    // No Scaffold and no AppBar: the app shell owns both for every
    // signed-in route now, and a second Scaffold here would stack a second
    // app bar with a back button that goes nowhere.
    return KeyedSubtree(
      // Identifies the destination for reachability tests. Asserting on the
      // AppBar title instead would match the sidebar entry that opens this
      // screen, and so would pass whether or not navigation happened.
      key: const Key('facultyInvitesScreen'),
      child: PageShell(
        maxWidth: AppTokens.measureWide,
        kicker: 'Research office',
        title: 'Users',
        subtitle: 'Invite faculty by their institutional address. The role '
            'is applied the first time they sign in with it verified.',
        children: [
          // Both Users tabs carry the same strip.
          const UsersTabs(selected: UsersTab.invites),
          const Gap.lg(),
          SplitColumns(
            primaryFlex: 5,
            secondaryFlex: 6,
            primary: [
              Panel(
                title: 'Invite a faculty member',
                icon: Icons.person_add_alt_outlined,
                emphasis: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormRow(
                      label: 'Institutional email',
                      child: TextField(
                        key: const Key('inviteEmail'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'surname@isufst.edu.ph',
                        ),
                      ),
                    ),
                    FormRow(
                      label: 'Role',
                      child: DropdownButtonFormField<UserRole>(
                        key: const Key('inviteRole'),
                        initialValue: _role,
                        items: [
                          for (final r in _invitableRoles)
                            DropdownMenuItem(
                                value: r, child: Text(roleLabel(r))),
                        ],
                        onChanged: (v) => setState(() => _role = v!),
                      ),
                    ),
                    FormRow(
                      label: 'College',
                      child: DropdownButtonFormField<String>(
                        key: const Key('inviteCollege'),
                        initialValue: _college,
                        isExpanded: true,
                        items: [
                          for (final c in _colleges)
                            DropdownMenuItem(
                              value: c,
                              child: Text(c, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() => _college = v!),
                      ),
                    ),
                    FormRow(
                      label: 'Specialization (optional)',
                      hint: 'Shown beside their name when students pick a '
                          'panel.',
                      child: TextField(
                        key: const Key('inviteSpecialization'),
                        controller: _specialization,
                      ),
                    ),
                    if (_error != null) ...[
                      ErrorState(key: const Key('error'), message: _error!),
                      const Gap.md(),
                    ],
                    if (_notice != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 18, color: Tone.endorsed.color(context)),
                          const SizedBox(width: AppTokens.sm),
                          Expanded(
                              child: Text(_notice!, key: const Key('notice'))),
                        ],
                      ),
                      const Gap.md(),
                    ],
                    FilledButton.icon(
                      key: const Key('sendInvite'),
                      onPressed: (_busy || me == null)
                          ? null
                          : () => _invite(me.uid, me.email ?? ''),
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: Text(_busy ? 'Inviting…' : 'Send invite'),
                    ),
                  ],
                ),
              ),
            ],
            secondary: [
              Panel(
                title: 'Invites',
                subtitle: 'Open invites can be retracted; claimed ones are '
                    'the record of a promotion',
                icon: Icons.mail_outline_rounded,
                flush: true,
                child: invitesAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppTokens.md),
                    child: LoadingState(),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(AppTokens.md),
                    child: ErrorState(
                      error: e,
                      message: 'Could not load invites. Only coordinators '
                          'may view them.',
                    ),
                  ),
                  data: (invites) {
                    if (invites.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(AppTokens.lg - 4),
                        child: Text('No invites yet.',
                            key: const Key('noInvites'),
                            style: Theme.of(context).textTheme.bodySmall),
                      );
                    }
                    return Column(
                      children: [
                        for (final i in invites)
                          RecordRow(
                            key: Key('invite_${i.email}'),
                            leading: InitialsAvatar(i.email, size: 32),
                            title: i.email,
                            subtitle: [
                              roleLabel(i.role),
                              if (i.college != null) i.college!,
                              if (i.specialization != null &&
                                  i.specialization!.isNotEmpty)
                                i.specialization!,
                            ].join(', '),
                            // Consumed invites are the permanent record of
                            // a promotion; only open ones can be retracted.
                            trailing: i.isConsumed
                                ? const ToneBadge(
                                    label: 'Claimed',
                                    tone: Tone.endorsed,
                                    dense: true,
                                  )
                                : TextButton(
                                    key: Key('retract_${i.email}'),
                                    onPressed: () => _retract(i),
                                    child: const Text('Retract'),
                                  ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
