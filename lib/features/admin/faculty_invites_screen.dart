import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_invite.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';

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
      if (!mounted) return;
      setState(() {
        _notice = 'Invited $email as ${_role.value}. They will hold that role '
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
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Invite a faculty member',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'They sign up normally with this address. The role is applied '
                'the first time they sign in with it verified.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('inviteEmail'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Institutional email',
                  hintText: 'surname@isufst.edu.ph',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                key: const Key('inviteRole'),
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [
                  for (final r in _invitableRoles)
                    DropdownMenuItem(value: r, child: Text(r.value)),
                ],
                onChanged: (v) => setState(() => _role = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('inviteCollege'),
                initialValue: _college,
                decoration: const InputDecoration(labelText: 'College'),
                items: [
                  for (final c in _colleges)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => _college = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('inviteSpecialization'),
                controller: _specialization,
                decoration: const InputDecoration(
                  labelText: 'Specialization (optional)',
                  helperText:
                      'Shown beside their name when students pick a panel.',
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!,
                      key: const Key('error'),
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_notice!, key: const Key('notice')),
                ),
              FilledButton(
                key: const Key('sendInvite'),
                onPressed: (_busy || me == null)
                    ? null
                    : () => _invite(me.uid, me.email ?? ''),
                child: Text(_busy ? 'Inviting…' : 'Send invite'),
              ),
              const Divider(height: 40),
              const Text('Invites',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              invitesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, _) => const Text(
                    'Could not load invites. Only coordinators may view them.'),
                data: (invites) {
                  if (invites.isEmpty) {
                    return const Text('No invites yet.',
                        key: Key('noInvites'));
                  }
                  return Column(
                    children: [
                      for (final i in invites)
                        ListTile(
                          key: Key('invite_${i.email}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(i.email),
                          subtitle: Text([
                            i.role.value,
                            if (i.college != null) i.college!,
                            if (i.specialization != null) i.specialization!,
                          ].join(' · ')),
                          trailing: i.isConsumed
                              // Consumed invites are the permanent record of
                              // a promotion that happened. Retracting one
                              // would erase evidence, not cancel anything —
                              // so only open invites offer the action.
                              ? const Text('Claimed')
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
            ],
          ),
        ),
      ),
    );
  }
}
