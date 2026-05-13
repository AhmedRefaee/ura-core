import 'package:app_links/app_links.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'config/supabase_config.dart';
import 'core/di/injection.dart';
import 'core/logging/app_logger.dart';
import 'core/notifications/notification_service.dart';
import 'firebase_options.dart';

bool _isAuthCallback(Uri uri) =>
    uri.queryParameters.containsKey('code') ||
    uri.fragment.contains('access_token=') ||
    uri.fragment.contains('refresh_token=');

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  timeago.setLocaleMessages('ar', timeago.ArMessages());

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    debug: true,
  );

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
