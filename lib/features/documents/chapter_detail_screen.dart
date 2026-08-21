import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// One chapter's full history: every version uploaded and every remark an
/// adviser or panelist has left on it.
///
/// Reached from the chapters list at
/// `/thesis/chapters/<chapterId>?id=<thesisId>`.
class ChapterDetailScreen extends ConsumerStatefulWidget {
  const ChapterDetailScreen({
    super.key,
    required this.thesisId,
    required this.chapter,
    this.pickDocument,
  });

  final String thesisId;
  final ChapterId chapter;

  /// Injectable so a widget test can reach the upload path without a
  /// platform file dialog, matching [SubmitTitlesScreen.pickDocument].
  /// Accepted and stored here; wiring it to an actual upload is the next
  /// task -- this screen only needs somewhere to keep it so that task does
  /// not have to touch this constructor again.
  final DocumentPicker? pickDocument;

  @override
  ConsumerState<ChapterDetailScreen> createState() =>
      _ChapterDetailScreenState();
}

class _ChapterDetailScreenState extends ConsumerState<ChapterDetailScreen> {
  bool _busy = false;
  String? _error;

  final _feedbackController = TextEditingController();
  bool _feedbackBusy = false;
  String? _feedbackError;

  bool _statusBusy = false;
  String? _statusError;

