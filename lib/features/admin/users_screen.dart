import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/admin_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Active-state buckets the coordinator can narrow by. Defaults to
/// [active]: a deactivated account is the exception, not the common case,
/// and a list that opened on every account ever created would bury the
/// handful still doing anything under every graduate the college has had.
enum ActiveFilter { active, inactive, all }

/// One uid's counted positions, folded from a single pass over every
/// thesis rather than one query per row.
typedef PositionCounts = ({int advising, int panelling});

/// Adviser and panelist counts per uid, derived from [allThesesProvider].
///
/// `adviserUid` and `panelistUids` live on the thesis document, not on any
/// per-faculty collection, so the only way to know how many groups someone
/// currently holds a position on is to look at every thesis. [allThesesProvider]
/// is already watched by two dashboards and is permitted to the coordinator,
/// so this folds over that ONE stream once per build rather than issuing a
/// query per row -- a college with thirty faculty would otherwise cost
/// thirty-plus reads to render one screen.
Map<String, PositionCounts> positionCounts(List<Thesis> theses) {
  final map = <String, PositionCounts>{};
  PositionCounts entryFor(String uid) => map[uid] ?? (advising: 0, panelling: 0);

  for (final t in theses) {
    final adviser = t.adviserUid;
    if (adviser != null && adviser.isNotEmpty) {
      final cur = entryFor(adviser);
      map[adviser] = (advising: cur.advising + 1, panelling: cur.panelling);
    }
    for (final p in t.panelistUids) {
      final cur = entryFor(p);
      map[p] = (advising: cur.advising, panelling: cur.panelling + 1);
    }
  }
  return map;
}

/// The coordinator's Users destination: every account in the college,
/// activated or not, with who may be nominated as an adviser or a panelist.
///
/// No `Scaffold`, no `AppBar` -- the app shell owns both for every
/// signed-in route, and a second one here would stack a second app bar.
///
/// Two tabs sit at the top, Accounts and Invites. This screen IS the
/// Accounts tab; Invites is a `context.go('/invites')` away, its own
/// linkable route rendering `FacultyInvitesScreen`, so both stay
/// bookmarkable rather than one being buried as local tab state the other
/// can never point at.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  /// `null` means "every role". Selecting a role explicitly (including
  /// [UserRole.student]) always shows it -- [_showStudents] only matters
  /// while this is `null`.
  UserRole? _roleFilter;

  /// Whether a student appears while [_roleFilter] is `null`. Off by
  /// default: a student cannot be nominated and carries no designation
  /// control, so a list opened to answer "who can I nominate" should not
  /// have to be scrolled past every student in the college. Turning it on
  /// is the escape hatch spec §-required elsewhere in this task: nothing
  /// else in the app can deactivate a graduated student, so this list must
  /// still be able to reach them.
  bool _showStudents = false;

  ActiveFilter _activeFilter = ActiveFilter.active;

  bool _visible(AppUser u) {
    if (_roleFilter != null) {
      if (u.role != _roleFilter) return false;
    } else if (u.role == UserRole.student && !_showStudents) {
      return false;
    }
    switch (_activeFilter) {
      case ActiveFilter.active:
        if (!u.active) return false;
      case ActiveFilter.inactive:
        if (u.active) return false;
      case ActiveFilter.all:
        break;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    final thesesAsync = ref.watch(allThesesProvider);
    final directoryAsync = ref.watch(allDirectoryProvider);
    final myUid = ref.watch(signedInUidProvider);

    return PageShell(
      key: const Key('usersScreen'),
      maxWidth: AppTokens.measureWide,
      title: 'Users',
      subtitle: 'Every account in the college. Activate, deactivate, and set '
          'who may be nominated as an adviser or a panelist.',
      children: [
        _Tabs(onInvites: () => context.go('/invites')),
        const Gap.lg(),
        _Filters(
          roleFilter: _roleFilter,
          showStudents: _showStudents,
          activeFilter: _activeFilter,
          onRoleChanged: (r) => setState(() => _roleFilter = r),
          onShowStudentsChanged: (v) => setState(() => _showStudents = v),
          onActiveChanged: (a) => setState(() => _activeFilter = a),
        ),
        const Gap.lg(),
        usersAsync.when(
          loading: () => const LoadingState(label: 'Loading accounts…'),
          error: (e, _) => ErrorState(
            error: e,
            message: 'Could not load accounts. Only coordinators may view '
                'this list.',
          ),
          data: (users) {
            final visible = users.where(_visible).toList()
              ..sort((a, b) => a.fullName.compareTo(b.fullName));
            if (visible.isEmpty) {
              return const EmptyState(
                key: Key('noUsers'),
                icon: Icons.people_outline,
                title: 'No accounts match this filter',
                message: 'Try a different role or active state.',
              );
            }
            final positions = positionCounts(thesesAsync.valueOrNull ?? const []);
            // Only asserted once the directory has actually loaded --
            // while it is still settling, treating every faculty row as
            // "not yet signed in" would flash a false warning on accounts
            // that have one.
            final directoryUids = <String>{
              for (final e in directoryAsync.valueOrNull ?? const [])
                e.uid,
            };
            return _UsersTable(
              users: visible,
              positions: positions,
              directoryUids: directoryUids,
              directoryLoaded: directoryAsync.hasValue,
              myUid: myUid,
            );
          },
        ),
      ],
    );
  }
}

