import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/repositories/title_defence_repository.dart';
import 'package:ethesishub/features/titles/file_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// Picks one document, or null if the user cancelled.
typedef DocumentPicker = Future<PickedDocument?> Function({
  required Set<String> allowed,
});

/// The real picker, backing [SubmitTitlesScreen.pickDocument] by default.
/// `file_picker` has no test seam of its own, so this is the one call in the
/// screen that a widget test cannot reach without injection.
Future<PickedDocument?> _realPicker({required Set<String> allowed}) async {
  // `allowed` used to be accepted and dropped on the floor, so the OS dialog
  // offered every file on the machine and the student learned their .zip was
  // wrong only after picking it. `validateDocument` still runs afterwards —
  // this narrows the dialog, it does not replace the check.
  final result = await FilePicker.platform.pickFiles(
    withData: true,
    type: FileType.custom,
    allowedExtensions: allowed.toList(),
  );
  final picked = result?.files.single;
  if (picked == null || picked.bytes == null) return null;
  final extension = (picked.extension ?? '').toLowerCase();
  return PickedDocument(
    name: picked.name,
    bytes: picked.bytes!,
    extension: extension,
    contentType: contentTypeFor(extension),
  );
}

/// Lets the thesis leader submit three or more candidate titles, each with
/// its own justification document, plus one presentation, moving the thesis
/// into the title defence.
///
/// Reached from the thesis status screen at `/thesis/titles?id=<thesisId>`.
class SubmitTitlesScreen extends ConsumerStatefulWidget {
  const SubmitTitlesScreen({
    super.key,
    required this.thesisId,
    this.pickDocument,
  });

  final String thesisId;

  /// Injectable so a widget test can reach the success path — upload,
  /// submit and navigate — without a platform file dialog. Defaults to the
  /// real picker. `file_picker` has no test seam of its own, and the
  /// success branch is the one this project has shipped broken twice.
  final DocumentPicker? pickDocument;

  @override
  ConsumerState<SubmitTitlesScreen> createState() =>
      _SubmitTitlesScreenState();
}

