import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/confirm.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/admin_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
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
      kicker: 'Research office',
      title: 'Users',
      subtitle: 'Every account in the college. Activate, deactivate, and set '
          'who may be nominated as an adviser or a panelist.',
      actions: [
        OutlinedButton.icon(
          key: const Key('stalledLink'),
          onPressed: () => context.push('/stalled'),
          icon: const Icon(Icons.report_outlined, size: 18),
          label: const Text('Stalled nominations'),
        ),
        // The publish queue's link from the coordinator's admin area; it
        // is deliberately not a destination.
        OutlinedButton.icon(
          key: const Key('archiveQueueLink'),
          onPressed: () => context.go('/archive/queue'),
          icon: const Icon(Icons.upload_outlined, size: 18),
          label: const Text('Publish queue'),
        ),
      ],
      children: [
        const UsersTabs(selected: UsersTab.accounts),
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
            // Spec §7: each panel resolves its own AsyncValue, and a failed
            // one must SAY so rather than degrade into something that reads
            // as data. A failed theses query used to render every Positions
            // cell as "—", indistinguishable from "holds nothing" -- the
            // exact misreading the column exists to prevent (§5.1, because
            // of D30): the coordinator narrows someone while the screen
            // says they sit on nothing. Same for the directory, whose
            // failure silently withdrew every "not yet signed in" marker.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (thesesAsync.hasError) ...[
                  ErrorState(
                    key: const Key('positionsUnavailable'),
                    error: thesesAsync.error,
                    message: 'Could not load current positions. The Positions '
                        'column below is unknown for every row — it does not '
                        'mean these accounts hold nothing.',
                  ),
                  const Gap.md(),
                ],
                if (directoryAsync.hasError) ...[
                  ErrorState(
                    key: const Key('directoryUnavailable'),
                    error: directoryAsync.error,
                    message: 'Could not load the faculty directory, so this '
                        'screen cannot say which accounts have never signed '
                        'in and therefore have no designation in the '
                        'nomination picker yet.',
                  ),
                  const Gap.md(),
                ],
                _UsersTable(
                  users: visible,
                  positions: positions,
                  positionsFailed: thesesAsync.hasError,
                  directoryUids: directoryUids,
                  directoryLoaded: directoryAsync.hasValue,
                  myUid: myUid,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Which of the Users destination's two tabs a screen is.
enum UsersTab { accounts, invites }

/// Accounts (`/users`) vs Invites (`/invites`), rendered as tabs even though
/// they are two separate routes -- see [UsersScreen]'s class doc.
///
/// Public and shared by BOTH screens. It lived privately in this file at
/// first, so `/invites` rendered with the rail highlighting "Users", the app
/// bar reading "Invites", and no Accounts/Invites control anywhere on the
/// screen -- a tab you could enter and not leave. Spec §5 promises a
/// destination "with two tabs", which is only true if both of them carry
/// the strip.
class UsersTabs extends StatelessWidget {
  const UsersTabs({super.key, required this.selected});

  final UsersTab selected;

  @override
  Widget build(BuildContext context) {
    // Selecting the tab already showing is a no-op.
    final p = Palette.of(context);
    Widget tab(Key key, String label, IconData icon, UsersTab value,
        String route) {
      final on = selected == value;
      return InkWell(
        key: key,
        onTap: on ? null : () => context.go(route),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.md, vertical: AppTokens.sm + 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? p.seal : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: on ? p.seal : p.muted),
              const SizedBox(width: AppTokens.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: on ? p.seal : p.muted,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: 'Users sections',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.rule)),
        ),
        child: Row(
          children: [
            tab(const Key('usersTabAccounts'), 'Accounts',
                Icons.people_outline, UsersTab.accounts, '/users'),
            tab(const Key('usersTabInvites'), 'Invites',
                Icons.mail_outline_rounded, UsersTab.invites, '/invites'),
          ],
        ),
      ),
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
              DropdownMenuItem(value: r, child: Text(roleLabel(r))),
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
    required this.positionsFailed,
    required this.directoryUids,
    required this.directoryLoaded,
    required this.myUid,
  });

  final List<AppUser> users;
  final Map<String, PositionCounts> positions;

  /// The theses query failed, so [positions] is empty for a reason that has
  /// nothing to do with what anyone holds. Every cell says "unknown"
  /// instead of "—".
  final bool positionsFailed;
  final Set<String> directoryUids;
  final bool directoryLoaded;
  final String? myUid;

  // Flex weights for the five columns, shared between the header and every
  // data row so the two stay lined up.
  static const _flex = [3, 1, 2, 3, 2];

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final headStyle = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: p.muted);

    List<Widget> cellsFor(AppUser u) => [
          _NameCell(
            user: u,
            // A student never gets a directory entry, so the marker means
            // nothing for one and is suppressed.
            notSignedIn: u.isFaculty &&
                directoryLoaded &&
                !directoryUids.contains(u.uid),
          ),
          // Plain text, no control: a coordinator may never write `role`.
          Text(roleLabel(u.role), key: Key('roleText-${u.uid}')),
          _PositionsCell(
            user: u,
            counts: positions[u.uid],
            failed: positionsFailed,
          ),
          // A student can never be nominated.
          u.isFaculty
              ? _DesignationCell(user: u, isOwnRow: u.uid == myUid)
              : const Text('Not applicable'),
          _ActiveCell(user: u, isOwnRow: u.uid == myUid),
        ];

    return Panel(
      title: users.length == 1 ? '1 account' : '${users.length} accounts',
      icon: Icons.badge_outlined,
      flush: true,
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 820) {
          const labels = [
            'Account',
            'Role',
            'Positions',
            'May be nominated as',
            'Active',
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final u in users)
                Container(
                  key: ValueKey('userRow-${u.uid}'),
                  padding: const EdgeInsets.all(AppTokens.md),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: p.rule)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, cell) in cellsFor(u).indexed)
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppTokens.sm),
                          child: i == 0
                              ? cell
                              : Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 120,
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(labels[i],
                                            style: headStyle),
                                      ),
                                    ),
                                    Expanded(child: cell),
                                  ],
                                ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: p.canvas,
              padding: const EdgeInsets.symmetric(vertical: AppTokens.sm + 2),
              child: _Row(
                flex: _flex,
                cells: [
                  Text('Account', style: headStyle),
                  Text('Role', style: headStyle),
                  Text('Positions', style: headStyle),
                  Text('May be nominated as', style: headStyle),
                  Text('Active', style: headStyle),
                ],
              ),
            ),
            for (final u in users)
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.md),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: p.rule)),
                ),
                child: _Row(
                  key: ValueKey('userRow-${u.uid}'),
                  flex: _flex,
                  cells: cellsFor(u),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// One row, header or data: cells laid out with shared flex weights so the
/// header and every row line up, each free to take the height it needs.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.flex, required this.cells});

  final List<int> flex;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.md),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(user.fullName, size: 32),
        const SizedBox(width: AppTokens.sm + 2),
        Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(user.fullName,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
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
      )),
      ],
    );
  }
}

