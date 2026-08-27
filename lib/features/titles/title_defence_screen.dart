import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/candidate_title.dart';
import 'package:ethesishub/data/models/composing_indicator.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/title_comment.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
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

  void _startComposing(String candidateId, AppUser me, Thesis thesis) {
    _composingCandidateId = candidateId;
    final role = _roleOnThisThesis(thesis, me);
    final repo = ref.read(titleDefenceRepositoryProvider);
    repo.markComposing(
      thesisId: widget.thesisId,
      uid: me.uid,
      name: me.fullName,
      role: role,
      candidateTitleId: candidateId,
    );
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      final id = _composingCandidateId;
      if (id == null) return;
      repo.markComposing(
        thesisId: widget.thesisId,
        uid: me.uid,
        name: me.fullName,
        role: role,
        candidateTitleId: id,
      );
    });
  }

  void _stopComposing(AppUser me) {
    _heartbeat?.cancel();
    _heartbeat = null;
    _composingCandidateId = null;
    ref
        .read(titleDefenceRepositoryProvider)
        .clearComposing(thesisId: widget.thesisId, uid: me.uid);
  }

  /// The uploaded documents were written on submission and rendered
  /// nowhere: the panel could see three title strings and had no way to
  /// read a single justification, let alone the presentation.
  Future<void> _open(String? url, String what) async {
    if (url == null || url.isEmpty) {
      setState(() => _error = 'No $what was uploaded for this thesis.');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      setState(() => _error = 'That $what link is not a valid address.');
      return;
    }
    setState(() => _error = null);
    try {
      final opened = await (widget.openUrl ?? _realOpener)(uri);
      if (!opened && mounted) {
        setState(() => _error = 'Could not open the $what.');
      }
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
      return const LoadingState(label: 'Loading the title defence…');
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

    return KeyedSubtree(
      key: const Key('titleDefenceScreen'),
      child: PageShell(
        title: 'Title defence',
        subtitle: thesis.workingTitle,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(_error!,
                  key: const Key('error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
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
              final comments = commentsAsync.valueOrNull ?? const <TitleComment>[];
              final composing =
                  composingAsync.valueOrNull ?? const <ComposingIndicator>[];

              final now = DateTime.now();
              final active = composing
                  .where((c) => c.uid != me.uid && !c.isStaleAt(now))
                  .toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // One presentation for the whole defence, so it sits
                  // above the candidates rather than inside each card.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('openPresentation'),
                      icon: const Icon(Icons.slideshow_outlined),
                      onPressed: () => _open(
                          thesis.presentationUrl, 'presentation'),
                      label: const Text('Open the presentation'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (active.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        key: const Key('composingBanner'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          active
                              .map((c) => _composingText(c, candidates))
                              .join('\n'),
                        ),
                      ),
                    ),
                  for (final (index, candidate) in candidates.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: _CandidateCard(
                        candidate: candidate,
                        ordinal: index + 1,
                        onOpenJustification: () => _open(
                            candidate.justificationUrl, 'justification'),
                        comments: comments
                            .where((c) => c.candidateTitleId == candidate.id)
                            .toList(),
                        controller: _controllerFor(candidate.id),
                        focusNode: _focusNodeFor(candidate.id, me, thesis),
                        busy: _busyCandidateId(candidate.id),
                        isDean: isDean,
                        canDecide: thesis.status.value == 'titlePendingDefence',
                        onPost: () => _postComment(candidate.id, me, thesis),
                        onApprove: () => _approve(candidate.id, me.uid),
                      ),
                    ),
                  if (isDean) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    if (!_rejecting)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          key: const Key('rejectSet'),
                          onPressed: () => setState(() => _rejecting = true),
                          child: const Text('Reject this set'),
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('rejectRemark'),
                            controller: _rejectController,
                            decoration: const InputDecoration(
                              labelText: 'Why is this set being rejected?',
                            ),
                            minLines: 2,
                            maxLines: 4,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              FilledButton(
                                key: const Key('confirmReject'),
                                onPressed: _busyReject
                                    ? null
                                    : () => _confirmReject(me.uid),
                                child: Text(_busyReject
                                    ? 'Rejecting…'
                                    : 'Confirm rejection'),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _rejecting = false),
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ],
                      ),
                  ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Each candidate is numbered and its own remarks are boxed
            // beneath it, so a panel scrolling a ten-candidate defence can
            // tell where one ends and the next begins. Previously every
            // title, comment and box ran together in one column.
            Text('Candidate $ordinal',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    )),
            const SizedBox(height: 4),
            Text(candidate.titleText,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: Key('openJustification-${candidate.id}'),
                icon: const Icon(Icons.description_outlined, size: 18),
                onPressed: onOpenJustification,
                label: const Text('Open the justification'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (comments.isEmpty)
                    Text('No remarks on this candidate yet.',
                        style: Theme.of(context).textTheme.bodySmall)
                  else
                    for (final comment in comments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${comment.authorName} — ${comment.authorRole}: '
                          '${comment.body}',
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('commentBox-${candidate.id}'),
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(labelText: 'Add a comment'),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  key: Key('postComment-${candidate.id}'),
                  onPressed: busy ? null : onPost,
                  child: Text(busy ? 'Posting…' : 'Post comment'),
                ),
                if (isDean && canDecide) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      key: Key('approve-${candidate.id}'),
                      onPressed: busy ? null : onApprove,
                      child: const Text('Approve this title'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
