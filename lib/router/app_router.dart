import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/logic/auth_cubit.dart';
import '../features/auth/logic/auth_state.dart';
import '../features/auth/ui/login_screen.dart';
import '../features/auth/ui/register_screen.dart';
import '../features/auth/ui/pending_approval_screen.dart';
import '../features/auth/ui/forgot_password_screen.dart';
import '../features/auth/ui/reset_password_screen.dart';
import '../features/auth/ui/create_org_name_screen.dart';
import '../features/auth/ui/create_org_details_screen.dart';
import '../features/auth/ui/join_org_screen.dart';
import '../features/admin/ui/admin_console_screen.dart';
import '../features/verifier/ui/verifier_home_screen.dart';
import '../features/rep/ui/rep_home_screen.dart';
import '../features/rep/ui/rep_order_detail_screen.dart';
import '../features/rep/logic/rep_order_detail_cubit.dart';
import '../features/storage/ui/storage_home_screen.dart';
import '../features/storage/ui/storage_order_detail_screen.dart';
import '../features/storage/logic/storage_order_detail_cubit.dart';
import '../features/manager/ui/manager_home_screen.dart';
import '../features/manager/ui/task_detail_screen.dart';
import '../core/di/injection.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/chat/ui/chat_hub_screen.dart';
import '../features/chat/ui/chat_thread_screen.dart';
import '../features/notifications/logic/notifications_cubit.dart';
import '../features/notifications/ui/notifications_screen.dart';
import '../features/entities/logic/entities_cubit.dart';
import '../features/entities/ui/entities_screen.dart';
import '../features/settings/ui/settings_screen.dart';
import '../shared/models/profile.dart';

class AppRoutes {
  static const String login = '/login';
  static const String register = '/register';
  static const String createOrgName = '/create-org';
  static const String createOrgDetails = '/onboarding/create-details';
  static const String joinOrg = '/onboarding/join';
  static const String admin = '/admin';
  static const String pending = '/pending';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';
  static const String verifierHome = '/verifier';
  static const String repHome = '/rep';
  static const String storageHome = '/storage';
  static const String managerHome = '/manager';
  static const String chat = '/chat';
  static const String notifications = '/notifications';
  static const String entities = '/entities';
  static const String settings = '/settings';
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
          location == AppRoutes.createOrgName ||
          location == AppRoutes.forgotPassword;
      final isOnPending = location == AppRoutes.pending;
      final isOnOnboarding = location == AppRoutes.createOrgDetails ||
          location == AppRoutes.joinOrg;
      final isOnAdmin = location == AppRoutes.admin;

      if (authState is AuthUnauthenticated || authState is AuthError) {
        return isOnAuthPage ? null : AppRoutes.login;
      }

      if (authState is AuthNeedsOnboarding) {
        final target = authCubit.hasPendingOrgCreation
            ? AppRoutes.createOrgDetails
            : AppRoutes.joinOrg;
        return location == target ? null : target;
      }

      if (authState is AuthPlatformAdmin) {
        return isOnAdmin ? null : AppRoutes.admin;
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
        if (isOnAuthPage || isOnPending || isOnOnboarding || isOnAdmin) {
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
        path: AppRoutes.createOrgName,
        builder: (_, _) => const CreateOrgNameScreen(),
      ),
      GoRoute(
        path: AppRoutes.createOrgDetails,
        builder: (_, _) => const CreateOrgDetailsScreen(),
      ),
      GoRoute(
        path: AppRoutes.joinOrg,
        builder: (_, _) => const JoinOrgScreen(),
      ),
      GoRoute(
        path: AppRoutes.admin,
        builder: (_, _) => const AdminConsoleScreen(),
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
        path: AppRoutes.notifications,
        builder: (_, _) => BlocProvider(
          create: (_) => sl<NotificationsCubit>()..load(),
          child: const NotificationsScreen(),
        ),
      ),
      GoRoute(
        path: '/chat/:threadId',
        builder: (_, state) {
          final threadId = state.pathParameters['threadId']!;
          return _ChatThreadLoader(threadId: threadId);
        },
      ),
      GoRoute(
        path: '/orders/:orderId',
        builder: (_, state) => _OrderDeepLinkLoader(
          orderId: state.pathParameters['orderId']!,
          authCubit: authCubit,
        ),
      ),
      GoRoute(
        path: '/order/:orderId',
        redirect: (_, state) => '/orders/${state.pathParameters['orderId']}',
      ),
      GoRoute(
        path: '/pending-user/:userId',
        redirect: (_, _) {
          final authState = authCubit.state;
          if (authState is AuthAuthenticated) {
            return AppRoutes.managerHome;
          }
          return AppRoutes.login;
        },
      ),
      GoRoute(
        path: AppRoutes.entities,
        builder: (_, _) => BlocProvider(
          create: (_) => sl<EntitiesCubit>()..load(),
          child: const EntitiesScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, _) => const SettingsScreen(),
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

// ── Order deep-link loader ────────────────────────────────────────────────────
// Opened when a push notification with route /orders/:id is tapped.
// Works for any order status including delivered.

class _OrderDeepLinkLoader extends StatelessWidget {
  final String orderId;
  final AuthCubit authCubit;
  const _OrderDeepLinkLoader({required this.orderId, required this.authCubit});

  @override
  Widget build(BuildContext context) {
    final authState = authCubit.state;
    if (authState is! AuthAuthenticated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final role = authState.profile.role;

    switch (role) {
      case UserRole.rep:
        return BlocProvider(
          create: (_) => sl.get<RepOrderDetailCubit>(param1: orderId)..load(),
          child: const RepOrderDetailScreen(),
        );
      case UserRole.storageActor:
        return BlocProvider(
          create: (_) =>
              sl.get<StorageOrderDetailCubit>(param1: orderId)..load(),
          child: const StorageOrderDetailScreen(),
        );
      default:
        return TaskDetailScreen(orderId: orderId);
    }
  }
}

class _ChatThreadLoader extends StatefulWidget {
  final String threadId;
  const _ChatThreadLoader({required this.threadId});

  @override
  State<_ChatThreadLoader> createState() => _ChatThreadLoaderState();
}

class _ChatThreadLoaderState extends State<_ChatThreadLoader> {
  String? _title;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTitle();
  }

  Future<void> _loadTitle() async {
    try {
      final data = await Supabase.instance.client
          .from('chat_threads')
          .select('title')
          .eq('id', widget.threadId)
          .single();
      if (mounted) setState(() { _title = data['title'] as String?; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _title = 'محادثة'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    final child = _loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : ChatThreadScreen(threadId: widget.threadId, threadTitle: _title ?? 'محادثة');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (router.canPop()) {
          router.pop();
        } else {
          // No back stack (cold-start deep link) — the redirect sends the
          // authenticated user to their role home screen.
          router.go(AppRoutes.login);
        }
      },
      child: child,
    );
  }
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
