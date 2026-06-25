import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../router/app_router.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
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
    context.read<AuthCubit>().signUp(
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
                        'إنشاء حساب جديد',
                        style: AppTextStyles.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: AppSpacing.verticalSmall),
                      Text(
                        'بعد إنشاء الحساب ستختار إنشاء مؤسسة جديدة أو الانضمام لمؤسسة قائمة',
                        style: AppTextStyles.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: AppSpacing.verticalXXLarge),
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
                        text: 'تسجيل',
                        onPressed: isLoading ? null : _submit,
                        isLoading: isLoading,
                        variant: AppButtonVariant.elevated,
                      ),
                      SizedBox(height: AppSpacing.verticalMedium),
                      AppButton(
                        text: 'لديك حساب بالفعل؟ سجّل دخولك',
                        onPressed:
                            isLoading ? null : () => context.go(AppRoutes.login),
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
