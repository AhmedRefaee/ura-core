import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'config/supabase_config.dart';
import 'core/di/injection.dart';
import 'core/logging/app_logger.dart';
import 'core/logging/crashlytics_reporter.dart';
import 'core/notifications/notification_service.dart';
import 'firebase_options.dart';

bool _isAuthCallback(Uri uri) =>
    uri.queryParameters.containsKey('code') ||
    uri.fragment.contains('access_token=') ||
    uri.fragment.contains('refresh_token=');

/// Routes uncaught framework and async errors to Crashlytics, and points
/// [AppLogger] at it so `logger.e` survives release builds.
///
/// Crashlytics has no web implementation, so callers must guard on `!kIsWeb`.
Future<void> _initCrashReporting() async {
  final crashlytics = FirebaseCrashlytics.instance;

  // Debug runs stay out of the dashboard — the console already shows them,
  // and they would otherwise drown out real user crashes.
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);

  logger.useCrashReporter(CrashlyticsReporter(crashlytics));

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    crashlytics.recordFlutterFatalError(details);
  };

  // Async errors that never reach the Flutter framework at all.
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  timeago.setLocaleMessages('ar', timeago.ArMessages());

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Vouches this is a genuine, unmodified copy of the app before Firebase
  // lets a Gemini call through -- the Firebase config shipped in the app is
  // public by design (extractable from the APK, readable in a web JS bundle),
  // so without this, anyone who copies it could call Gemini through this
  // project's billing. AndroidDebugProvider only produces a token once that
  // build's one-time debug token is registered in the Firebase Console.
  //
  // Android only, deliberately -- and the guard has to be skipping the CALL,
  // not just omitting providerWeb. firebase_app_check_web's activate() only
  // wraps its localStorage write in a null check; it then passes the provider
  // straight to getAppCheckInstance() regardless, so a null one reaches the JS
  // SDK and throws "Cannot read properties of null (reading 'initialize')",
  // taking the whole web app down at startup rather than merely leaving it
  // unattested.
  //
  // Web is not a shipping target yet. When it becomes one it needs a reCAPTCHA
  // ENTERPRISE key created inside the ura-core-9981c Google Cloud project
  // itself -- classic reCAPTCHA v3 is dead (Google stopped issuing new classic
  // keys in Q3 2024 and finished auto-migrating the rest in Q1 2026, so the App
  // Check console's classic registration form is disabled), and an Enterprise
  // key auto-migrated into some other project cannot be used here. Pair that
  // key with ReCaptchaEnterpriseProvider, not V3, and add providerWeb here.
  //
  // Until then the web build carries no App Check token, so with enforcement on
  // for AI Logic its Gemini calls are rejected by design. Everything else in
  // the web app works normally.
  if (!kIsWeb) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  }

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await _initCrashReporting();
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    debug: false,
  );

  // Ties crash reports to whoever is signed in, so a report from the warehouse
  // can be traced back to the account that hit it.
  Supabase.instance.client.auth.onAuthStateChange.listen((state) {
    unawaited(logger.crashReporter.setUserId(state.session?.user.id));
  });

  await setupDependencies();
  await sl<NotificationService>().init();

  // Handle cold-start deep link (app was not running when link was tapped)
  final initialUri = await AppLinks().getInitialLink();
  if (initialUri != null) {
    logger.d('main → cold-start deep link: $initialUri');
    if (_isAuthCallback(initialUri)) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(initialUri);
      } catch (e) {
        logger.w('main → getSessionFromUrl failed: $e');
      }
    }
  }

  logger.i('App started — URA CORE');

  FlutterNativeSplash.remove();
  runApp(const UraApp());
}
