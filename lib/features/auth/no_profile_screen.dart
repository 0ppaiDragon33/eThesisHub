import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Shown to a signed-in account whose `users/{uid}` profile could not be
/// used to route it to a dashboard.
///
/// This project has twice treated "profile missing" as "this person has no
/// rights" and degraded quietly: once it permanently hid a group leader's
/// upload button, once it silently routed a dean down the faculty code
/// path. Both looked like working software. So where the role is unknown,
/// the app says so and stops here, rather than guessing.
///
/// There are two distinct causes, and they are never collapsed into one
/// "something went wrong":
///
/// - The document is genuinely absent (`data(null)`): the read succeeded
///   and came back empty, which almost always means registration did not
///   finish. The remedy is a coordinator, not a retry of the network.
/// - The read itself failed (`error`): offline, refused, or otherwise
///   broken, and the Firestore code is shown via [ErrorState] because that
///   is the only place the reason can surface in the field.
///
/// Renders no [Scaffold] and no [AppBar]: the app shell that hosts this
/// screen owns both, and a second app bar here would double up once wired
/// in.
class NoProfileScreen extends ConsumerWidget {
  const NoProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    final actions = Row(
      children: [
        OutlinedButton(
          key: const Key('noProfileRetry'),
          onPressed: () => ref.invalidate(currentUserProvider),
          child: const Text('Try again'),
        ),
        const SizedBox(width: 12),
        const SignOutButton(),
      ],
    );

    final Widget body = userAsync.when(
      data: (user) {
        if (user != null) {
          // Should not happen: the redirect that sent an account here only
          // does so when there is no profile to route on. If a profile
          // shows up mid-flight, hold a brief loading state rather than
          // asserting or flashing a dead end.
          return const LoadingState();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your account exists, but its profile record is missing. '
              'This usually means registration did not finish. Ask the '
              'College Research Coordinator to check the account.',
            ),
            const SizedBox(height: 16),
            actions,
          ],
        );
      },
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ErrorState(error: error, message: 'Could not read your profile.'),
          const SizedBox(height: 16),
          actions,
        ],
      ),
      loading: () => const LoadingState(),
    );

    return Container(
      key: const Key('noProfileScreen'),
      child: PageShell(
        title: 'Profile unavailable',
        children: [body],
      ),
    );
  }
}
