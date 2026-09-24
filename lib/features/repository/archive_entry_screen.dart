import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/open_document.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/app_user.dart';
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
          maxWidth: AppTokens.measureWide,
          kicker: 'College archive',
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
    //
    // The profile is passed down whole, not flattened to a bool. `?.role ==
    // coordinator` collapses three different states — still loading, the
    // read failed, you are not a coordinator — into one silent absence, the
    // very conflation the comment above the entry branch says has already
    // shipped four bugs here. A coordinator whose profile read was denied
    // must not be told, by omission, that they are not a coordinator.
    final profile = ref.watch(currentUserProvider);

    return _framed([_EntryView(entry: entry, profile: profile)]);
  }
}

class _EntryView extends ConsumerStatefulWidget {
  const _EntryView({required this.entry, required this.profile});

  final ArchiveEntry entry;

  /// The reader's own profile, still in its three states. See the comment at
  /// the watch site for why this is not a bool.
  final AsyncValue<AppUser?> profile;

  @override
  ConsumerState<_EntryView> createState() => _EntryViewState();
}

class _EntryViewState extends ConsumerState<_EntryView> {
  /// Builds and shares Form 8 straight from the [ArchiveEntry] already on
  /// screen. No further read: a second fetch would be a chance for the
  /// certificate to disagree with what the reader is looking at.
  Future<void> _downloadForm8(ArchiveEntry entry) async {
    try {
      // Refuse BEFORE assembling (§6). The gate that shipped is structural
      // only — this button is unreachable unless the thesis is archived —
      // and an archived entry can still hold no members and no title, which
      // would render a letterheaded, signature-ruled CERTIFICATION that
      // "  has submitted bound copies of his/her undergraduate thesis". The
      // throw takes the same path as any other failure, so the catch below
      // surfaces it in a SnackBar exactly as `_downloadForm5c` refuses on a
      // missing thesis.
      final blocker = Form8Unissuable.check(entry);
      if (blocker != null) throw blocker;

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

  /// The Form 8 control, or an account of why there isn't one.
  ///
  /// Three states, kept apart: the profile is still loading, the profile
  /// read failed, or it resolved and the reader is not a coordinator. Only
  /// the last is silence — a coordinator has no business being told about
  /// the other roles' absent button. A FAILED read is never allowed to look
  /// like "you are not a coordinator": that is a transient fault dressed up
  /// as an authorization answer, and the reader would go looking for a
  /// permission they already have.
  List<Widget> _form8Control(
    ArchiveEntry entry,
    TextTheme text,
    Color muted,
  ) {
    // No spinner: a widget test that pumpAndSettle()s would never settle on
    // one, and this is a line of text's worth of waiting.
    Widget note(String key, String message) => Padding(
          padding: const EdgeInsets.only(top: AppTokens.md - 4),
          child: Text(
            message,
            key: Key(key),
            style: text.bodySmall?.copyWith(color: muted),
          ),
        );

    return widget.profile.when(
      loading: () => [note('form8RoleLoading', 'Checking your role…')],
      error: (e, _) => [
        note(
          'form8RoleUnavailable',
          'Could not check your role, so Form 8 is unavailable here. This is '
              'a failed read, not an answer about your permissions — try '
              'again.',
        ),
      ],
      data: (user) => user?.role == UserRole.coordinator
          ? [
              const Gap.sm(),
              OutlinedButton(
                key: const Key('downloadForm8'),
                onPressed: () => _downloadForm8(entry),
                child: const Text('Download Form 8'),
              ),
            ]
          : const [],
    );
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

    final manuscript = entry.manuscriptPath.isNotEmpty
        ? FilledButton.icon(
            key: const Key('openManuscript'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open manuscript'),
            // Leaves the app: there is no in-app PDF viewer. The bucket is
            // private, so this asks the `document-url` function for a
            // short-lived link. An archived manuscript opens for any active
            // reader — the repository is meant to be browsed — while the
            // function still refuses in-progress theses to non-members.
            onPressed: () => openStoredDocument(
              context,
              ref,
              entry.manuscriptPath,
              label: 'the manuscript',
            ),
          )
        // A button that launches nothing invites a silent tap; say so.
        : Text(
            'No manuscript is on file for this thesis.',
            key: const Key('manuscriptMissing'),
            style: text.bodyMedium?.copyWith(color: muted),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(entry.title,
            style: Breakpoint.of(context) == Breakpoint.compact
                ? text.headlineSmall
                : text.headlineMedium),
        const SizedBox(height: AppTokens.sm),
        Text(authors, style: text.bodyLarge?.copyWith(color: muted)),
        const Gap.lg(),
        SplitColumns(
          primary: [
            Panel(
              title: 'Abstract',
              icon: Icons.subject_rounded,
              child: Text(entry.abstract,
                  style: text.bodyLarge?.copyWith(height: 1.65)),
            ),
          ],
          secondary: [
            Panel(
              title: 'Manuscript',
              icon: Icons.picture_as_pdf_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [manuscript, ..._form8Control(entry, text, muted)],
              ),
            ),
            Panel(
              title: 'Record',
              icon: Icons.info_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FactLine(label: 'College', value: entry.college),
                  FactLine(label: 'Program', value: entry.program),
                  FactLine(label: 'Academic year', value: entry.academicYear),
                ],
              ),
            ),
            Panel(
              title: 'Adviser and panel',
              icon: Icons.groups_outlined,
              child: Column(
                children: [
                  PersonLine(name: entry.adviserName, role: 'Adviser'),
                  if (entry.panelNames.isEmpty)
                    const PersonLine(name: 'Unknown panel', role: 'Panel')
                  else
                    for (final n in entry.panelNames)
                      PersonLine(name: n, role: 'Panel member'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
