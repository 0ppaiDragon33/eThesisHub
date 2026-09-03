import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
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
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}