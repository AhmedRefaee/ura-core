import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/logic/auth_cubit.dart';
import '../features/auth/logic/auth_state.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/ui/register_screen.dart';
import '../features/auth/ui/pending_approval_screen.dart';
import '../features/auth/ui/forgot_password_screen.dart';
import '../features/auth/ui/reset_password_screen.dart';
import '../features/verifier/ui/verifier_home_screen.dart';
import '../features/rep/ui/rep_home_screen.dart';
import '../features/storage/ui/storage_home_screen.dart';
import '../features/manager/ui/manager_home_screen.dart';
import '../features/chat/ui/chat_hub_screen.dart';
import '../shared/models/profile.dart';

class AppRoutes {
  static const String login = '/login';
  static const String register = '/register';
  static const String pending = '/pending';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String verifierHome = '/verifier';
  static const String repHome = '/rep';
  static const String storageHome = '/storage';
  static const String managerHome = '/manager';
  static const String chat = '/chat';
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

GoRouter createRouter(AuthCubit authCubit) {
  return GoRouter(
    initialLocation: AppRoutes.login,
    refreshListenable: GoRouterRefreshStream(authCubit.stream),
    redirect: (context, state) {
      final authState = authCubit.state;
      final location = state.matchedLocation;

      if (authState is AuthInitial || authState is AuthLoading) return null;

      final isOnAuthPage = location == AppRoutes.login ||
          location == AppRoutes.register ||
          location == AppRoutes.forgotPassword;
      final isOnPending = location == AppRoutes.pending;

      if (authState is AuthUnauthenticated || authState is AuthError) {
        return isOnAuthPage ? null : AppRoutes.login;
      }

      if (authState is AuthPendingApproval) {
        return isOnPending ? null : AppRoutes.pending;
      }

      if (authState is AuthPasswordRecovery) {
        return location == AppRoutes.resetPassword
            ? null
            : AppRoutes.resetPassword;
      }

      if (authState is AuthAuthenticated) {
        if (isOnAuthPage || isOnPending) {
          return _roleRoute(authState.profile.role);
        }
        return null;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (_, _) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.pending,
        builder: (_, _) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifierHome,
        builder: (_, _) => const VerifierHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.repHome,
        builder: (_, _) => const RepHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.storageHome,
        builder: (_, _) => const StorageHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.managerHome,
        builder: (_, _) => const ManagerHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (_, _) => const ChatHubScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, _) => const ResetPasswordScreen(),
      ),
    ],
  );
}

String _roleRoute(UserRole? role) {
  switch (role) {
    case UserRole.verifier:
      return AppRoutes.verifierHome;
    case UserRole.rep:
      return AppRoutes.repHome;
    case UserRole.storageActor:
      return AppRoutes.storageHome;
    case UserRole.manager:
      return AppRoutes.managerHome;
    default:
      return AppRoutes.pending;
  }
}
