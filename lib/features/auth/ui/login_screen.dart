import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../router/app_router.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _errorMessage = null);
    context.read<AuthCubit>().signIn(
          _emailController.text.trim(),
          _passwordController.text,
        );
  }



  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthError) {
          setState(() => _errorMessage = state.message);
        }
      },
      builder: (context, state) {
        final isLoading = state is AuthLoading;
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: AppSpacing.screenPaddingInsets,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'تسجيل الدخول',
                        style: AppTextStyles.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: AppSpacing.verticalXXXLarge),
                      AppTextField(
                        controller: _emailController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.emailAddress,
                        label: 'البريد الإلكتروني',
                        focusNode: _emailFocusNode,
                      ),
                      SizedBox(height: AppSpacing.verticalLarge),
                      AppTextField(
                        controller: _passwordController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.visiblePassword,
                        label: 'كلمة المرور',
                        focusNode: _passwordFocusNode,
                      ),
                      if (_errorMessage != null) ...[
                        SizedBox(height: AppSpacing.verticalMedium),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: AppColors.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      SizedBox(height: AppSpacing.verticalXXLarge),
                      AppButton(
                        text: 'دخول',
                        onPressed: isLoading ? null : _submit,
                        isLoading: isLoading,
                        variant: AppButtonVariant.elevated,
                      ),
                      SizedBox(height: AppSpacing.verticalMedium),
                      AppButton(
                        text: 'ليس لديك حساب؟ سجّل الآن',
                        onPressed:
                            isLoading ? null : () => context.go(AppRoutes.register),
                        variant: AppButtonVariant.text,
                      ),
                      AppButton(
                        text: 'إنشاء مؤسسة جديدة',
                        onPressed: isLoading
                            ? null
                            : () => context.go(AppRoutes.createOrgName),
                        variant: AppButtonVariant.text,
                      ),
                      AppButton(
                        text: 'نسيت كلمة المرور؟',
                        onPressed: isLoading
                            ? null
                            : () => context.go(AppRoutes.forgotPassword),
                        variant: AppButtonVariant.text,
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
