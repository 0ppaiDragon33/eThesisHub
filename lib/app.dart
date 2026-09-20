import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/idle_logout.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/theme_provider.dart';

class EThesisHubApp extends ConsumerWidget {
  const EThesisHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep these alive so router redirects see fresh values.
    ref.watch(authStateProvider);
    ref.watch(currentUserProvider);

    return MaterialApp.router(
      title: 'eThesisHub',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      scaffoldMessengerKey: _messengerKey,
      routerConfig: ref.watch(goRouterProvider),
      // Below the router so a tap on any screen resets the idle clock, and so
      // the sign-out notice shows through the shared messenger.
      builder: (context, child) => IdleLogout(
        messengerKey: _messengerKey,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// One messenger for the whole app, so the idle-logout notice survives the
/// navigation back to the login screen.
final _messengerKey = GlobalKey<ScaffoldMessengerState>();