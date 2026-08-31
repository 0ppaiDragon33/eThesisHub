import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// A consolidated manuscript is one bound PDF, not the working chapter
/// files -- so unlike [kChapterTypes] this admits nothing else.
const kManuscriptTypes = {'pdf'};

/// Above [kChapterMaxBytes]: a consolidated manuscript carries every
/// chapter's figures and tables at once, still under the bucket's 50 MB
/// ceiling (see `file_upload.dart`'s own note on that ceiling).
const kManuscriptMaxBytes = 40 * 1024 * 1024;

/// Lets the leader of a group whose final defence passed upload their
/// consolidated manuscript and its abstract.
///
/// Visibility is decided from [myDefencesProvider], NOT from
/// `thesis.status` -- nothing in this project ever advances a thesis past
/// `titleApproved`; the defence record and its panel verdict are the only
/// place a "the group is done" signal exists. A completed final defence
/// with no verdict yet, or a `fail`, must show nothing here at all -- both
/// look identical to "not eligible" from this widget's point of view.
class ManuscriptUpload extends ConsumerStatefulWidget {
  const ManuscriptUpload({super.key, required this.thesis, this.pickDocument});

  final Thesis thesis;

  /// Injectable so a widget test can reach the upload path without a
  /// platform file dialog, matching [ChapterDetailScreen.pickDocument].
  final DocumentPicker? pickDocument;

  @override
  ConsumerState<ManuscriptUpload> createState() => _ManuscriptUploadState();
}

class _ManuscriptUploadState extends ConsumerState<ManuscriptUpload> {
  final _abstractController = TextEditingController();
  PickedDocument? _file;
  bool _busy = false;
  String? _error;

  /// True once the leader has asked to replace an already-submitted
  /// manuscript. `thesis.hasManuscript` alone cannot gate the form, or a
  /// leader could never overwrite a wrong upload.
  bool _replacing = false;

  @override
  void initState() {
    super.initState();
    // Rebuilds the button's disabled state as the abstract is typed --
    // required is "non-empty", which cannot be decided once at build time.
    _abstractController.addListener(_onAbstractChanged);
  }

  void _onAbstractChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _abstractController.removeListener(_onAbstractChanged);
    _abstractController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final pick = widget.pickDocument ?? realPicker;
    final picked = await pick(allowed: kManuscriptTypes);
    if (picked == null) return;

    final invalid = validateDocument(picked,
        allowed: kManuscriptTypes, maxBytes: kManuscriptMaxBytes);
    if (invalid != null) {
      if (mounted) setState(() => _error = invalid);
      return;
    }
    if (mounted) {
      setState(() {
        _file = picked;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    final file = _file;
    if (file == null || _busy) return;

    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) {
      // A blank submit here would give the leader no feedback at all --
      // see the identical note on ChapterDetailScreen's own upload.
      if (mounted) {
        setState(() =>
            _error = 'You appear to be signed out. Sign in again and retry.');
      }
      return;
    }

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
        thesisId: widget.thesis.id,
        documentId: 'manuscript',
      );
      await ref.read(thesisRepositoryProvider).attachManuscript(
            thesisId: widget.thesis.id,
            leaderUid: uid,
            storagePath: stored.path,
            fileUrl: stored.url,
            abstract: _abstractController.text,
          );
      if (mounted) {
        setState(() {
          _file = null;
          _replacing = false;
        });
      }
    } on StorageFailure catch (e) {
      // There are no server-side logs on this project -- the message and
      // code are the only place the cause can surface.
      if (mounted) setState(() => _error = '${e.message} [${e.code}]');
    } on ArgumentError catch (e) {
      // The repository's own refusal (empty abstract/path/url) is written
      // for a human; show it rather than a generic failure. The file is
      // already uploaded at this point, so clean up the orphan.
      if (stored != null) {
        try {
          await storage.delete(stored.path);
        } catch (_) {}
      }
      if (mounted) setState(() => _error = e.message.toString());
    } on StateError catch (e) {
      // Wrong leader, or the thesis is not at titleApproved -- also a
      // human-written message from the repository.
      if (stored != null) {
        try {
          await storage.delete(stored.path);
        } catch (_) {}
      }
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (stored != null) {
        try {
          await storage.delete(stored.path);
        } catch (_) {}
      }
      if (mounted) setState(() => _error = 'Could not submit the manuscript.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _submittedView(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Manuscript submitted, awaiting the coordinator.',
                    key: const Key('manuscriptSubmitted'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('replaceManuscript'),
              onPressed: () => setState(() => _replacing = true),
              child: const Text('Replace manuscript'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formView(BuildContext context) {
    final canSubmit = _file != null &&
        _abstractController.text.trim().isNotEmpty &&
        !_busy;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Submit final manuscript',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('pickManuscript'),
              icon: const Icon(Icons.upload_file),
              label: Text(_file?.name ?? 'Choose PDF'),
              onPressed: _busy ? null : _pick,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('manuscriptAbstract'),
              controller: _abstractController,
              enabled: !_busy,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Abstract',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('submitManuscript'),
              onPressed: canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit manuscript'),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defences =
        ref.watch(myDefencesProvider).valueOrNull ?? const <Defence>[];
    final eligible = defences.any((d) =>
        d.type == DefenceType.final_ &&
        d.status == DefenceStatus.completed &&
        d.panelVerdict == PassFail.pass);

    if (!eligible) return const SizedBox.shrink();

    final showSubmitted = widget.thesis.hasManuscript && !_replacing;

    return KeyedSubtree(
      key: const Key('manuscriptUpload'),
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: showSubmitted ? _submittedView(context) : _formView(context),
      ),
    );
  }
}
