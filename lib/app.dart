import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/platform/native_back.dart';
import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/idle_logout.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/theme_provider.dart';

class EThesisHubApp extends ConsumerStatefulWidget {
  const EThesisHubApp({super.key});

  @override
  ConsumerState<EThesisHubApp> createState() => _EThesisHubAppState();
}

class _EThesisHubAppState extends ConsumerState<EThesisHubApp> {
  @override
  void initState() {
    super.initState();
    // Let MainActivity's back handler pop a pushed screen through go_router
    // before it double-backs to exit. Harmless on web, where the channel is
    // never called.
    registerNativeBackHandler(ref.read(goRouterProvider));
  }

  @override
  Widget build(BuildContext context) {
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
