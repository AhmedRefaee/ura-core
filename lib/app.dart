import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/di/injection.dart';
import 'core/logging/app_logger.dart';
import 'features/auth/logic/auth_cubit.dart';
import 'router/app_router.dart';

class UraApp extends StatefulWidget {
  const UraApp({super.key});

  @override
  State<UraApp> createState() => _UraAppState();
}

class _UraAppState extends State<UraApp> {
  late final StreamSubscription _linkSubscription;

  @override
  void initState() {
    super.initState();
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) async {
      logger.d('UraApp → deep link received: $uri');
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
    return BlocProvider(
      create: (_) => sl<AuthCubit>()..checkSession(),
      child: Builder(
        builder: (context) {
          final authCubit = context.read<AuthCubit>();
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
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
              useMaterial3: true,
            ),
            routerConfig: createRouter(authCubit),
          );
        },
      ),
    );
  }
}
