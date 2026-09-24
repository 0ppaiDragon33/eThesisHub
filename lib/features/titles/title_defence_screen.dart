import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/composing_indicator.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// Opens an uploaded document. Injectable so a widget test can assert the
/// panel really can reach a justification without a platform browser.
typedef UrlOpener = Future<bool> Function(Uri url);

/// `url_launcher` rather than `dart:io`: this app ships to Web as well as
/// Android, and `dart:io` does not exist there. `externalApplication` opens
/// a new tab on Web and the system viewer on Android, so a PDF or a PPTX
/// is handed to something that can actually display it.
Future<bool> _realOpener(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

/// The position this person holds on THIS thesis, which is what a comment
/// records. Not their account role: a coordinator sitting as a nominated
/// panel member comments as a panel member.
String _roleOnThisThesis(Thesis thesis, AppUser me) {
  if (thesis.adviserUid == me.uid) return 'Adviser';
  if (thesis.panelistUids.contains(me.uid)) return 'Panel Member';
  return switch (me.role) {
    UserRole.coordinator => 'Research Coordinator',
    UserRole.dean => 'Dean',
    _ => 'Panel Member',
  };
}

/// The room the title defence actually runs in.
///
/// One screen for the whole panel — every panel member watches the same
/// candidates, posts remarks that appear live for everyone else, and sees who
/// else is currently composing. The Dean, who is also a panel member, gets an
/// addition rather than a separate screen: buttons to approve one candidate
/// or reject the whole set with a required remark.
///
/// Reached at `/defence/:thesisId` from the faculty, Dean and Coordinator
/// dashboards.
class TitleDefenceScreen extends ConsumerStatefulWidget {
  const TitleDefenceScreen({
    super.key,
    required this.thesisId,
    this.openUrl,
  });

  final String thesisId;

  /// Defaults to the real launcher. See [UrlOpener].
  final UrlOpener? openUrl;

  @override
  ConsumerState<TitleDefenceScreen> createState() =>
      _TitleDefenceScreenState();
}

class _TitleDefenceScreenState extends ConsumerState<TitleDefenceScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};

  Timer? _heartbeat;
  String? _composingCandidateId;

  bool _busyCandidateId(String id) => _busyComment == id;
  String? _busyComment;

  bool _rejecting = false;
  bool _busyReject = false;
  final _rejectController = TextEditingController();

  String? _error;

  TextEditingController _controllerFor(String candidateId) {
    return _controllers.putIfAbsent(candidateId, () => TextEditingController());
  }

  FocusNode _focusNodeFor(String candidateId, AppUser me, Thesis thesis) {
    return _focusNodes.putIfAbsent(candidateId, () {
      final node = FocusNode();
      node.addListener(() {
        if (node.hasFocus) {
          _startComposing(candidateId, me, thesis);
        } else {
          _stopComposing(me);
        }
      });
      return node;
    });
  }

  /// Fires a presence write and swallows its refusal.
  ///
  /// The "is writing" marker is decoration, and `firestore.rules` refuses it
  /// outright to anyone not on the panel: `titleComposing` allows create
  /// only for `isOnPanel()`, while get/list also allows the Coordinator and
  /// the Dean. So a Coordinator or Dean reading this screen is shown a
  /// comment box, focuses it, and the write is denied — once on focus and
  /// then again on every heartbeat.
  ///
  /// Nothing awaits these writes, so each refusal escaped to the browser as
  /// "Uncaught (in promise) [cloud_firestore/permission-denied]". Losing a
  /// marker costs a reader nothing; it must not be reported as a failure.
  void _presence(Future<void> write) {
    write.catchError((Object _) {});
  }

  void _startComposing(String candidateId, AppUser me, Thesis thesis) {
    _composingCandidateId = candidateId;
    final role = _roleOnThisThesis(thesis, me);
    final repo = ref.read(titleDefenceRepositoryProvider);
    _presence(repo.markComposing(
      thesisId: widget.thesisId,
      uid: me.uid,
      name: me.fullName,
      role: role,
      candidateTitleId: candidateId,
    ));
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      final id = _composingCandidateId;
      if (id == null) return;
      _presence(repo.markComposing(
        thesisId: widget.thesisId,
        uid: me.uid,
        name: me.fullName,
        role: role,
        candidateTitleId: id,
      ));
    });
  }

  void _stopComposing(AppUser me) {
    _heartbeat?.cancel();
    _heartbeat = null;
    _composingCandidateId = null;
    _presence(ref
        .read(titleDefenceRepositoryProvider)
        .clearComposing(thesisId: widget.thesisId, uid: me.uid));
  }

  /// The uploaded documents were written on submission and rendered
  /// nowhere: the panel could see three title strings and had no way to
  /// read a single justification, let alone the presentation.
  ///
  /// Takes the storage PATH, not a URL. The bucket is private, so the link
  /// is minted per-open by the `document-url` function, which checks that
  /// this panel member is on this thesis before it signs — a stored public
  /// URL would have opened for anyone who ever saw it.
  Future<void> _open(String? path, String what) async {
    if (path == null || path.isEmpty) {
      setState(() => _error = 'No $what was uploaded for this thesis.');
      return;
    }
    setState(() => _error = null);
    try {
      final url = await ref.read(storageServiceProvider).signedUrl(path);
      final uri = Uri.tryParse(url);
      if (uri == null) {
        if (mounted) setState(() => _error = 'That $what link is not valid.');
        return;
      }
      final opened = await (widget.openUrl ?? _realOpener)(uri);
      if (!opened && mounted) {
        setState(() => _error = 'Could not open the $what.');
      }
    } on StorageFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the $what.');
    }
  }

  Future<void> _postComment(
    String candidateId,
    AppUser me,
    Thesis thesis,
  ) async {
    if (_busyComment != null) return;
    final controller = _controllerFor(candidateId);
    final text = controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Write a comment before posting.');
      return;
    }

    setState(() {
      _busyComment = candidateId;
      _error = null;
    });

    try {
      await ref.read(titleDefenceRepositoryProvider).addComment(
            thesisId: widget.thesisId,
            candidateTitleId: candidateId,
            authorUid: me.uid,
            authorName: me.fullName,
            authorRole: _roleOnThisThesis(thesis, me),
            body: text,
          );
      controller.clear();
      _focusNodes[candidateId]?.unfocus();
      _stopComposing(me);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to comment on this thesis.'
            : 'Could not post the comment. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not post the comment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busyComment = null);
    }
  }

  Future<void> _approve(String candidateId, String deanUid) async {
    if (_busyComment != null) return;
    setState(() {
      _busyComment = candidateId;
      _error = null;
    });
    try {
      await ref.read(titleDefenceRepositoryProvider).approveTitle(
            thesisId: widget.thesisId,
            candidateTitleId: candidateId,
            deanUid: deanUid,
          );
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to approve this title.'
            : 'Could not record the approval. Please try again.');
      }
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not record the approval. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busyComment = null);
    }
  }

  Future<void> _confirmReject(String deanUid) async {
    if (_busyReject) return;
    final remark = _rejectController.text.trim();
    if (remark.isEmpty) {
      setState(() => _error = 'Say why the set is being rejected.');
      return;
    }

    setState(() {
      _busyReject = true;
      _error = null;
    });

    try {
      await ref.read(titleDefenceRepositoryProvider).rejectTitles(
            thesisId: widget.thesisId,
            deanUid: deanUid,
            remark: remark,
          );
      _rejectController.clear();
      if (mounted) setState(() => _rejecting = false);
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to reject these titles.'
            : 'Could not record the rejection. Please try again.');
      }
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not record the rejection. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busyReject = false);
    }
  }

  @override
  void dispose() {
    // A periodic timer that outlives this screen would keep writing to
    // Firestore forever — Spark allows only 20,000 writes a day.
    _heartbeat?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final n in _focusNodes.values) {
      n.dispose();
    }
    _rejectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside a handler: watching in build guarantees
    // a settled value is already available by the time the user can act, so
    // no handler races the auth stream's first event.
    ref.watch(authStateProvider);
    final meAsync = ref.watch(currentUserProvider);
    final thesisAsync = ref.watch(thesisByIdProvider(widget.thesisId));
    final candidatesAsync = ref.watch(candidateTitlesProvider(widget.thesisId));
    final commentsAsync = ref.watch(titleCommentsProvider(widget.thesisId));
    final composingAsync = ref.watch(composingProvider(widget.thesisId));

    // Loading / error / not-found are kept as separate branches: collapsing
    // loading into another state has previously told a user their thesis had
    // moved on while it was still loading.
    // None of these states carries a Scaffold any more: the app shell owns
    // it, along with the app bar and the sidebar, for every signed-in
    // route.
    if (meAsync.isLoading || thesisAsync.isLoading) {
      return const PageShell(
        maxWidth: 900,
        children: [LoadingState.page(label: 'Loading the title defence…')],
      );
    }
    if (meAsync.hasError) {
      return PageShell(children: [
        ErrorState(
          error: meAsync.error,
          message: 'Could not load your account.',
        ),
      ]);
    }
    if (thesisAsync.hasError) {
      return PageShell(children: [
        ErrorState(
          error: thesisAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }

    final me = meAsync.valueOrNull;
    final thesis = thesisAsync.valueOrNull;
    if (me == null || thesis == null) {
      return const PageShell(children: [
        EmptyState(
          icon: Icons.search_off,
          title: 'Thesis not found',
          message: 'This thesis no longer exists, or it belongs to '
              'another group.',
        ),
      ]);
    }

    final isDean = me.role == UserRole.dean;

    final text = Theme.of(context).textTheme;

    return KeyedSubtree(
      key: const Key('titleDefenceScreen'),
      child: PageShell(
        maxWidth: 900,
        kicker: 'Title defence, round ${thesis.titleRound}',
        title: thesis.workingTitle,
        subtitle: isDean
            ? 'Read each candidate and the panel\'s remarks, then approve '
                'one title or return the set.'
            : 'Read each candidate and its justification, and leave your '
                'remarks for the group.',
        actions: [
          OutlinedButton.icon(
            key: const Key('openPresentation'),
            icon: const Icon(Icons.slideshow_outlined, size: 18),
            onPressed: () => _open(thesis.presentationPath, 'presentation'),
            label: const Text('Open presentation'),
          ),
        ],
        children: [
          if (_error != null) ...[
            ErrorState(key: const Key('error'), message: _error!),
            const Gap.md(),
          ],
          candidatesAsync.when(
            loading: () => const LoadingState(label: 'Loading candidates…'),
            error: (e, _) => ErrorState(
              error: e,
              message: 'Could not load the candidate titles.',
            ),
            data: (allCandidates) {
              final candidates = allCandidates
                  .where((c) => c.round == thesis.titleRound)
                  .toList();
              final comments =
                  commentsAsync.valueOrNull ?? const <TitleComment>[];
              final composing =
                  composingAsync.valueOrNull ?? const <ComposingIndicator>[];

              final now = DateTime.now();
              final active = composing
                  .where((c) => c.uid != me.uid && !c.isStaleAt(now))
                  .toList();
              final canDecide =
                  thesis.status.value == 'titlePendingDefence';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: active.isEmpty
                        ? const SizedBox(width: double.infinity)
                        : Container(
                            key: const Key('composingBanner'),
                            width: double.infinity,
                            margin:
                                const EdgeInsets.only(bottom: AppTokens.md),
                            padding: const EdgeInsets.all(AppTokens.md - 4),
                            decoration: BoxDecoration(
                              color: Palette.of(context)
                                  .seal
                                  .withValues(alpha: 0.07),
                              borderRadius:
                                  BorderRadius.circular(AppTokens.radiusSm),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.edit_note_rounded,
                                    color: Palette.of(context).seal),
                                const SizedBox(width: AppTokens.sm),
                                Expanded(
                                  child: Text(
                                    active
                                        .map((c) =>
                                            _composingText(c, candidates))
                                        .join('\n'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  for (final (index, candidate) in candidates.indexed) ...[
                    _CandidateCard(
                      candidate: candidate,
                      ordinal: index + 1,
                      onOpenJustification: () => _open(
                          candidate.justificationPath, 'justification'),
                      comments: comments
                          .where((c) => c.candidateTitleId == candidate.id)
                          .toList(),
                      controller: _controllerFor(candidate.id),
                      focusNode: _focusNodeFor(candidate.id, me, thesis),
                      busy: _busyCandidateId(candidate.id),
                      isDean: isDean,
                      canDecide: canDecide,
                      onPost: () => _postComment(candidate.id, me, thesis),
                      onApprove: () => _approve(candidate.id, me.uid),
                    ),
                    const Gap.md(),
                  ],
                  if (isDean)
                    Panel(
                      title: 'Return the whole set',
                      subtitle: 'The group reads your remark and submits a '
                          'new round',
                      icon: Icons.undo_rounded,
                      child: !_rejecting
                          ? Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                key: const Key('rejectSet'),
                                onPressed: () =>
                                    setState(() => _rejecting = true),
                                child: const Text('Reject this set'),
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FormRow(
                                  label: 'Why is this set being rejected?',
                                  child: TextField(
                                    key: const Key('rejectRemark'),
                                    controller: _rejectController,
                                    minLines: 2,
                                    maxLines: 4,
                                    autofocus: true,
                                  ),
                                ),
                                Wrap(
                                  spacing: AppTokens.sm,
                                  children: [
                                    FilledButton(
                                      key: const Key('confirmReject'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            Tone.returned.color(context),
                                      ),
                                      onPressed: _busyReject
                                          ? null
                                          : () => _confirmReject(me.uid),
                                      child: Text(_busyReject
                                          ? 'Rejecting…'
                                          : 'Confirm rejection'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          setState(() => _rejecting = false),
                                      child: const Text('Cancel'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    )
                  else
                    Text(
                      'Only the Dean records the decision.',
                      style: text.bodySmall,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _composingText(
      ComposingIndicator c, List<CandidateTitle> candidates) {
    final candidate = candidates.where((x) => x.id == c.candidateTitleId);
    final label = candidate.isEmpty ? 'a candidate' : candidate.first.titleText;
    return '${c.name} is writing a comment on $label…';
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.ordinal,
    required this.onOpenJustification,
    required this.comments,
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.isDean,
    required this.canDecide,
    required this.onPost,
    required this.onApprove,
  });

  final CandidateTitle candidate;
  final int ordinal;
  final VoidCallback onOpenJustification;
  final List<TitleComment> comments;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool isDean;
  final bool canDecide;
  final VoidCallback onPost;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = Palette.of(context);

    return Panel(
      flush: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The candidate.
          Padding(
            padding: const EdgeInsets.all(AppTokens.lg - 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.seal,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$ordinal',
                    semanticsLabel: 'Candidate $ordinal',
                    style: text.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
                const SizedBox(width: AppTokens.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Candidate $ordinal',
                          style: text.labelMedium?.copyWith(color: p.seal)),
                      const SizedBox(height: 2),
                      Text(candidate.titleText, style: text.titleLarge),
                      const SizedBox(height: AppTokens.xs),
                      TextButton.icon(
                        key: Key('openJustification-${candidate.id}'),
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 36)),
                        icon: const Icon(Icons.description_outlined, size: 18),
                        onPressed: onOpenJustification,
                        label: const Text('Open the justification'),
                      ),
                      if (isDean && canDecide) ...[
                        const SizedBox(height: AppTokens.sm),
                        FilledButton.icon(
                          key: Key('approve-${candidate.id}'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Tone.endorsed.color(context),
                          ),
                          onPressed: busy ? null : onApprove,
                          icon: const Icon(Icons.verified_outlined, size: 18),
                          label: const Text('Approve this title'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // The remarks.
          Container(
            color: p.canvas,
            padding: const EdgeInsets.fromLTRB(
                AppTokens.lg - 4, AppTokens.md, AppTokens.lg - 4, AppTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  comments.isEmpty
                      ? 'Remarks'
                      : comments.length == 1
                          ? '1 remark'
                          : '${comments.length} remarks',
                  style: text.labelMedium,
                ),
                const SizedBox(height: AppTokens.sm),
                if (comments.isEmpty)
                  Text('No remarks on this candidate yet.',
                      style: text.bodySmall)
                else
                  for (final comment in comments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.md - 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InitialsAvatar(comment.authorName, size: 30),
                          const SizedBox(width: AppTokens.sm + 2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${comment.authorName}, '
                                  '${comment.authorRole}',
                                  style: text.labelMedium,
                                ),
                                const SizedBox(height: 2),
                                Text(comment.body, style: text.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: AppTokens.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('commentBox-${candidate.id}'),
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          hintText: 'Add a remark on this candidate',
                        ),
                        minLines: 1,
                        maxLines: 4,
                      ),
                    ),
                    const SizedBox(width: AppTokens.sm),
                    FilledButton(
                      key: Key('postComment-${candidate.id}'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 52)),
                      onPressed: busy ? null : onPost,
                      child: Text(busy ? 'Posting…' : 'Post'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
