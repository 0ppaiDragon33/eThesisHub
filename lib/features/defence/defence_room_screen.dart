import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The live comment log every participant watches during the presentation.
///
/// Comments may be written only while `defence.status.acceptsComments` --
/// i.e. only while the defence is `inProgress`. The security rules and
/// [DefenceRepository.addComment] both enforce that independently, but this
/// screen never offers a control that would always fail: the comment box is
/// hidden, with the reason shown instead, whenever the gate is closed.
///
/// `authorPosition` is derived from the signed-in user's relationship to
/// THIS defence -- not from their account role -- because the position held
/// at a defence must not change retroactively when the account's role does
/// later. See [Defence]'s and [DefenceComment]'s own doc comments.
class DefenceRoomScreen extends ConsumerStatefulWidget {
  const DefenceRoomScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<DefenceRoomScreen> createState() => _DefenceRoomScreenState();
}

class _DefenceRoomScreenState extends ConsumerState<DefenceRoomScreen> {
  final _bodyController = TextEditingController();
  bool _posting = false;
  bool _statusBusy = false;
  String? _commentError;
  String? _statusError;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  /// `'Adviser'` if the signed-in uid matches this defence's adviser,
  /// `'Panel Member'` if it sits among this defence's panel, else the
  /// account's own role for a coordinator or dean. Null for anyone else --
  /// which is exactly who [_canComment] also refuses.
  String? _authorPositionFor(Defence defence, String? uid, UserRole? role) {
    if (uid == null) return null;
    if (uid == defence.adviserUid) return 'Adviser';
    if (defence.panelUids.contains(uid)) return 'Panel Member';
    if (role == UserRole.coordinator) return 'Coordinator';
    if (role == UserRole.dean) return 'Dean';
    return null;
  }

  bool _canComment(Defence defence, String? uid, UserRole? role) {
    if (!defence.status.acceptsComments) return false;
    return _authorPositionFor(defence, uid, role) != null;
  }

  String _commentReasonFor(Defence defence, String? uid, UserRole? role) {
    switch (defence.status) {
      case DefenceStatus.scheduled:
        return 'The comment log opens once the defence begins.';
      case DefenceStatus.completed:
        return 'This defence is closed. The comment log cannot be added to '
            'anymore.';
      case DefenceStatus.inProgress:
        return 'Only the adviser, the panel, the coordinator, or the dean '
            'may comment here.';
    }
  }

  Future<void> _postComment({
    required String uid,
    required String authorName,
    required String authorPosition,
  }) async {
    if (_posting) return;
    final body = _bodyController.text;

    setState(() {
      _posting = true;
      _commentError = null;
    });

    try {
      await ref.read(defenceRepositoryProvider).addComment(
            defenceId: widget.defenceId,
            authorUid: uid,
            authorName: authorName,
            authorPosition: authorPosition,
            body: body,
          );
      if (mounted) _bodyController.clear();
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _commentError = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _commentError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _commentError = e.code == 'permission-denied'
            ? 'You do not have permission to comment here '
                '[permission-denied].'
            : 'Could not post that comment. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _commentError = 'Could not post that comment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _setStatus(DefenceStatus status) async {
    if (_statusBusy) return;

    setState(() {
      _statusBusy = true;
      _statusError = null;
    });

    try {
      await ref.read(defenceRepositoryProvider).setStatus(
            defenceId: widget.defenceId,
            status: status,
          );
    } on StateError catch (e) {
      if (mounted) setState(() => _statusError = e.message);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _statusError = e.code == 'permission-denied'
            ? 'You do not have permission to change this defence\'s status '
                '[permission-denied].'
            : 'Could not update this defence. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() =>
            _statusError = 'Could not update this defence. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  /// Wraps every non-content state in the same Scaffold + AppBar the loaded
  /// screen uses, so a room still loading its defence, its log, or the
  /// signed-in profile is never a bare, unnavigable page.
  Widget _framed(List<Widget> children, {String? title}) {
    return Scaffold(
      key: const Key('defenceRoom'),
      appBar: AppBar(title: Text(title ?? 'Defence room')),
      body: PageShell(children: children),
    );
  }

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

    if (commentsAsync.isLoading) {
      return _framed(
        const [LoadingState(label: 'Loading comments…')],
        title: defence.type.label,
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
        title: defence.type.label,
      );
    }
    final comments = commentsAsync.valueOrNull ?? const <DefenceComment>[];

    if (meAsync.isLoading) {
      return _framed(
        const [LoadingState(label: 'Loading your profile…')],
        title: defence.type.label,
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
        title: defence.type.label,
      );
    }
    final me = meAsync.valueOrNull;
    final role = me?.role;

    // Coordinator only -- not the dean, who also grants comment access but
    // does not drive the room's own open/close lifecycle.
    final isCoordinator = role == UserRole.coordinator;
    final canComment = _canComment(defence, uid, role);
    final authorPosition = _authorPositionFor(defence, uid, role);

    // Thesis title only, shown for orientation; never gates the room --
    // this stream is not one of the three the room depends on to function.
    final thesisTitle =
        ref.watch(thesisByIdProvider(defence.thesisId)).valueOrNull?.workingTitle;

    return Scaffold(
      key: const Key('defenceRoom'),
      appBar: AppBar(title: Text(defence.type.label)),
      body: PageShell(
        title: defence.type.label,
        subtitle: thesisTitle,
        children: [
          for (final c in comments)
            Card(
              key: Key('commentRow-${c.id}'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${c.authorName} — ${c.authorPosition}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(c.body),
                  ],
                ),
              ),
            ),
          if (comments.isEmpty)
            const EmptyState(
              icon: Icons.forum_outlined,
              title: 'No comments yet',
              message: 'Remarks made during the defence will appear here.',
            ),
          const Gap.lg(),
          if (canComment) ...[
            TextField(
              key: const Key('commentBody'),
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Add a comment'),
              minLines: 2,
              maxLines: 4,
            ),
            const Gap.md(),
            if (_commentError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _commentError!,
                  key: const Key('commentError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('postComment'),
              onPressed: _posting || uid == null || authorPosition == null
                  ? null
                  : () => _postComment(
                        uid: uid,
                        authorName: me?.fullName ?? '',
                        authorPosition: authorPosition,
                      ),
              child: Text(_posting ? 'Posting…' : 'Post comment'),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _commentReasonFor(defence, uid, role),
                key: const Key('commentReason'),
              ),
            ),
          const Gap.lg(),
          if (_statusError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _statusError!,
                key: const Key('statusError'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          // Hidden rather than merely disabled for anyone but the
          // coordinator: the rules deny the write either way, but a button
          // that always fails is worse than no button at all.
          if (isCoordinator && defence.status == DefenceStatus.scheduled)
            FilledButton(
              key: const Key('openDefence'),
              onPressed:
                  _statusBusy ? null : () => _setStatus(DefenceStatus.inProgress),
              child: Text(_statusBusy ? 'Opening…' : 'Open defence'),
            ),
          if (isCoordinator && defence.status == DefenceStatus.inProgress)
            FilledButton(
              key: const Key('closeDefence'),
              onPressed:
                  _statusBusy ? null : () => _setStatus(DefenceStatus.completed),
              child: Text(_statusBusy ? 'Closing…' : 'Close defence'),
            ),
        ],
      ),
    );
  }
}
