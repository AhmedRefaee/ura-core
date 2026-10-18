import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:ura_core/core/di/injection.dart';
import 'package:ura_core/core/errors/app_error.dart';
import 'package:ura_core/core/errors/app_result.dart';
import 'package:ura_core/features/auth/logic/auth_cubit.dart';
import 'package:ura_core/features/auth/logic/auth_state.dart';
import 'package:ura_core/features/project_share/data/project_share_repository.dart';
import 'package:ura_core/features/project_share/logic/shared_project_cubit.dart';
import 'package:ura_core/features/project_share/models/shared_project.dart';
import 'package:ura_core/features/project_share/ui/shared_project_screen.dart';
import 'package:ura_core/router/app_router.dart';
import 'package:ura_core/shared/models/profile.dart';

class MockProjectShareRepository extends Mock implements ProjectShareRepository {}

class MockAuthCubit extends Mock implements AuthCubit {}

/// What get_shared_project returns -- plus quantity/price keys a buggy or
/// tampered response might carry, which the model must never surface.
final _payload = <String, dynamic>{
  'project_name': 'مشروع الإعاشة',
  'entity_name': 'وزارة الصحة',
  'letterhead_path': null,
  'items': [
    {'category': 'المخبوزات', 'item_name': 'خبز عربي', 'description': 'حجم متوسط', 'unit': 'كيس', 'quantity': 50700, 'unit_price': 1.25},
    {'category': 'الفحم', 'item_name': 'فحم طبيعي', 'description': '  ', 'unit': 'شوال', 'total_price': 162000},
    {'category': 'المخبوزات', 'item_name': 'خبز توست', 'description': null, 'unit': 'كيس'},
  ],
};

void main() {
  group('SharedProject model', () {
    test('parses names/descriptions/units and drops blank descriptions', () {
      final p = SharedProject.fromMap(_payload);
      expect(p.projectName, 'مشروع الإعاشة');
      expect(p.entityName, 'وزارة الصحة');
      expect(p.items, hasLength(3));
      expect(p.items[0], const SharedItem(category: 'المخبوزات', itemName: 'خبز عربي', description: 'حجم متوسط', unit: 'كيس'));
      expect(p.items[1].description, isNull);
    });

    test('groups by category in first-appearance order', () {
      final groups = SharedProject.fromMap(_payload).byCategory;
      expect(groups.keys, ['المخبوزات', 'الفحم']);
      expect(groups['المخبوزات']!.map((i) => i.itemName), ['خبز عربي', 'خبز توست']);
    });

    test('a link is active until revoked or expired', () {
      final now = DateTime(2026, 10, 18);
      ProjectShareLink link({DateTime? expires, DateTime? revoked}) =>
          ProjectShareLink(id: 'l', token: 't', createdAt: now, expiresAt: expires, revokedAt: revoked);
      expect(link().isActive(now), isTrue);
      expect(link(expires: now.add(const Duration(days: 1))).isActive(now), isTrue);
      expect(link(expires: now.subtract(const Duration(seconds: 1))).isActive(now), isFalse);
      expect(link(revoked: now).isActive(now), isFalse);
    });

    test('link URL points at the website, hash-routed', () {
      expect(shareLinkUrl('abc'), 'https://ura-core-9981c.web.app/#/share/abc');
    });
  });

  group('SharedProjectCubit', () {
    late MockProjectShareRepository repo;
    setUp(() => repo = MockProjectShareRepository());

    test('loaded on a valid token', () async {
      when(() => repo.fetchShared('t')).thenAnswer((_) async => AppSuccess(SharedProject.fromMap(_payload)));
      final cubit = SharedProjectCubit(repo, 't');
      await cubit.load();
      expect(cubit.state, isA<SharedProjectLoaded>());
    });

    test('invalid when the server returns null', () async {
      when(() => repo.fetchShared('t')).thenAnswer((_) async => const AppSuccess(null));
      final cubit = SharedProjectCubit(repo, 't');
      await cubit.load();
      expect(cubit.state, const SharedProjectInvalid());
    });

    test('error on failure', () async {
      when(() => repo.fetchShared('t')).thenAnswer(
        (_) async => const AppFailure(AppError(message: 'x', type: AppErrorType.network)),
      );
      final cubit = SharedProjectCubit(repo, 't');
      await cubit.load();
      expect(cubit.state, const SharedProjectError('x'));
    });
  });

  group('SharedProjectScreen', () {
    Future<void> pumpScreen(WidgetTester tester, AppResult<SharedProject?> result) async {
      final repo = MockProjectShareRepository();
      when(() => repo.fetchShared('t')).thenAnswer((_) async => result);
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BlocProvider(
            create: (_) => SharedProjectCubit(repo, 't')..load(),
            child: const SharedProjectScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows categories, names, descriptions, units -- never quantity or price', (tester) async {
      await pumpScreen(tester, AppSuccess(SharedProject.fromMap(_payload)));

      for (final text in ['مشروع الإعاشة', 'وزارة الصحة', 'المخبوزات', 'الفحم', 'خبز عربي', 'حجم متوسط', 'فحم طبيعي', 'خبز توست', 'شوال']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('كيس'), findsNWidgets(2));
      for (final leaked in ['50700', '50,700', '1.25', '162000', '162,000']) {
        expect(find.textContaining(leaked), findsNothing, reason: leaked);
      }
    });

    testWidgets('invalid link message', (tester) async {
      await pumpScreen(tester, const AppSuccess(null));
      expect(find.text('هذا الرابط غير صالح أو انتهت صلاحيته'), findsOneWidget);
    });
  });

  group('router', () {
    late MockAuthCubit auth;
    late StreamController<AuthState> authStream;
    late AuthState authState;

    setUp(() {
      authStream = StreamController<AuthState>.broadcast();
      authState = AuthLoading();
      auth = MockAuthCubit();
      when(() => auth.stream).thenAnswer((_) => authStream.stream);
      when(() => auth.state).thenAnswer((_) => authState);
      when(() => auth.hasPendingOrgCreation).thenReturn(false);
      final repo = MockProjectShareRepository();
      when(() => repo.fetchShared(any())).thenAnswer((_) async => AppSuccess(SharedProject.fromMap(_payload)));
      sl.registerSingleton<ProjectShareRepository>(repo);
    });

    tearDown(() async {
      await sl.unregister<ProjectShareRepository>();
      await authStream.close();
    });

    const profile = Profile(id: 'u', fullName: 'x', isApproved: false, role: UserRole.rep);

    for (final (name, next) in [
      ('signed out', AuthUnauthenticated()),
      ('pending approval', const AuthPendingApproval(profile)),
      ('needs onboarding', AuthNeedsOnboarding()),
      ('logged in', const AuthAuthenticated(profile)),
    ]) {
      testWidgets('/share/:token stays put when $name', (tester) async {
        final router = createRouter(auth);
        await tester.pumpWidget(BlocProvider<AuthCubit>.value(
          value: auth,
          child: MaterialApp.router(routerConfig: router),
        ));
        router.go('/share/abc');
        await tester.pumpAndSettle();

        authState = next;
        authStream.add(next);
        await tester.pumpAndSettle();

        expect(router.routerDelegate.currentConfiguration.uri.path, '/share/abc');
        expect(find.byType(SharedProjectScreen), findsOneWidget);
      });
    }
  });
}
