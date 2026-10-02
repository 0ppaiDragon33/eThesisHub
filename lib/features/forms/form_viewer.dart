import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/repositories/faculty_directory_repository.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/editable/form1_template.dart';
import 'package:ethesishub/features/forms/editable/form_pdf.dart';
import 'package:ethesishub/features/forms/form1_data.dart';
import 'package:ethesishub/features/forms/form1_pdf.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The filled Form 1 for [thesis], as it stands now: each nominee's conforme
/// as recorded so far.
///
/// [leaderName] is the thesis's own `leaderName` for anyone who cannot read
/// the leader's profile (nominees); the leader's own screen may pass the
/// profile name instead. The two signatory names are resolved against the
/// live faculty directory, which every verified user may read, so they do
/// not print blank for an office holder with no seat on this thesis.
Future<Uint8List> buildForm1For({
  required Thesis thesis,
  required List<Nomination> nominations,
  required FacultyDirectoryRepository directory,
  String? leaderName,
}) async {
  final directoryNames = <String, String>{};
  for (final uid in <String?>{
    thesis.coordinatorRecommendedBy,
    thesis.deanApprovedBy,
  }) {
    if (uid == null) continue;
    final entry = await directory.fetch(uid);
    if (entry != null) directoryNames[uid] = entry.fullName;
  }
  final data = Form1Data.assemble(
    thesis: thesis,
    nominations: nominations,
    leaderName: leaderName ?? thesis.leaderName ?? '',
    directoryNames: directoryNames,
  );
  return buildForm1Pdf(data);
}

/// Opens a filled form full screen, inside the app: its pages to read and
/// zoom, and a Download button for a copy. Nothing is downloaded unless the
/// reader asks.
Future<void> showFormViewer(
  BuildContext context, {
  required String title,
  required String filename,
  required Future<Uint8List> Function() buildPdf,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _FormViewer(title: title, filename: filename, buildPdf: buildPdf),
  );
}

/// A "View Form N" button for a card where someone accepts or declines.
class ViewFormButton extends StatelessWidget {
  const ViewFormButton({
    super.key,
    required this.label,
    required this.title,
    required this.filename,
    required this.buildPdf,
  });

  final String label;
  final String title;
  final String filename;
  final Future<Uint8List> Function() buildPdf;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showFormViewer(
        context,
        title: title,
        filename: filename,
        buildPdf: buildPdf,
      ),
      icon: const Icon(Icons.description_outlined, size: 18),
      label: Text(label),
    );
  }
}

/// "View Form 1" for a nomination: the thesis and its nominations are read
/// when the reader taps it, so the form shows the conformes as they stand.
/// Readable by every nominee on the thesis, the Coordinator and the Dean.
class ViewForm1Button extends ConsumerWidget {
  const ViewForm1Button({super.key, required this.thesisId});

  final String thesisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ViewFormButton(
      label: 'View Form 1',
      title: 'Form 1 · Nomination of Thesis Adviser and Panel Members',
      filename: 'Form1-$thesisId.pdf',
      buildPdf: () async {
        final repo = ref.read(thesisRepositoryProvider);
        final thesis = await repo.watchThesis(thesisId).first;
        if (thesis == null) throw StateError('This thesis no longer exists.');
        final nominations = await repo.watchNominations(thesisId).first;
        // A thesis older than `leaderName` lacks it until its leader next
        // opens the app. The Coordinator and the Dean may read the leader's
        // profile meanwhile; a nominee may not, and gets a blank name.
        var leaderName = thesis.leaderName;
        if (leaderName == null || leaderName.isEmpty) {
          try {
            leaderName = (await ref
                    .read(userRepositoryProvider)
                    .fetchUser(thesis.leaderUid))
                ?.fullName;
          } catch (_) {
            leaderName = null;
          }
        }
        return buildForm1For(
          thesis: thesis,
          nominations: nominations,
          directory: ref.read(facultyDirectoryRepositoryProvider),
          leaderName: leaderName,
        );
      },
    );
  }
}

class _FormViewer extends ConsumerStatefulWidget {
  const _FormViewer({
    required this.title,
    required this.filename,
    required this.buildPdf,
  });

  final String title;
  final String filename;
  final Future<Uint8List> Function() buildPdf;

  @override
  ConsumerState<_FormViewer> createState() => _FormViewerState();
}

class _FormViewerState extends ConsumerState<_FormViewer> {
  /// Built once and shared by the preview and the download, so the copy the
  /// reader saves is the one they read.
  late final Future<Uint8List> _bytes = widget.buildPdf();

  bool _saving = false;
  String? _error;

  // A method tear-off, so the preview gets the same function on every
  // rebuild; a fresh closure would make it draw the pages again each time
  // the Download button redraws.
  Future<Uint8List> _source() => _bytes;

  Future<void> _download() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(pdfSharerProvider)(await _bytes, widget.filename);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save a copy.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(formPreviewBuilderProvider);
    return Dialog.fullscreen(
      key: const Key('formViewer'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.xs, AppTokens.xs, AppTokens.md, AppTokens.xs),
            child: Row(
              children: [
                IconButton(
                  key: const Key('closeFormViewer'),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: AppTokens.xs),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_error != null) ...[
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  const SizedBox(width: AppTokens.sm),
                ],
                OutlinedButton.icon(
                  key: const Key('downloadForm'),
                  onPressed: _saving ? null : _download,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Download'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: preview(_source)),
        ],
      ),
    );
  }
}

/// "View attached copy": the Form 1 copy the leader attached to the
/// nomination, shown beside the official Form 1 for the people who sign.
/// Draws nothing when no copy was attached.
class ViewForm1CopyButton extends ConsumerWidget {
  const ViewForm1CopyButton({super.key, required this.thesisId});

  final String thesisId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachment = ref.watch(form1AttachmentProvider(thesisId)).valueOrNull;
    if (attachment == null) return const SizedBox.shrink();
    return ViewFormButton(
      label: 'View attached copy',
      title: attachment.copyName,
      filename: 'Form1-copy-$thesisId.pdf',
      buildPdf: () => buildFormPdf(form1Template, attachment.overrides),
    );
  }
}
