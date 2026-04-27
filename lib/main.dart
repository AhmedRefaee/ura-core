import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'config/supabase_config.dart';
import 'core/di/injection.dart';
import 'core/logging/app_logger.dart';

bool _isAuthCallback(Uri uri) =>
    uri.queryParameters.containsKey('code') ||
    uri.fragment.contains('access_token=') ||
    uri.fragment.contains('refresh_token=');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    debug: true,
  );

  await setupDependencies();

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

  runApp(const UraApp());
}
