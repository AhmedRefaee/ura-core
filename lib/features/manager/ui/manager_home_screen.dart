import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../../auth/logic/auth_cubit.dart';
import '../logic/manager_pending_users_cubit.dart';
import '../logic/monitor_orders_cubit.dart';
import 'manager_pending_users_screen.dart';
import 'monitor_tasks_screen.dart';
import 'monitor_users_screen.dart';

class ManagerHomeScreen extends StatelessWidget {
  const ManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<MonitorOrdersCubit>()),
        BlocProvider(create: (_) => sl<ManagerPendingUsersCubit>()),
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
        title: const Text('لوحة المدير'),
        actions: [
          if (_navIndex == 0)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => context.read<MonitorOrdersCubit>().load(),
              tooltip: 'تحديث',
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => context.read<AuthCubit>().signOut(),
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: const [
          _MonitorTab(),
          ManagerPendingUsersScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) {
          setState(() => _navIndex = i);
          if (i == 1) {
            context.read<ManagerPendingUsersCubit>().load();
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.monitor_outlined),
            selectedIcon: Icon(Icons.monitor),
            label: 'المراقبة',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_add_outlined),
            selectedIcon: Icon(Icons.person_add),
            label: 'مستخدمون جدد',
          ),
        ],
      ),
    );
  }
}

class _MonitorTab extends StatefulWidget {
  const _MonitorTab();

  @override
  State<_MonitorTab> createState() => _MonitorTabState();
}

class _MonitorTabState extends State<_MonitorTab> {
  int _segmentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('بالمستخدم'),
                icon: Icon(Icons.people_outline),
              ),
              ButtonSegment(
                value: 1,
                label: Text('بالمهمة'),
                icon: Icon(Icons.list_alt_outlined),
              ),
            ],
            selected: {_segmentIndex},
            onSelectionChanged: (s) {
              setState(() => _segmentIndex = s.first);
              if (s.first == 1) {
                context.read<MonitorOrdersCubit>().load();
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _segmentIndex == 0
              ? const MonitorUsersScreen()
              : const MonitorTasksScreen(),
        ),
      ],
    );
  }
}