class _PositionsCell extends StatelessWidget {
  const _PositionsCell({
    required this.user,
    required this.counts,
    required this.failed,
  });

  final AppUser user;
  final PositionCounts? counts;

  /// The theses query failed. "—" would be a lie here: it reads as "holds
  /// nothing", which is the one conclusion this column exists to stop a
  /// coordinator drawing wrongly before they narrow someone (D30).
  final bool failed;

  @override
  Widget build(BuildContext context) {
    if (failed && user.isFaculty) {
      return Text(
        'Unknown',
        key: Key('positionsUnknown-${user.uid}'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
      );
    }
    final c = counts;
    if (!user.isFaculty || c == null || (c.advising == 0 && c.panelling == 0)) {
      return const Text('None');
    }
    return Text('${c.advising} advising, ${c.panelling} on panels',
        key: Key('positions-${user.uid}'));
  }
}

/// The two designation checkboxes for one account.
///
/// Stateful because a refused write has to be shown. Spec §7: *"a refused
/// write says which write was refused … a coordinator hitting the self-edit
/// ban through some path the UI did not anticipate must be told that, not
/// 'something went wrong'."* Previously the write was neither awaited nor
/// caught, so a refusal became an unhandled Future error and the checkbox
/// silently snapped back to its old value on the next stream event -- which
/// also hid the real case in [UserRepository.setDesignation], where the
/// `users` write can succeed and the `facultyDirectory` mirror be refused,
/// leaving authority and mirror divergent with nothing on screen saying so.
class _DesignationCell extends ConsumerStatefulWidget {
  const _DesignationCell({required this.user, required this.isOwnRow});

  final AppUser user;

