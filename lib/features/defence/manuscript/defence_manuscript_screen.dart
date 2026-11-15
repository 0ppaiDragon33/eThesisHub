import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/defence_annotation.dart';
import 'package:ethesishub/features/defence/defence_mode_gate.dart';
import 'package:ethesishub/features/defence/manuscript/highlight_colours.dart';
import 'package:ethesishub/features/defence/manuscript/highlights_panel.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_pane.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_view.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// The manuscript and its highlights, read-only: how the group reads what
/// the panel marked, once the adviser has released the comments.
class DefenceManuscriptScreen extends ConsumerStatefulWidget {
  const DefenceManuscriptScreen({super.key, required this.defenceId});

  final String defenceId;

  @override
  ConsumerState<DefenceManuscriptScreen> createState() =>
      _DefenceManuscriptScreenState();
}

class _DefenceManuscriptScreenState
    extends ConsumerState<DefenceManuscriptScreen> {
  final _controller = ManuscriptController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _framed(List<Widget> children) => KeyedSubtree(
    key: const Key('defenceManuscript'),
    child: PageShell(children: children),
  );

  @override
  Widget build(BuildContext context) {
    final defenceAsync = ref.watch(defenceProvider(widget.defenceId));
    final uid = ref.watch(signedInUidProvider);

    if (defenceAsync.isLoading) {
      return _framed(const [LoadingState(label: 'Loading defense…')]);
    }
    if (defenceAsync.hasError) {
      return _framed([
        ErrorState(
          error: defenceAsync.error,
          message: 'Could not load this defense.',
        ),
      ]);
    }
    final defence = defenceAsync.valueOrNull;
    if (defence == null) {
      return _framed(const [
        EmptyState(
          icon: Icons.search_off,
          title: 'Defense not found',
          message: 'This defense no longer exists.',
        ),
      ]);
    }

    // Until auth has said who this is, the gate below cannot be decided, and
    // nothing may be read on the guess that it is not the leader.
    if (uid == null) {
      return _framed(const [LoadingState(label: 'Loading defense…')]);
    }

    // A faculty member who holds both capabilities must be in the mode that
    // matches their seat on THIS defense: adviser mode for the adviser,
    // panelist mode for a panelist. Anything else is turned away here, before
    // a single highlight, grade or evaluation is read.
    final modeGate = checkDefenceModeGate(ref, defence, uid);
    if (modeGate.gate == DefenceModeGate.loading) {
      return _framed(const [LoadingState(label: 'Checking your mode…')]);
    }
    if (modeGate.gate == DefenceModeGate.blocked) {
      return _framed([DefenceModeBlock(needed: modeGate.needed!)]);
    }

    // Decided from the defence alone, before any highlight is read: the
    // rules refuse the group until release, and nothing here may try.
    if (uid == defence.leaderUid && !defence.isReleased) {
      return _framed(const [
        EmptyState(
          icon: Icons.lock_clock_outlined,
          title: 'Not released yet',
          message: 'Available once your adviser releases the comments.',
        ),
      ]);
    }

    final annotationsAsync = ref.watch(
      defenceAnnotationsProvider(widget.defenceId),
    );
    final annotations =
        annotationsAsync.valueOrNull ?? const <DefenceAnnotation>[];
    final parts = ref
        .watch(
          manuscriptPartsProvider((
            defenceId: defence.id,
            thesisId: defence.thesisId,
            type: defence.type,
          )),
        )
        .valueOrNull;

    final list = annotationsAsync.hasError
        ? ErrorState(
            error: annotationsAsync.error,
            message: 'Could not load the highlights.',
          )
        : SingleChildScrollView(
            child: HighlightsList(
              annotations: annotations,
              parts: parts,
              colours: highlightColours(
                defence: defence,
                annotations: annotations,
              ),
              numbers: highlightNumbers(annotations),
              onSelect: _controller.reveal,
            ),
          );

    final pane = DefenceManuscriptPane(
      defence: defence,
      controller: _controller,
    );

    return KeyedSubtree(
      key: const Key('defenceManuscript'),
      child: PageShell(
        scrollable: false,
        maxWidth: AppTokens.measureWide,
        kicker: defence.label,
        title: 'Manuscript',
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 900
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: pane),
                        const SizedBox(width: AppTokens.lg),
                        SizedBox(width: 360, child: list),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 3, child: pane),
                        const SizedBox(height: AppTokens.md),
                        Expanded(flex: 2, child: list),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
