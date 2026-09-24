import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/components/document.dart';
import 'package:ethesishub/core/design/layout.dart';
import 'package:ethesishub/core/design/tone.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/audit_entry.dart';
import 'package:ethesishub/providers/admin_providers.dart';

/// The coordinator/dean view of the audit log: who did what, to which
/// record, and when. Read-only — entries are written by the actions
/// themselves and are append-only in the rules.
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logAsync = ref.watch(auditLogProvider);

    return KeyedSubtree(
      key: const Key('auditLogScreen'),
      child: PageShell(
        kicker: 'Management',
        title: 'Activity log',
        subtitle: 'A record of privileged actions — publishing, deactivating '
            'an account, issuing an invite, releasing evaluations.',
        maxWidth: AppTokens.measureWide,
        children: [
          logAsync.when(
            loading: () => const LoadingState(label: 'Loading the log…'),
            error: (e, _) => ErrorState(
              error: e,
              message: 'Could not load the activity log.',
            ),
            data: (entries) => entries.isEmpty
                ? const EmptyState(
                    key: Key('auditEmpty'),
                    title: 'Nothing logged yet.',
                    message: 'Privileged actions will appear here as they '
                        'happen.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in entries) _AuditRow(e),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow(this.entry);

  final AuditEntry entry;

  /// `account.deactivated` -> `Account deactivated`. The namespaced verb is
  /// built for querying; this makes it read as a sentence.
  static String humanize(String action) {
    final words = action.replaceAll('.', ' ').replaceAll('_', ' ');
    if (words.isEmpty) return 'Action';
    return words[0].toUpperCase() + words.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final when = entry.at == null ? 'Just now' : Dates.relative(entry.at!);
    return RecordRow(
      key: Key('auditRow-${entry.id}'),
      leading: Icon(Icons.history_rounded,
          size: 18, color: Tone.neutral.color(context)),
      title: humanize(entry.action),
      subtitle: '${entry.targetType} · ${entry.targetId} · by ${entry.actorUid}',
      trailing: Text(when, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
