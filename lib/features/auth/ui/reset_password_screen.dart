import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _validationError;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 6) {
      setState(() => _validationError = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل');
      return;
    }
    if (password != confirm) {
      setState(() => _validationError = 'كلمتا المرور غير متطابقتين');
      return;
    }

    setState(() => _validationError = null);
    context.read<AuthCubit>().updatePassword(password);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Scaffold(
          appBar: AppBar(
            title: const Text('تعيين كلمة مرور جديدة'),
            automaticallyImplyLeading: false,
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: AppSpacing.screenPaddingInsets,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(Icons.lock_reset_outlined,
                          size: 56, color: AppColors.primary),
                      SizedBox(height: AppSpacing.verticalXXLarge),
                      Text(
                        'أدخل كلمة المرور الجديدة',
                        style: AppTextStyles.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: AppSpacing.verticalXXXLarge),
                      AppTextField(
                        controller: _passwordController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.visiblePassword,
                        label: 'كلمة المرور الجديدة',
                      ),
                      SizedBox(height: AppSpacing.verticalLarge),
                      AppTextField(
                        controller: _confirmController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.visiblePassword,
                        label: 'تأكيد كلمة المرور',
                      ),
                      if (_validationError != null) ...[
                        SizedBox(height: AppSpacing.verticalMedium),
                        Text(
                          _validationError!,
                          style: TextStyle(
                              color: AppColors.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      SizedBox(height: AppSpacing.verticalXXLarge),
                      AppButton(
                        text: 'تعيين كلمة المرور',
                        onPressed: isLoading ? null : _submit,
                        isLoading: isLoading,
                        variant: AppButtonVariant.elevated,
                        height: 50,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
