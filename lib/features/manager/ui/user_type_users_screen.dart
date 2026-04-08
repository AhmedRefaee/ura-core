import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/injection.dart';
import '../logic/user_type_cubit.dart';
import 'user_orders_screen.dart';

class UserTypeUsersScreen extends StatelessWidget {
  final String roleKey;
  final String roleLabel;

  const UserTypeUsersScreen({
    super.key,
    required this.roleKey,
    required this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<UserTypeCubit>()..load(roleKey),
      child: _UserTypeUsersView(roleLabel: roleLabel, roleKey: roleKey),
    );
  }
}

class _UserTypeUsersView extends StatelessWidget {
  final String roleKey;
  final String roleLabel;
  const _UserTypeUsersView({required this.roleKey, required this.roleLabel});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(roleLabel),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<UserTypeCubit>().load(roleKey),
          ),
        ],
      ),
      body: BlocBuilder<UserTypeCubit, UserTypeState>(
        builder: (context, state) {
          if (state is UserTypeLoading || state is UserTypeInitial) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is UserTypeError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.message, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.read<UserTypeCubit>().load(roleKey),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }
          if (state is UserTypeLoaded) {
            if (state.users.isEmpty) {
              return Center(child: Text('لا يوجد $roleLabel مسجلون'));
            }
            return ListView.builder(
              itemCount: state.users.length,
              itemBuilder: (_, i) {
                final user = state.users[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: CircleAvatar(child: Text(user.fullName[0])),
                    title: Text(user.fullName),
                    subtitle: Text(user.phone ?? 'لا يوجد رقم هاتف'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserOrdersScreen(user: user),
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
    );
  }
}
