import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/forms/form5c_pdf.dart';
import 'package:ethesishub/features/forms/form8_data.dart';
import 'package:ethesishub/features/forms/form8_pdf.dart';
import 'package:ethesishub/providers/archive_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// The office's forms, findable on their own — not only as a download
/// button bolted onto whatever screen happens to already hold the data.
///
/// The complaint this answers: a reader went looking for "the forms" and
/// there was nowhere to look. Forms at this university are physical
/// artifacts before they are anything else — people print blanks, carry
/// them into rooms, and fill them in by hand — so the one thing every
/// card on this screen guarantees, unconditionally, is a blank template.
/// No thesis, no defence, no evaluation, no archive entry: a completely
/// empty database still renders three cards, each with a working
/// download. Everything else on a card — a link to a filled version this
/// reader happens to be entitled to — is additive on top of that
/// guarantee, never a precondition for it.
class FormsScreen extends StatelessWidget {
  const FormsScreen({super.key});

  Widget _framed(List<Widget> children) => KeyedSubtree(
        key: const Key('forms'),
        child: PageShell(
          title: 'Forms',
          subtitle: 'Blank templates for every research form, and the '
              'filled versions you have on file.',
          children: children,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return _framed(const [
      _Form1Card(),
      Gap.md(),
      _Form5cCard(),
      Gap.md(),
      _Form8Card(),
    ]);
  }
}

/// The one shape every card on this screen shares: a name, a one-line
/// account of what the form is for, and whatever action widgets the
/// specific card adds beneath that.
class _FormCard extends StatelessWidget {
  const _FormCard({
    required this.cardKey,
    required this.name,
    required this.purpose,
    required this.actions,
  });

  final Key cardKey;
  final String name;
  final String purpose;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      key: cardKey,
      margin: const EdgeInsets.only(bottom: AppTokens.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: text.titleMedium),
            const SizedBox(height: AppTokens.xs),
            Text(purpose, style: text.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: AppTokens.sm),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Shows a failure the same way every download control on this screen
/// reports one, in a SnackBar rather than a dialog that would need its
/// own dismissal.
void _reportFailure(BuildContext context, String form, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Could not generate $form: $error')),
  );
}

/// Form 1 — Nomination of Thesis Adviser and Panel Members.
///
/// No blank template button here, deliberately. `Form1Data` requires a
/// whole `Thesis` (and its layout is a table of nominees built from real
/// nominations, not a fixed rubric with ruled blanks), so there is no
/// honest way to hand back a blank Form 1 without fabricating a thesis
/// that does not exist. This card still lists the form and, when the
/// reader has a thesis of their own, links to the screen that already
/// generates it filled — Form 1's status page, `/thesis`.
class _Form1Card extends ConsumerWidget {
  const _Form1Card();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesis = ref.watch(myThesisProvider).valueOrNull;

    return _FormCard(
      cardKey: const Key('form1Card'),
      name: 'Form 1 — Nomination of Thesis Adviser and Panel Members',
      purpose: 'The letter that starts a thesis\'s approval chain, naming '
          'its adviser and panel.',
      actions: [
        Text(
          'Generated from a thesis\'s own nominations, so there is no '
          'blank template — open your thesis to download it filled in.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        if (thesis != null) ...[
          const Gap.sm(),
          OutlinedButton(
            key: const Key('form1OpenThesis'),
            onPressed: () => context.go('/thesis'),
            child: const Text('Open my thesis'),
          ),
        ],
      ],
    );
  }
}

/// Form 5c — Evaluation Guide.
///
/// The blank template button is always enabled: [buildForm5cBlank] takes
/// no data at all. There is no provider on hand that lists "every
/// evaluation this panelist has submitted" across every defence (the
/// existing providers are all scoped to one defence at a time), so rather
/// than build one for a convenience link, this card points at the screen
/// that already owns that list one defence at a time — Defences.
class _Form5cCard extends StatefulWidget {
  const _Form5cCard();

