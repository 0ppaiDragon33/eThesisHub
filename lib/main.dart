import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/firebase_options.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

void main() {
  // TEMPORARY DIAGNOSTIC — remove once the permission-denied is identified.
  //
  // A Firestore rejection that nothing awaits escapes as a bare browser
  // "Uncaught (in promise)" with a JS-only stack, which names neither the
  // collection nor the Dart call site. Running the app inside a guarded
  // zone catches those rejections and prints the Dart stack instead, and
  // Firestore's own logging names the Listen target that was refused.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    if (kDebugMode) {
      FirebaseFirestore.setLoggingEnabled(true);
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );

    final prefs = await SharedPreferences.getInstance();

    runApp(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const EThesisHubApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('╔══ UNCAUGHT ASYNC ERROR ═══════════════════════════════');
    debugPrint('║ $error');
    debugPrint('╠═══════════════════════════════════════════════════════');
    debugPrint('$stack');
    debugPrint('╚═══════════════════════════════════════════════════════');
  });
}