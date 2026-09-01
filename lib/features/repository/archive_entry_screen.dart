import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form8_pdf.dart';
import 'package:ethesishub/providers/archive_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// A single published thesis, in full.
///
/// The screen a reader lands on from [ArchiveScreen]'s card: everything a
/// card summarises, plus the full abstract and the panel, and the one
/// action a browse list cannot offer -- opening the manuscript itself.
class ArchiveEntryScreen extends ConsumerWidget {
  const ArchiveEntryScreen({super.key, required this.thesisId});

  final String thesisId;

  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('archiveEntry'),
        child: PageShell(
          title: 'Thesis',
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entryAsync = ref.watch(archiveEntryProvider(thesisId));

    if (entryAsync.isLoading) {
      return _framed(const [
        LoadingState(key: Key('entryLoading'), label: 'Loading the thesis…'),
      ]);
    }
    if (entryAsync.hasError) {
      return _framed([
        ErrorState(
          error: entryAsync.error,
          message: 'Could not load this thesis.',
        ),
      ]);
    }

    // Resolved-but-null is NOT an error: the coordinator can retract an
    // archive entry, which deletes the doc, and a reader following a stale
    // link (a bookmark, a share) lands exactly here. Conflating this with a
    // failed read has shipped four bugs on this project already -- keep the
    // two paths separate.
    final entry = entryAsync.valueOrNull;
    if (entry == null) {
      return _framed(const [
        EmptyState(
          key: Key('entryNotFound'),
          icon: Icons.inbox_outlined,
          title: 'That thesis is not in the archive.',
          message: 'It may have been retracted, or the link is out of date.',
        ),
      ]);
    }

    // The archive entry screen is the one screen in this app any signed-in
    // reader can open. Form 8 certifies that bound copies reached the Dean,
    // the Library and R&D — issuing it is the coordinator's act (§10b, the
    // role table), so the control is gated on the READER's role, not on the
    // entry: nothing about the data changes who may see the button.
    final isCoordinator =
        ref.watch(currentUserProvider).valueOrNull?.role == UserRole.coordinator;

    return _framed([_EntryView(entry: entry, isCoordinator: isCoordinator)]);
  }
}

class _EntryView extends StatefulWidget {
  const _EntryView({required this.entry, required this.isCoordinator});

  final ArchiveEntry entry;
  final bool isCoordinator;

  @override
  State<_EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends State<_EntryView> {
  /// Builds and shares Form 8 straight from the [ArchiveEntry] already on
  /// screen. No further read: a second fetch would be a chance for the
  /// certificate to disagree with what the reader is looking at.
  Future<void> _downloadForm8(ArchiveEntry entry) async {
    try {
      final data = Form8Data.assemble(entry: entry);
      await Printing.sharePdf(
        bytes: await buildForm8Pdf(data),
        filename: 'Form8-${entry.thesisId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate Form 8: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // An entry with no members recorded still needs a line here rather than
    // a blank one -- matches the card on ArchiveScreen, so the two screens
    // do not disagree about the same entry.
    final authors =
        entry.authorsLabel.isNotEmpty ? entry.authorsLabel : 'Unknown authors';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.title, style: text.headlineSmall),
        const SizedBox(height: AppTokens.xs),
        Text(authors, style: text.bodyMedium?.copyWith(color: muted)),
        const SizedBox(height: AppTokens.xs),
        Text(
          '${entry.college} · ${entry.program} · ${entry.academicYear}',
          style: text.bodySmall?.copyWith(color: muted),
        ),
        const Gap.md(),
        Text('Adviser: ${entry.adviserName}', style: text.bodyMedium),
        const SizedBox(height: AppTokens.xs),
        Text(
          'Panel: ${entry.panelNames.isNotEmpty ? entry.panelNames.join(', ') : 'Unknown panel'}',
          style: text.bodyMedium,
        ),
        const Gap.lg(),
        Text('Abstract', style: text.titleMedium),
        const SizedBox(height: AppTokens.xs),
        Text(entry.abstract, style: text.bodyMedium),
        const Gap.lg(),
        if (entry.manuscriptUrl.isNotEmpty)
          FilledButton.icon(
            key: const Key('openManuscript'),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open manuscript'),
            // Deliberately leaves the app: the manuscript lives in a public
            // Supabase bucket and there is no in-app PDF viewer, so the only
            // way to read it is to hand the URL to the platform.
            onPressed: () => launchUrl(
              Uri.parse(entry.manuscriptUrl),
              mode: LaunchMode.externalApplication,
            ),
          )
        else
          // A manuscript-less archive entry is possible (an upload step
          // failed after the record was written, say) but a button that
          // launches nothing is worse than no button -- it invites a tap
          // that silently does nothing. Say so instead.
          Text(
            'No manuscript is on file for this thesis.',
            key: const Key('manuscriptMissing'),
            style: text.bodyMedium?.copyWith(color: muted),
          ),
        if (widget.isCoordinator) ...[
          const Gap.md(),
          OutlinedButton(
            key: const Key('downloadForm8'),
            onPressed: () => _downloadForm8(entry),
            child: const Text('Download Form 8'),
          ),
        ],
      ],
    );
  }
}