/// Accounts (this screen) vs Invites (`/invites`), rendered as tabs even
/// though they are two separate routes -- see the class doc above.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.onInvites});

  final VoidCallback onInvites;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ChoiceChip(
          key: const Key('usersTabAccounts'),
          label: const Text('Accounts'),
          selected: true,
          // Already here; selecting the current tab is a no-op rather than
          // a route with no destination-changing effect.
          onSelected: (_) {},
        ),
        const SizedBox(width: AppTokens.sm),
        ChoiceChip(
          key: const Key('usersTabInvites'),
          label: const Text('Invites'),
          selected: false,
          onSelected: (_) => onInvites(),
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.roleFilter,
    required this.showStudents,
    required this.activeFilter,
    required this.onRoleChanged,
    required this.onShowStudentsChanged,
    required this.onActiveChanged,
  });

  final UserRole? roleFilter;
  final bool showStudents;
  final ActiveFilter activeFilter;
  final ValueChanged<UserRole?> onRoleChanged;
  final ValueChanged<bool> onShowStudentsChanged;
  final ValueChanged<ActiveFilter> onActiveChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppTokens.md,
      runSpacing: AppTokens.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<UserRole?>(
          key: const Key('roleFilter'),
          value: roleFilter,
          onChanged: onRoleChanged,
          items: [
            const DropdownMenuItem(value: null, child: Text('All roles')),
            for (final r in UserRole.values)
              DropdownMenuItem(value: r, child: Text(r.value)),
          ],
        ),
        if (roleFilter == null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                key: const Key('showStudentsToggle'),
                value: showStudents,
                onChanged: (v) => onShowStudentsChanged(v ?? false),
              ),
              const Text('Show students'),
            ],
          ),
        DropdownButton<ActiveFilter>(
          key: const Key('activeFilter'),
          value: activeFilter,
          onChanged: (v) => onActiveChanged(v ?? ActiveFilter.active),
          items: const [
            DropdownMenuItem(
                value: ActiveFilter.active, child: Text('Active')),
            DropdownMenuItem(
                value: ActiveFilter.inactive, child: Text('Inactive')),
            DropdownMenuItem(value: ActiveFilter.all, child: Text('All')),
          ],
        ),
      ],
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.positions,
    required this.directoryUids,
    required this.directoryLoaded,
    required this.myUid,
  });

  final List<AppUser> users;
  final Map<String, PositionCounts> positions;
  final Set<String> directoryUids;
  final bool directoryLoaded;
  final String? myUid;

  // Flex weights for the five columns, shared between the header and every
  // data row so the two stay lined up.
  static const _flex = [3, 1, 2, 3, 2];

  @override
  Widget build(BuildContext context) {
    final rule = Theme.of(context).colorScheme.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          flex: _flex,
          cells: const [
            Text('Name and email', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Role', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Positions', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Designation', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Active', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Divider(height: AppTokens.lg, color: rule),
        for (final u in users) ...[
          _Row(
            key: ValueKey('userRow-${u.uid}'),
            flex: _flex,
            cells: [
              _NameCell(
                user: u,
                // A student never gets a directory entry at all (see
                // FacultyDirectoryRepository.upsertOwnEntry), so this
                // marker means nothing for one and is suppressed.
                notSignedIn: u.isFaculty &&
                    directoryLoaded &&
                    !directoryUids.contains(u.uid),
              ),
              // Plain text, no control: a coordinator may never write
              // `role` (the rules pin it to the invite/promotion path),
              // and a control that always fails reads as a broken app.
              Text(u.role.value, key: Key('roleText-${u.uid}')),
              _PositionsCell(user: u, counts: positions[u.uid]),
              // A student can never be nominated, so a designation
              // control here would be meaningless -- not merely denied,
              // but asking a question that does not apply to this role.
              u.isFaculty ? _DesignationCell(user: u) : const Text('—'),
              _ActiveCell(user: u, isOwnRow: u.uid == myUid),
            ],
          ),
          Divider(height: AppTokens.lg, color: rule),
        ],
      ],
    );
  }
}