  @override
  State<_Form5cCard> createState() => _Form5cCardState();
}

class _Form5cCardState extends State<_Form5cCard> {
  Future<void> _downloadBlank() async {
    try {
      final bytes = await buildForm5cBlank();
      await Printing.sharePdf(bytes: bytes, filename: 'Form5c-blank.pdf');
    } catch (e) {
      if (!mounted) return;
      _reportFailure(context, 'Form 5c', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormCard(
      cardKey: const Key('form5cCard'),
      name: 'Form 5c — Evaluation Guide',
      purpose: 'The rubric a panelist scores a title or final defence '
          'with, eleven criteria across content and presentation.',
      actions: [
        OutlinedButton(
          key: const Key('form5cBlankButton'),
          onPressed: _downloadBlank,
          child: const Text('Blank template'),
        ),
        const Gap.sm(),
        Text(
          'Sheets you have already submitted are attached to the defence '
          'they were scored at.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const Gap.sm(),
        OutlinedButton(
          key: const Key('form5cOpenDefences'),
          onPressed: () => context.go('/defences'),
          child: const Text('Open Defences'),
        ),
      ],
    );
  }
}

/// Form 8 — Certification of Submission of Bound Copies.
///
/// The blank template button is always enabled: [buildForm8Blank] takes
/// no data at all, and carries the diagonal "TEMPLATE" watermark and the
/// under-heading marking that keep it from being confused with a real,
/// signed certificate (§6, `Form8Unissuable`). The filled list beneath it
/// — one row per archived thesis, each with its own "Download" control —
/// is wired straight from providers this screen already reads
/// ([archiveProvider], [currentUserProvider]) and the same
/// [Form8Unissuable] gate `ArchiveEntryScreen` uses, so a coordinator
/// with nothing archived yet still gets the blank without an empty list
/// under it.
class _Form8Card extends StatefulWidget {
  const _Form8Card();

  @override
  State<_Form8Card> createState() => _Form8CardState();
}

class _Form8CardState extends State<_Form8Card> {
  Future<void> _downloadBlank() async {
    try {
      final bytes = await buildForm8Blank();
      await Printing.sharePdf(bytes: bytes, filename: 'Form8-blank.pdf');
    } catch (e) {
      if (!mounted) return;
      _reportFailure(context, 'Form 8', e);
    }
  }

  Future<void> _downloadFilled(ArchiveEntry entry) async {
    try {
      final blocker = Form8Unissuable.check(entry);
      if (blocker != null) throw blocker;

      final data = Form8Data.assemble(entry: entry);
      await Printing.sharePdf(
        bytes: await buildForm8Pdf(data),
        filename: 'Form8-${entry.thesisId}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      _reportFailure(context, 'Form 8', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final profile = ref.watch(currentUserProvider).valueOrNull;
        final isCoordinator = profile?.role == UserRole.coordinator;
        final entries = isCoordinator
            ? ref.watch(archiveProvider).valueOrNull ?? const <ArchiveEntry>[]
            : const <ArchiveEntry>[];

        return _FormCard(
          cardKey: const Key('form8Card'),
          name: 'Form 8 — Certification of Submission of Bound Copies',
          purpose: 'The coordinator\'s certificate that bound copies of a '
              'thesis reached the Dean, the Library and R&D.',
          actions: [
            OutlinedButton(
              key: const Key('form8BlankButton'),
              onPressed: _downloadBlank,
              child: const Text('Blank template'),
            ),
            if (isCoordinator && entries.isNotEmpty) ...[
              const Gap.md(),
              Text(
                'Archived theses',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Gap.sm(),
              for (final entry in entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTokens.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppTokens.sm),
                      OutlinedButton(
                        key: Key('form8Download-${entry.thesisId}'),
                        onPressed: () => _downloadFilled(entry),
                        child: const Text('Download'),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}