class _SubmitTitlesScreenState extends ConsumerState<SubmitTitlesScreen> {
  final List<TextEditingController> _titles = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final List<PickedDocument?> _justifications = [null, null, null];
  PickedDocument? _presentation;

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _titles) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCandidate() {
    setState(() {
      _titles.add(TextEditingController());
      _justifications.add(null);
    });
  }

  Future<void> _pickJustification(int index) async {
    final pick = widget.pickDocument ?? _realPicker;
    final doc = await pick(allowed: kJustificationTypes);
    if (doc == null) return;
    final validationError = validateDocument(doc,
        allowed: kJustificationTypes, maxBytes: kJustificationMaxBytes);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _justifications[index] = doc;
      _error = null;
    });
  }

  Future<void> _pickPresentation() async {
    final pick = widget.pickDocument ?? _realPicker;
    final doc = await pick(allowed: kPresentationTypes);
    if (doc == null) return;
    final validationError = validateDocument(doc,
        allowed: kPresentationTypes, maxBytes: kPresentationMaxBytes);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _presentation = doc;
      _error = null;
    });
  }

  Future<void> _submit(String leaderUid) async {
    if (_busy) return;

    final titleTexts = _titles.map((c) => c.text.trim()).toList();
    if (titleTexts.any((t) => t.isEmpty)) {
      setState(() => _error = 'Give every candidate a title.');
      return;
    }
    if (_justifications.any((j) => j == null)) {
      setState(() =>
          _error = 'Attach a justification for every candidate title.');
      return;
    }
    if (_presentation == null) {
      setState(() => _error = 'Attach your presentation.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final storage = ref.read(storageServiceProvider);
      final repo = ref.read(titleDefenceRepositoryProvider);

      final drafts = <CandidateTitleDraft>[];
      for (var i = 0; i < titleTexts.length; i++) {
        final stored = await uploadDocument(
          storage: storage,
          file: _justifications[i]!,
          thesisId: widget.thesisId,
          documentId: 'candidate-$i',
        );
        drafts.add((
          titleText: titleTexts[i],
          justificationPath: stored.path,
          justificationUrl: stored.url,
        ));
      }

      final storedPresentation = await uploadDocument(
        storage: storage,
        file: _presentation!,
        thesisId: widget.thesisId,
        documentId: 'presentation',
      );

      await repo.submitCandidateTitles(
        thesisId: widget.thesisId,
        titles: drafts,
        presentationPath: storedPresentation.path,
        presentationUrl: storedPresentation.url,
      );

      // Straight to the status screen, mirroring nominate_screen.dart:
      // staying put let this screen's own status stream replace the form
      // with a refusal message immediately after the submission succeeded.
      if (mounted) context.go('/thesis');
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } on StateError catch (_) {
      if (mounted) {
        setState(() => _error =
            'This thesis is no longer accepting candidate titles.');
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'permission-denied'
            ? 'You do not have permission to submit candidate titles.'
            : 'Could not submit. Please try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not submit. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watched, not read lazily inside the submit handler — see
    // nominate_screen.dart for the bug this avoids: reading it lazily races
    // the auth stream's first event and throws a null-check error the
    // generic catch swallows.
    final leaderUid = ref.watch(authStateProvider).valueOrNull?.uid;
    final thesisAsync = ref.watch(thesisByIdProvider(widget.thesisId));

    // Four distinct outcomes, kept apart. Collapsing loading into "not
    // ready" is exactly the bug M1a shipped: a student was told "this
    // thesis has moved past draft" while it was still loading.
    if (thesisAsync.isLoading) {
      return const LoadingState(label: 'Loading your thesis…');
    }
    if (thesisAsync.hasError) {
      return PageShell(children: [
        ErrorState(
          error: thesisAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }

    final thesis = thesisAsync.valueOrNull;
    if (thesis == null) {
      return const PageShell(children: [
        EmptyState(
          icon: Icons.search_off,
          title: 'Thesis not found',
          message:
              'This thesis no longer exists, or it belongs to another group.',
        ),
      ]);
    }

    final canSubmit = thesis.status == ThesisStatus.nominationApproved ||
        thesis.status == ThesisStatus.titleRejected;
    if (!canSubmit) {
      return const PageShell(children: [
        EmptyState(
          key: Key('notReady'),
          icon: Icons.hourglass_empty,
          title: 'Not ready for candidate titles',
          message: 'Candidate titles can be submitted once the nomination '
              'is approved, or after a set has been rejected.',
        ),
      ]);
    }

    final atCap = _titles.length >= TitleDefenceRepository.maxCandidates;

    return Scaffold(
      key: const Key('submitTitlesScreen'),
      appBar: AppBar(title: const Text('Candidate titles')),
      body: PageShell(
        title: 'Candidate titles',
        subtitle: 'Submit at least ${TitleDefenceRepository.minCandidates} '
            'candidate titles, each with a justification, plus one '
            'presentation.',
        children: [
          if (thesis.status == ThesisStatus.titleRejected &&
              (thesis.titleRejectionRemark ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ErrorState(
                message: 'This set was rejected: '
                    '${thesis.titleRejectionRemark}',
              ),
            ),
          for (var i = 0; i < _titles.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: Key('titleText$i'),
                    controller: _titles[i],
                    decoration: InputDecoration(
                      labelText: 'Candidate title ${i + 1}',
                    ),
                  ),
                  const Gap.sm(),
                  Row(
                    children: [
                      TextButton(
                        key: Key('pickJustification$i'),
                        onPressed: () => _pickJustification(i),
                        child: Text(_justifications[i] == null
                            ? 'Attach justification'
                            : 'Justification: ${_justifications[i]!.name}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('addCandidate'),
              onPressed: atCap ? null : _addCandidate,
              child: const Text('+ Add candidate title'),
            ),
          ),
          if (atCap)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Candidate titles are capped at '
                '${TitleDefenceRepository.maxCandidates} per submission: '
                'each one costs a security-rules check, and a larger batch '
                'is denied.',
                key: const Key('candidateCapReason'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Gap.lg(),
          TextButton(
            key: const Key('pickPresentation'),
            onPressed: _pickPresentation,
            child: Text(_presentation == null
                ? 'Attach presentation'
                : 'Presentation: ${_presentation!.name}'),
          ),
          const Gap.lg(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                key: const Key('error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            key: const Key('submitTitles'),
            onPressed: _busy || leaderUid == null
                ? null
                : () => _submit(leaderUid),
            child: Text(_busy ? 'Submitting…' : 'Submit candidate titles'),
          ),
        ],
      ),
    );
  }
}
