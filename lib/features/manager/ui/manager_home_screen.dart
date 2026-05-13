import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../auth/logic/auth_state.dart';
import '../../chat/logic/chat_threads_cubit.dart';
import '../../chat/ui/chat_hub_screen.dart';
import '../../notifications/logic/chat_badge_cubit.dart';
import '../../notifications/logic/notifications_badge_cubit.dart';
import '../../inventory/ui/inventory_availability_screen.dart';
import '../../profile/ui/profile_screen.dart';
import '../logic/manager_pending_users_cubit.dart';
import '../logic/monitor_orders_cubit.dart';
import '../logic/stats_cubit.dart';
import '../logic/user_type_cubit.dart';
import 'manager_pending_users_screen.dart';
import 'monitor_tasks_screen.dart';
import 'stats_screen.dart';

class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<MonitorOrdersCubit>()..load()),
        BlocProvider(create: (_) => sl<ManagerPendingUsersCubit>()..load()),
        BlocProvider.value(value: sl<NotificationsBadgeCubit>()),
        BlocProvider.value(value: sl<ChatBadgeCubit>()),
        BlocProvider(create: (_) => sl<StatsCubit>()),
        BlocProvider(create: (_) => sl<ChatThreadsCubit>()..loadThreads()),
      ],
      child: const _ManagerHomeView(),
    );
  }
}

class _ManagerHomeView extends StatefulWidget {
  const _ManagerHomeView();

  @override
  State<_ManagerHomeView> createState() => _ManagerHomeViewState();
}

class _ManagerHomeViewState extends State<_ManagerHomeView> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_navIndex == 2 ? 'المحادثات' : 'لوحة المدير'),
        actions: [
          BlocBuilder<NotificationsBadgeCubit, int>(
            builder: (context, count) => Badge(
              isLabelVisible: count > 0,
              alignment: Alignment.topRight,
              offset: const Offset(-8, 8),
              label: Text(
                count > 9 ? '9+' : '$count',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                tooltip: 'الإشعارات',
                onPressed: () => context.push('/notifications'),
              ),
            ),
          ),
          if (_navIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<MonitorOrdersCubit>().load(),
              tooltip: 'تحديث',
            ),
          if (_navIndex == 2) ...[
            if (chatHubCanCreate(context))
              IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: 'محادثة جديدة',
                onPressed: () => chatHubCreateThread(context),
              ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
              onPressed: () =>
                  context.read<ChatThreadsCubit>().loadThreads(),
            ),
          ],
        ],
      ),
      body: _navIndex == 4
          ? _SettingsTab(
              onInventoryTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const InventoryAvailabilityScreen(),
                ),
              ),
              onLogout: () => context.read<AuthCubit>().signOut(),
            )
          : _navIndex == 2
              ? const ChatHubBody()
              : IndexedStack(
                  index: _navIndex < 2 ? _navIndex : _navIndex - 1,
                  children: const [
                    MonitorTasksScreen(),
                    _UsersTab(),
                    StatsScreen(),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.list_alt_outlined),
            selectedIcon: Icon(Icons.list_alt),
            label: 'الطلبات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'المستخدمون',
          ),
          NavigationDestination(
            icon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => Badge(
                isLabelVisible: count > 0,
                alignment: Alignment.topRight,
                offset: const Offset(-8, 8),
                label: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                backgroundColor: Colors.red,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            selectedIcon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => Badge(
                isLabelVisible: count > 0,
                alignment: Alignment.topRight,
                offset: const Offset(-8, 8),
                label: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                backgroundColor: Colors.red,
                child: const Icon(Icons.chat_bubble),
              ),
            ),
            label: 'المحادثات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'الإحصائيات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
    );
  }
}

// ── Users Tab ─────────────────────────────────────────────────────────────────

class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'طلبات الانضمام'),
              Tab(text: 'المستخدمون'),
            ],
          ),
          const Expanded(
            child: TabBarView(
              children: [
                ManagerPendingUsersScreen(),
                _AllUsersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── All Users Tab ─────────────────────────────────────────────────────────────

class _AllUsersTab extends StatefulWidget {
  const _AllUsersTab();

  @override
  State<_AllUsersTab> createState() => _AllUsersTabState();
}

class _AllUsersTabState extends State<_AllUsersTab> {
  String _role = 'rep';
  late final UserTypeCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = sl<UserTypeCubit>()..load(_role);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'rep', label: Text('مناديب')),
                ButtonSegment(
                    value: 'storage_actor', label: Text('أمناء المخزن')),
                ButtonSegment(value: 'verifier', label: Text('مشرفون')),
              ],
              selected: {_role},
              onSelectionChanged: (s) {
                setState(() => _role = s.first);
                _cubit.load(s.first);
              },
            ),
          ),
          Expanded(
            child: BlocBuilder<UserTypeCubit, UserTypeState>(
              builder: (context, state) {
                if (state is UserTypeLoading || state is UserTypeInitial) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is UserTypeError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(state.message,
                            style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => _cubit.load(_role),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                }
                if (state is UserTypeLoaded) {
                  if (state.users.isEmpty) {
                    return const Center(
                        child: Text('لا يوجد مستخدمون في هذه الفئة'));
                  }
                  return ListView.builder(
                    itemCount: state.users.length,
                    itemBuilder: (_, i) {
                      final user = state.users[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(user.fullName[0]),
                          ),
                          title: Text(user.fullName),
                          subtitle: Text(user.phone ?? 'لا يوجد رقم هاتف'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ProfileScreen(
                                profile: user,
                                isSelf: false,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings Tab ──────────────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final VoidCallback onInventoryTap;
  final VoidCallback onLogout;

  const _SettingsTab({
    required this.onInventoryTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('ملفي الشخصي'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            final state = context.read<AuthCubit>().state;
            if (state is AuthAuthenticated) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileScreen(profile: state.profile),
                ),
              );
            }
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: const Text('المخزون'),
          onTap: onInventoryTap,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.business_outlined),
          title: const Text('إدارة الجهات'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/entities'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings),
          title: const Text('الإعدادات'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/settings'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('تسجيل الخروج'),
          onTap: onLogout,
        ),
      ],
    );
  }
}