  Future<void> _upload() async {
    if (_busy) return;
    final pick = widget.pickDocument ?? realPicker;
    final file = await pick(allowed: kChapterTypes);
    if (file == null) return;

    final invalid = validateDocument(file,
        allowed: kChapterTypes, maxBytes: kChapterMaxBytes);
    if (invalid != null) {
      if (mounted) setState(() => _error = invalid);
      return;
    }

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) {
      // The user has already picked a file by this point. A silent return
      // here means they choose a file and nothing happens at all -- no
      // spinner, no message -- and on a project with no server-side logs
      // this screen is the only place the cause could ever surface.
      if (mounted) {
        setState(() =>
            _error = 'You appear to be signed out. Sign in again and retry.');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final storage = ref.read(storageServiceProvider);
    StoredFile? stored;
    try {
      stored = await uploadDocument(
        storage: storage,
        file: file,
        thesisId: widget.thesisId,
        documentId: widget.chapter.value,
      );
      await ref.read(documentRepositoryProvider).addVersion(
            thesisId: widget.thesisId,
            chapter: widget.chapter,
            storagePath: stored.path,
            fileUrl: stored.url,
            mimeType: file.contentType,
            sizeBytes: file.bytes.length,
            uploadedBy: uid,
          );
    } on StorageFailure catch (e) {
      if (mounted) setState(() => _error = '${e.message} [${e.code}]');
    } on FirebaseException catch (e) {
      // A denied write leaves the file uploaded and unreferenced, exactly as
      // any other post-upload failure does, so the cleanup runs here too.
      if (stored != null) {
        try {
          await storage.delete(stored.path);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to upload to this chapter.'
            : 'Could not upload this version.');
      }
    } catch (e) {
      // The file is already in a public bucket but the record that would
      // reference it was never written. Remove the orphan, best-effort:
      // a failed cleanup must never replace the real failure.
      if (stored != null) {
        try {
          await storage.delete(stored.path);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _error =
            e is StateError ? e.message : 'Could not upload this version.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Posts one remark against the version the adviser is looking at right
  /// now. `currentVersion` is passed in by the caller rather than read off
  /// `_upload`'s state, because the reviewer and the uploader are different
  /// people acting at different times -- the version to attach a remark to
  /// is whatever the chapter's stream says is current at the moment of
  /// posting, not anything this screen instance remembers.
  Future<void> _postFeedback({
    required String thesisId,
    required ChapterId chapter,
    required int currentVersion,
    required String reviewerUid,
    required String reviewerName,
  }) async {
    if (_feedbackBusy) return;
    setState(() {
      _feedbackBusy = true;
      _feedbackError = null;
    });

    try {
      await ref.read(documentRepositoryProvider).addFeedback(
            thesisId: thesisId,
            chapter: chapter,
            version: currentVersion,
            reviewerUid: reviewerUid,
            reviewerName: reviewerName,
            reviewerRole: 'Adviser',
            body: _feedbackController.text,
          );
      _feedbackController.clear();
    } on ArgumentError catch (e) {
      // The repository already refuses an empty/whitespace body with a
      // specific message ("Write something first."); surface that message
      // rather than a generic failure so a blank submit reads as a nudge,
      // not an error.
      if (mounted) setState(() => _feedbackError = e.message.toString());
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _feedbackError = e.code == 'permission-denied'
            ? 'You do not have permission to leave feedback on this '
                'chapter.'
            : 'Could not post this feedback.');
      }
    } catch (_) {
      if (mounted) setState(() => _feedbackError = 'Could not post this feedback.');
    } finally {
      if (mounted) setState(() => _feedbackBusy = false);
    }
  }

  /// The adviser's half of chapter status: `revise` sends it back, `approved`
  /// locks it. Both go through [DocumentRepository.setChapterStatus], which
  /// itself refuses `submitted` -- that value can only be written by an
  /// upload.
  Future<void> _setStatus({
    required String thesisId,
    required ChapterId chapter,
    required ChapterStatus status,
  }) async {
    if (_statusBusy) return;
    setState(() {
      _statusBusy = true;
      _statusError = null;
    });

    try {
      await ref.read(documentRepositoryProvider).setChapterStatus(
            thesisId: thesisId,
            chapter: chapter,
            status: status,
          );
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _statusError = e.code == 'permission-denied'
            ? 'You do not have permission to change this chapter\'s status.'
            : 'Could not update this chapter\'s status.');
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _statusError = 'Could not update this chapter\'s status.');
      }
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  /// A short, human date for a version or a remark. `intl` is not a
  /// dependency of this project, so this stays a plain manual format rather
  /// than pulling one in for a single label.
  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Just now';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}, '
        '$hour12:$minute $period';
  }

  /// Every state renders inside this frame. A bare [PageShell] has no
  /// Scaffold, so a refusal had no app bar and no way back at all -- see
  /// chapters_screen.dart, which this mirrors.
  Widget _framed(List<Widget> children) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.chapter.label)),
      body: PageShell(children: children),
    );
  }

  Widget _uploadControl({required bool disabled, String? disabledReason}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          key: const Key('uploadVersion'),
          onPressed: disabled || _busy ? null : _upload,
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Upload new version'),
        ),
        if (disabled && disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              disabledReason,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  /// Feedback and status controls, shown only to the thesis's adviser. A
  /// student and a panelist both read the same chapter stream, so the guard
  /// that keeps this section adviser-only lives in the caller, not here.
  Widget _reviewSection({
    required String thesisId,
    required ChapterId chapter,
    required int currentVersion,
    required String reviewerUid,
    required String reviewerName,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Gap.lg(),
        const Divider(),
        const Gap.sm(),
        Text('Adviser review',
            style: Theme.of(context).textTheme.titleMedium),
        const Gap.sm(),
        TextField(
          key: const Key('feedbackBody'),
          controller: _feedbackController,
          decoration: InputDecoration(
            labelText: 'Leave feedback on version $currentVersion',
          ),
          minLines: 2,
          maxLines: 4,
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('postFeedback'),
          onPressed: _feedbackBusy
              ? null
              : () => _postFeedback(
                    thesisId: thesisId,
                    chapter: chapter,
                    currentVersion: currentVersion,
                    reviewerUid: reviewerUid,
                    reviewerName: reviewerName,
                  ),
          child: Text(_feedbackBusy ? 'Posting…' : 'Post feedback'),
        ),
        if (_feedbackError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _feedbackError!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const Gap.sm(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('markRevise'),
                onPressed: _statusBusy
                    ? null
                    : () => _setStatus(
                          thesisId: thesisId,
                          chapter: chapter,
                          status: ChapterStatus.revise,
                        ),
                child: const Text('Send back for revision'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('markApproved'),
                onPressed: _statusBusy
                    ? null
                    : () => _setStatus(
                          thesisId: thesisId,
                          chapter: chapter,
                          status: ChapterStatus.approved,
                        ),
                child: const Text('Approve this chapter'),
              ),
            ),
          ],
        ),
        if (_statusError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _statusError!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapterRef =
        (thesisId: widget.thesisId, chapter: widget.chapter);

    // Read only to decide whether the review section renders, and to supply
    // `reviewerName` on a posted remark -- NOT gated on with a full-page
    // loading/error branch the way the three streams below are. Those three
    // are this screen's primary content: collapsing their loading state into
    // absence has shipped real bugs here before. The adviser section is
    // additive on top of that content, gated by an identity check, so
    // treating "still loading" or "failed to load" as "not proven to be the
    // adviser" (via valueOrNull) is the same fail-closed default the
    // security rules themselves apply, not a regression of that lesson. It
    // also means a caller need not stand up a signed-in `FirebaseAuth`
    // mock just to view chapter content, matching every render path before
    // this task.
    final thesis = ref.watch(thesisByIdProvider(widget.thesisId)).valueOrNull;
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isAdviser =
        thesis != null && me != null && thesis.adviserUid == me.uid;
    // Same fail-closed reasoning as `isAdviser` above, applied to the
    // upload control: an adviser, coordinator or dean who is shown "Upload
    // new version" will tap it, have the write denied by the rules, and
    // watch the orphaned file get deleted again -- a control that is
    // visible and always fails is worse than no control at all.
    final isLeader =
        thesis != null && me != null && thesis.leaderUid == me.uid;

    final chaptersAsync = ref.watch(chaptersProvider(widget.thesisId));

    // Each of the three streams below is checked on its own for loading and
    // error, rather than folded into `valueOrNull ?? []`. Collapsing a
    // still-loading stream into an empty list reads as "nothing here" and is
    // indistinguishable from a chapter that genuinely has no versions yet --
    // exactly the bug chapters_screen.dart's review caught.
    if (chaptersAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading this chapter…')]);
    }
    if (chaptersAsync.hasError) {
      return _framed([
        ErrorState(
          error: chaptersAsync.error,
          message: 'Could not load this chapter.',
        ),
      ]);
    }

    final chapters = chaptersAsync.valueOrNull ?? const <ThesisChapter>[];
    ThesisChapter? thisChapter;
    for (final c in chapters) {
      if (c.id == widget.chapter) {
        thisChapter = c;
        break;
      }
    }

    final versionsAsync = ref.watch(chapterVersionsProvider(chapterRef));
    if (versionsAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading versions…')]);
    }
    if (versionsAsync.hasError) {
      return _framed([
        ErrorState(
          error: versionsAsync.error,
          message: 'Could not load the versions of this chapter.',
        ),
      ]);
    }

    final feedbackAsync = ref.watch(chapterFeedbackProvider(chapterRef));
    if (feedbackAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading feedback…')]);
    }
    if (feedbackAsync.hasError) {
      return _framed([
        ErrorState(
          error: feedbackAsync.error,
          message: 'Could not load feedback for this chapter.',
        ),
      ]);
    }

    if (thisChapter == null) {
      return _framed([
        const EmptyState(
          key: Key('notStarted'),
          icon: Icons.upload_file,
          title: 'Not started',
          message: 'Upload your first version to begin.',
        ),
        const Gap.lg(),
        // Leader-only, mirroring `isAdviser` below: only the thesis's own
        // leader can ever write a version, so anyone else sees no control
        // to tap and have denied.
        if (isLeader) _uploadControl(disabled: false),
      ]);
    }

    final versions = versionsAsync.valueOrNull ?? const <ChapterVersion>[];
    final feedback = feedbackAsync.valueOrNull ?? const <ChapterFeedback>[];
    final brightness = Theme.of(context).brightness;
    final status = thisChapter.status;

    return Scaffold(
      key: const Key('chapterDetailScreen'),
      appBar: AppBar(title: Text(widget.chapter.label)),
      body: PageShell(
        title: widget.chapter.label,
        subtitle: ChapterStatusWords.detailFor(status),
        children: [
          Row(
            children: [
              Text(
                ChapterStatusWords.labelFor(status),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: ChapterStatusWords.colorFor(status, brightness)),
              ),
            ],
          ),
          const Gap.lg(),
          Text('Versions', style: Theme.of(context).textTheme.titleMedium),
          const Gap.sm(),
          if (versions.isEmpty)
            const EmptyState(
              icon: Icons.description_outlined,
              title: 'No versions yet',
              message: 'Upload the first version below.',
            )
          else
            for (final v in versions)
              Card(
                key: Key('versionRow-${v.version}'),
                child: ListTile(
                  title: Text('Version ${v.version}'),
                  subtitle: Text('Uploaded ${_formatDate(v.uploadedAt)}'),
                  trailing: TextButton(
                    onPressed: () => launchUrl(Uri.parse(v.fileUrl)),
                    child: const Text('Open'),
                  ),
                ),
              ),
          const Gap.lg(),
          Text('Feedback', style: Theme.of(context).textTheme.titleMedium),
          const Gap.sm(),
          if (feedback.isEmpty)
            const EmptyState(
              icon: Icons.chat_bubble_outline,
              title: 'No feedback yet',
              message: 'Your adviser has not left a remark yet.',
            )
          else
            for (final f in feedback)
              Card(
                key: Key('feedbackRow-${f.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${f.reviewerName} — ${f.reviewerRole} · '
                        'Version ${f.version}',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(f.body),
                    ],
                  ),
                ),
              ),
          const Gap.lg(),
          // Leader-only, for the same reason `isAdviser` gates the review
          // section below: the rules deny anyone else's write on `versions`
          // regardless, but a control that is visible and always fails is
          // worse than no control at all.
          if (isLeader)
            _uploadControl(
              disabled: status == ChapterStatus.approved,
              disabledReason: 'This chapter is approved. Ask your adviser '
                  'to reopen it before uploading again.',
            ),
          // Adviser-only. The rules deny a non-adviser's write on `status`
          // and `feedback` regardless, but a control that is visible and
          // always fails is worse than no control at all -- a student would
          // tap it, watch it silently do nothing (or surface a raw
          // permission error), and have no way to tell the two apart.
          if (isAdviser)
            _reviewSection(
              thesisId: widget.thesisId,
              chapter: widget.chapter,
              currentVersion: thisChapter.currentVersion,
              reviewerUid: me.uid,
              reviewerName: me.fullName,
            ),
        ],
      ),
    );
  }
}
