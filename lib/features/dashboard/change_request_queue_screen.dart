import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/dashboard/change_request_queue.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// The `/change-requests` destination: the Coordinator's or the Dean's
/// change-of-adviser / change-of-title queue, chosen from the signed-in
/// role. Reachable only by a coordinator or a dean (app_router.dart's role
/// guard, modelled on '/recommendations' and '/title-defences').
class ChangeRequestQueueScreen extends ConsumerWidget {
  const ChangeRequestQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserProvider).valueOrNull?.role;
    final asDean = role == UserRole.dean;

    return PageShell(
      key: const Key('changeRequestQueueScreen'),
      maxWidth: AppTokens.measureWide,
      kicker: asDean ? 'Office of the Dean' : 'Research office',
      title: 'Change requests',
      subtitle: asDean
          ? 'Requests the Coordinator has recommended. Approving one '
                'applies the change to the thesis.'
          : 'Requests every co-signer has accepted, waiting on your '
                'recommendation to the Dean.',
      children: [ChangeRequestQueue(asDean: asDean)],
    );
  }
}
