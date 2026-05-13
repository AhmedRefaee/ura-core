import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/di/injection.dart';
import 'core/logging/app_logger.dart';
import 'core/notifications/notification_service.dart';
import 'core/design_system/theme/app_theme.dart';
import 'features/auth/logic/auth_cubit.dart';
import 'features/settings/logic/theme_cubit.dart';
import 'router/app_router.dart';

bool _isAuthCallback(Uri uri) =>
    uri.queryParameters.containsKey('code') ||
    uri.fragment.contains('access_token=') ||
    uri.fragment.contains('refresh_token=');

class UraApp extends StatefulWidget {
  const UraApp({super.key});

  @override
  State<UraApp> createState() => _UraAppState();
}

class _UraAppState extends State<UraApp> {
  late final StreamSubscription _linkSubscription;
  GoRouter? _router;

  @override
  void initState() {
    super.initState();  
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) async {
      logger.d('UraApp → deep link received: $uri');
      if (!_isAuthCallback(uri)) return;
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } catch (e) {
        logger.w('UraApp → getSessionFromUrl failed: $e');
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => sl<AuthCubit>()..checkSession(),
        ),
        BlocProvider(
          create: (_) => sl<ThemeCubit>()..initializeTheme(),
        ),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          final authCubit = context.read<AuthCubit>();
          _router ??= createRouter(authCubit);
          sl<NotificationService>().setRouter(_router!);

          return MaterialApp.router(
            title: 'URA CORE',
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: _router!,
          );
        },
      ),
    );
  }
}
