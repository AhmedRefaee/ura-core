import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final profile =
            state is AuthPendingApproval ? state.profile : null;
        final isLoading = state is AuthLoading;

        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      size: 72,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'مرحباً ${profile?.fullName ?? ''}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'حسابك قيد المراجعة.\nيرجى الانتظار حتى يوافق المشرف على حسابك.',
                      style: TextStyle(fontSize: 16, height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    FilledButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => context.read<AuthCubit>().refreshProfile(),
                      icon: isLoading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('تحديث الحالة'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => context.read<AuthCubit>().signOut(),
                      child: const Text('تسجيل الخروج'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
