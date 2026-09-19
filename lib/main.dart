import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Serve reads from a local cache when the network drops — campus wifi is
  // not reliable, and a defence should not stall on a lost connection.
  // Persistence is already on by default on Android/iOS; setting it here is
  // explicit for those and is what opts Web in (IndexedDB). Must be set
  // before any Firestore access, so it sits right after initializeApp. A
  // second browser tab may decline to share the cache — the app still works,
  // just without the offline cache in that tab.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // Crash reporting, so a failure during the defence demo leaves a record
  // instead of a blank stare. Crashlytics is Android/iOS only — it has no
  // web plugin — so on Web the same two hooks fall back to presenting the
  // error, which is all the framework can do there.
  if (!kIsWeb) {
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    // Errors outside the Flutter callchain (async gaps, platform channels)
    // that the framework does not route through FlutterError.
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } else {
    FlutterError.onError = FlutterError.presentError;
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
}