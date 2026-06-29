import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../core/di/injection.dart';
import '../../../shared/widgets/notification_dot.dart';
import '../../../core/design_system/widgets/widgets.dart';
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
      body: switch (_navIndex) {
        0 || 1 => IndexedStack(
          index: _navIndex,
          children: const [MonitorTasksScreen(), InventoryAvailabilityScreen()],
        ),
        2 => const ChatHubSection(),
        3 => const _UsersTab(),
        _ => _SettingsTab(
          onLogout: () => context.read<AuthCubit>().signOut(),
        ),
      },
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
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'المخزون',
          ),
          NavigationDestination(
            icon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => NotificationDot(
                isVisible: count > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
            ),
            selectedIcon: BlocBuilder<ChatBadgeCubit, int>(
              builder: (context, count) => NotificationDot(
                isVisible: count > 0,
                child: const Icon(Icons.chat_bubble),
              ),
            ),
            label: 'المحادثات',
          ),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'المستخدمون',
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

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('لوحة المدير'),
      actions: [
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.push('/notifications'),
            ),
          ),
        ),
      ],
      sliverBottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'طلبات الانضمام'),
          Tab(text: 'المستخدمون'),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Builder(
            builder: (ctx) => CollapsingInnerScrollBody(
              slivers: const [
                SliverFillRemaining(child: ManagerPendingUsersScreen()),
              ],
            ),
          ),
          Builder(
            builder: (ctx) => CollapsingInnerScrollBody(
              slivers: const [
                SliverFillRemaining(child: _AllUsersTab()),
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
                ButtonSegment(value: 'manager', label: Text('مديرون')),
                ButtonSegment(value: 'admin', label: Text('مديرون عامون')),
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
  final VoidCallback onLogout;

  const _SettingsTab({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return CollapsingHeaderWrapper(
      title: const Text('الإعدادات'),
      actions: [
        BlocBuilder<NotificationsBadgeCubit, int>(
          builder: (context, count) => NotificationDot(
            isVisible: count > 0,
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'الإشعارات',
              onPressed: () => context.push('/notifications'),
            ),
          ),
        ),
      ],
      body: Builder(
        builder: (ctx) => CollapsingInnerScrollBody(
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
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
                          builder: (_) =>
                              ProfileScreen(profile: state.profile),
                        ),
                      );
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.bar_chart_outlined),
                  title: const Text('الإحصائيات'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider(
                        create: (_) => sl<StatsCubit>(),
                        child: const StatsScreen(),
                      ),
                    ),
                  ),
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
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
