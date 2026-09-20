import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/features/titles/consolidated_comments.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// The consolidated, per-commenter record of one defence — Guidelines §4d.
///
/// The adviser is the person who furnishes the group's copy: they group the
/// panel's and their own remarks into bracketed blocks (via [blocksFor], the
/// same grouping M1b uses for title comments) and RELEASE them. Release is
/// the moment `consolidatedAt` is written, and it is the only thing that
/// opens the log to the student group -- the security rules' group read arm
/// requires `'consolidatedAt' in parent()` independently of anything this
/// screen does, so a leader who has not been released to sees nothing here
/// even if this screen's own gating were ever removed.
///
/// Everyone who actually sat at the defence -- the adviser, the panel, the
/// coordinator, the dean -- already heard every remark live in
/// [DefenceRoomScreen] while the defence was in progress, so this screen
/// does not re-hide the blocks from them before release. Only the group
/// (identified by `defence.leaderUid`, the one snapshot the defence model
/// keeps for the student side) is gated on [Defence.isReleased].
class ConsolidatedDefenceScreen extends ConsumerStatefulWidget {
  const ConsolidatedDefenceScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<ConsolidatedDefenceScreen> createState() =>
      _ConsolidatedDefenceScreenState();
}

class _ConsolidatedDefenceScreenState
    extends ConsumerState<ConsolidatedDefenceScreen> {
  bool _releasing = false;
  String? _releaseError;

  Future<void> _release() async {
    if (_releasing) return;

    setState(() {
      _releasing = true;
      _releaseError = null;
    });

    try {
      await ref.read(defenceRepositoryProvider).release(widget.defenceId);
    } on StateError catch (e) {
      if (mounted) setState(() => _releaseError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _releaseError = e.code == 'permission-denied'
            ? 'You do not have permission to release these comments '
                '[permission-denied].'
            : 'Could not release these comments. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _releaseError =
            'Could not release these comments. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _releasing = false);
    }
  }

  /// Wraps every non-content state in the same frame the loaded screen
  /// uses, so a page still loading its defence, its comment log, or the
  /// signed-in profile is never a bare, unnavigable page.
  ///
  /// The Scaffold and AppBar moved to the app shell, which titles this
  /// route 'Consolidated comments' for every one of these states — hence
  /// the [title] override being gone: it named the app bar, and there is
  /// no longer an app bar here to name. What the page is showing is said
  /// by [PageShell]'s own heading instead.
  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('consolidated'),
        child: PageShell(children: children),
      );

  @override
  Widget build(BuildContext context) {
    final defenceAsync = ref.watch(defenceProvider(widget.defenceId));
    final commentsAsync = ref.watch(defenceCommentsProvider(widget.defenceId));
    final meAsync = ref.watch(currentUserProvider);
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;

    // Each of the three streams gets its own isLoading/hasError branch,
    // checked apart from the others -- collapsing them would tell a viewer
    // whose comment log is merely still connecting that the defence itself
    // does not exist, or vice versa.
    if (defenceAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading defence…')]);
    }
    if (defenceAsync.hasError) {
      return _framed([
        ErrorState(
          error: defenceAsync.error,
          message: 'Could not load this defence.',
        ),
      ]);
    }
    final defence = defenceAsync.valueOrNull;
    if (defence == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defence not found',
          message: 'This defence no longer exists.',
        ),
      ]);
    }

    // The leader's not-released gate is decided from `defence` alone,
    // BEFORE the comments stream is even consulted. `firestore.rules`
    // denies a leader ANY read of `comments` until `consolidatedAt` exists,
    // so a real leader's `commentsAsync` reaches `hasError` here with a
    // permission-denied `FirebaseException` -- and checking that branch
    // first would show "Could not load the comment log." in place of the
    // actual reason: `fake_cloud_firestore` enforces no rules, so that
    // failure is invisible in this suite unless the comments stream is
    // deliberately overridden with an error (see the falsification test).
    final isLeader = uid != null && uid == defence.leaderUid;
    if (isLeader && !defence.isReleased) {
      return _framed(
        [
          const EmptyState(
            icon: Icons.lock_clock_outlined,
            title: 'Not released yet',
            message: 'Your adviser releases the panel\'s consolidated '
                'comments after the defence is closed.',
            action: Text(
              'The adviser has not released these comments yet.',
              key: Key('notReleasedReason'),
            ),
          ),
        ],
      );
    }

    if (commentsAsync.isLoading) {
      return _framed(
        const [LoadingState(label: 'Loading comments…')],
      );
    }
    if (commentsAsync.hasError) {
      return _framed(
        [
          ErrorState(
            error: commentsAsync.error,
            message: 'Could not load the comment log.',
          ),
        ],
      );
    }
    final comments = commentsAsync.valueOrNull ?? const <DefenceComment>[];

    if (meAsync.isLoading) {
      return _framed(
        const [LoadingState(label: 'Loading your profile…')],
      );
    }
    if (meAsync.hasError) {
      return _framed(
        [
          ErrorState(
            error: meAsync.error,
            message: 'Could not load your profile.',
          ),
        ],
      );
    }

    final isAdviser = uid != null && uid == defence.adviserUid;

    // The group's gate: everyone who was actually in the room already heard
    // these remarks live, so only the leader is held back until release.
    // `isLeader` itself was already decided above, before the comments
    // stream was consulted -- an unreleased leader never reaches this line.
    final canSeeBlocks = defence.isReleased || !isLeader;

    // blocksFor groups by authorUid+authorRole and returns CommentBlocks that
    // no longer carry the uid, so a parallel list of first-seen author uids
    // (grouped the identical way) is built to key each Card. The two lists
    // stay in lockstep because both walk `comments` with the same grouping
    // key, in the same order.
    final remarks = [
      for (final c in comments)
        (
          authorUid: c.authorUid,
          authorName: c.authorName,
          authorRole: c.authorPosition,
          body: c.body,
        ),
    ];
    final blocks = blocksFor(remarks);

    final authorUidsInOrder = <String>[];
    final seenKeys = <String>{};
    for (final c in comments) {
      final key = '${c.authorUid}|${c.authorPosition}';
      if (seenKeys.add(key)) authorUidsInOrder.add(c.authorUid);
    }

    final text = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: const Key('consolidated'),
      child: PageShell(
        kicker: defence.type.label,
        title: 'Consolidated comments',
        subtitle: 'Every remark from the session, grouped by the panel '
            'member who made it.',
        actions: [
          ToneBadge(
            label: defence.isReleased
                ? 'Released to the group'
                : 'Not yet released',
            tone: defence.isReleased ? Tone.endorsed : Tone.awaiting,
            icon: defence.isReleased
                ? Icons.lock_open_rounded
                : Icons.lock_outline_rounded,
          ),
        ],
        children: [
          if (isAdviser && !defence.isReleased) ...[
            Panel(
              emphasis: true,
              title: 'Release to the group',
              icon: Icons.send_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_releaseError != null) ...[
                    ErrorState(
                        key: const Key('releaseError'),
                        message: _releaseError!),
                    const Gap.sm(),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          defence.status != DefenceStatus.completed
                              ? 'Release once the defence is completed, so '
                                  'the log is the whole record.'
                              : 'The group will be able to read everything '
                                  'below.',
                          key: defence.status != DefenceStatus.completed
                              ? const Key('releaseReason')
                              : null,
                          style: text.bodySmall,
                        ),
                      ),
                      const SizedBox(width: AppTokens.md),
                      FilledButton(
                        key: const Key('releaseComments'),
                        onPressed: _releasing ||
                                defence.status != DefenceStatus.completed
                            ? null
                            : _release,
                        child: Text(
                            _releasing ? 'Releasing…' : 'Release comments'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap.md(),
          ],
          if (canSeeBlocks) ...[
            if (blocks.isEmpty)
              const EmptyState(
                icon: Icons.forum_outlined,
                title: 'No comments yet',
                message: 'There is nothing to consolidate yet.',
              )
            else
              for (var i = 0; i < blocks.length; i++) ...[
                Panel(
                  key: Key('blockFor-${authorUidsInOrder[i]}'),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InitialsAvatar(blocks[i].header, size: 36),
                      const SizedBox(width: AppTokens.md - 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(blocks[i].header, style: text.labelLarge),
                            for (final body in blocks[i].bodies)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: AppTokens.sm),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          top: 8, right: AppTokens.sm),
                                      child: Container(
                                        width: 5,
                                        height: 5,
                                        decoration: BoxDecoration(
                                          color: Palette.of(context).muted,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(body,
                                          style: text.bodyMedium),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap.md(),
              ],
          ] else
            const Text(
              'The adviser has not released these comments yet.',
              key: Key('notReleasedReason'),
            ),
        ],
      ),
    );
  }
}
