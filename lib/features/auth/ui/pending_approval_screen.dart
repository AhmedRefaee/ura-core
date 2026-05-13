import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';

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
                    Icon(
                      Icons.hourglass_top_rounded,
                      size: 72,
                      color: AppColors.warning,
                    ),
                    SizedBox(height: AppSpacing.verticalXXLarge),
                    Text(
                      'مرحباً ${profile?.fullName ?? ''}',
                      style: AppTextStyles.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: AppSpacing.verticalLarge),
                    Text(
                      'حسابك قيد المراجعة.\nيرجى الانتظار حتى يوافق المشرف على حسابك.',
                      style: AppTextStyles.bodyLarge.copyWith(height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 40),
                    AppButton(
                      text: 'تحديث الحالة',
                      onPressed: isLoading
                          ? null
                          : () => context.read<AuthCubit>().refreshProfile(),
                      isLoading: isLoading,
                      icon: Icons.refresh,
                      variant: AppButtonVariant.elevated,
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    AppButton(
                      text: 'تسجيل الخروج',
                      onPressed: () => context.read<AuthCubit>().signOut(),
                      variant: AppButtonVariant.text,
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
