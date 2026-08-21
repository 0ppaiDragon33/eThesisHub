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

  Future<void> _upload() async {
    if (_busy) return;
    final pick = widget.pickDocument ?? realPicker;
    final file = await pick(allowed: kChapterTypes);
    if (file == null) return;

    final invalid = validateDocument(file,
        allowed: kChapterTypes, maxBytes: kChapterMaxBytes);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;

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

  @override
  Widget build(BuildContext context) {
    final chapterRef =
        (thesisId: widget.thesisId, chapter: widget.chapter);
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
        _uploadControl(disabled: false),
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
          _uploadControl(
            disabled: status == ChapterStatus.approved,
            disabledReason: 'This chapter is approved. Ask your adviser to '
                'reopen it before uploading again.',
          ),
        ],
      ),
    );
  }
}