  /// The reader's own row. The `users` coordinator arm carries
  /// `request.auth.uid != uid` for ALL seven writable fields, not only
  /// `active`, so designating yourself is always refused -- the controls
  /// say so up front, exactly as the active switch does (spec §5.2, whose
  /// "controls disabled and the reason stated" is plural).
  final bool isOwnRow;

  @override
  ConsumerState<_DesignationCell> createState() => _DesignationCellState();
}

class _DesignationCellState extends ConsumerState<_DesignationCell> {
  Object? _error;

  Future<void> _write({bool? adviser, bool? panelist}) async {
    final user = widget.user;
    try {
      await ref.read(userRepositoryProvider).setDesignation(
            uid: user.uid,
            adviser: adviser ?? user.nominableAsAdviser,
            panelist: panelist ?? user.nominableAsPanelist,
          );
      if (mounted && _error != null) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final disabled = widget.isOwnRow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Wrap, not Row: this column is narrow at the shell's own rail
        // breakpoint, and a Row here has no way to give up horizontal
        // space -- it would silently clip "Panelist" off the edge instead
        // of dropping to a second line.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Checkbox(
              key: Key('adviserCheckbox-${user.uid}'),
              value: user.nominableAsAdviser,
              onChanged:
                  disabled ? null : (v) => _write(adviser: v ?? false),
            ),
            const Text('Adviser'),
            const SizedBox(width: AppTokens.sm),
            Checkbox(
              key: Key('panelistCheckbox-${user.uid}'),
              value: user.nominableAsPanelist,
              onChanged:
                  disabled ? null : (v) => _write(panelist: v ?? false),
            ),
            const Text('Panelist'),
          ],
        ),
        if (disabled)
          Text(
            'This is your own account — you cannot set your own '
            'designation.',
            key: Key('ownRowDesignationReason-${user.uid}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.xs),
            child: ErrorState(
              key: Key('designationWriteError-${user.uid}'),
              error: _error,
              message: 'Could not save the designation for '
                  '${user.fullName}. Their account may still say something '
                  'different from the nomination picker.',
            ),
          ),
      ],
    );
  }
}

class _ActiveCell extends ConsumerStatefulWidget {
  const _ActiveCell({required this.user, required this.isOwnRow});

  final AppUser user;
  final bool isOwnRow;

  @override
  ConsumerState<_ActiveCell> createState() => _ActiveCellState();
}

class _ActiveCellState extends ConsumerState<_ActiveCell> {
  Object? _error;

  Future<void> _setActive(bool value) async {
    // Only deactivation needs a guard: it signs the person out and locks them
    // out until reactivated, and the control is a switch a stray tap flips.
    // Reactivating is harmless and stays a single tap.
    if (!value) {
      final confirmed = await confirmAction(
        context,
        title: 'Deactivate this account?',
        message: '${widget.user.fullName} will be signed out and cannot sign '
            'back in until an account is reactivated.',
        confirmLabel: 'Deactivate',
        cancelLabel: 'Keep active',
        confirmKey: Key('confirmDeactivate-${widget.user.uid}'),
      );
      if (!confirmed || !mounted) return;
    }

    try {
      await ref.read(userRepositoryProvider).setActive(widget.user.uid, value);
      await _logActiveChange(value);
      if (mounted && _error != null) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Records who switched an account on or off. Best-effort and after the
  /// write: it swallows its own failure so the log can never block or undo
  /// the action — the same treatment the sign-in audit entries already get.
  Future<void> _logActiveChange(bool active) async {
    final actor = ref.read(signedInUidProvider);
    if (actor == null) return;
    try {
      await ref.read(auditServiceProvider).log(
            actorUid: actor,
            action: active ? 'account.activated' : 'account.deactivated',
            targetType: 'user',
            targetId: widget.user.uid,
          );
    } catch (_) {/* audit must never block the action */}
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
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
          onChanged: widget.isOwnRow ? null : _setActive,
        ),
        if (widget.isOwnRow)
          SizedBox(
            width: 160,
            child: Text(
              'This is your own account — you cannot activate or '
              'deactivate yourself.',
              key: Key('ownRowReason-${user.uid}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.xs),
            child: ErrorState(
              key: Key('activeWriteError-${user.uid}'),
              error: _error,
              message:
                  'Could not change whether ${user.fullName} is active.',
            ),
          ),
      ],
    );
  }
}