/// One row, header or data: five cells laid out with shared flex weights so
/// the header and every row line up, and each cell free to take whatever
/// height its own content needs -- unlike `DataTable`, which clips a cell
/// taller than its fixed row height. Several cells here genuinely run to two
/// or three lines: name+email, name+email+the "not yet signed in" notice, or
/// the active switch plus its refusal reason on the reader's own row.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.flex, required this.cells});

  final List<int> flex;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: flex[i],
              child: Padding(
                padding: const EdgeInsets.only(right: AppTokens.sm),
                child: cells[i],
              ),
            ),
        ],
      ),
    );
  }
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.user, required this.notSignedIn});

  final AppUser user;
  final bool notSignedIn;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(user.fullName, overflow: TextOverflow.ellipsis),
          Text(user.email,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
          if (notSignedIn)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.xs),
              child: Text(
                // Spec §4.2.1: an invited-and-designated account that has
                // never signed in has no directory entry yet -- the entry
                // is only created client-side at sign-in -- so a
                // designation set here has not reached the nomination
                // picker. This is that window, named rather than hidden.
                'Not yet signed in — designation has not reached the '
                'nomination picker yet.',
                key: Key('notSignedIn-${user.uid}'),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _PositionsCell extends StatelessWidget {
  const _PositionsCell({required this.user, required this.counts});

  final AppUser user;
  final PositionCounts? counts;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    if (!user.isFaculty || c == null || (c.advising == 0 && c.panelling == 0)) {
      return const Text('—');
    }
    return Text('${c.advising} advising · ${c.panelling} panel');
  }
}

class _DesignationCell extends ConsumerWidget {
  const _DesignationCell({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void write({bool? adviser, bool? panelist}) {
      ref.read(userRepositoryProvider).setDesignation(
            uid: user.uid,
            adviser: adviser ?? user.nominableAsAdviser,
            panelist: panelist ?? user.nominableAsPanelist,
          );
    }

    // Wrap, not Row: this column is narrow at the shell's own rail
    // breakpoint, and a Row here has no way to give up horizontal space --
    // it would silently clip "Panelist" off the edge instead of dropping
    // to a second line.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Checkbox(
          key: Key('adviserCheckbox-${user.uid}'),
          value: user.nominableAsAdviser,
          onChanged: (v) => write(adviser: v ?? false),
        ),
        const Text('Adviser'),
        const SizedBox(width: AppTokens.sm),
        Checkbox(
          key: Key('panelistCheckbox-${user.uid}'),
          value: user.nominableAsPanelist,
          onChanged: (v) => write(panelist: v ?? false),
        ),
        const Text('Panelist'),
      ],
    );
  }
}

class _ActiveCell extends ConsumerWidget {
  const _ActiveCell({required this.user, required this.isOwnRow});

  final AppUser user;
  final bool isOwnRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Switch(
          key: Key('activeSwitch-${user.uid}'),
          value: user.active,
          // The rules carry `request.auth.uid != uid`: a coordinator can
          // never activate or deactivate their own account. Disabling the
          // control here says so before the write is even attempted --
          // hiding the row would be stranger than showing it refused.
          onChanged: isOwnRow
              ? null
              : (v) => ref.read(userRepositoryProvider).setActive(user.uid, v),
        ),
        if (isOwnRow)
          SizedBox(
            width: 160,
            child: Text(
              'This is your own account — you cannot activate or '
              'deactivate yourself.',
              key: Key('ownRowReason-${user.uid}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
