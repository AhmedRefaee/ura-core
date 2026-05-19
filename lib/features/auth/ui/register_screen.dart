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
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _phoneFocusNode = FocusNode();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _phoneFocusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'رقم الواتساب مطلوب');
      return;
    }
    if (!RegExp(r'^05\d{8}$').hasMatch(phone)) {
      setState(() => _errorMessage = 'الرقم يجب أن يبدأ بـ 05 ويتكون من 10 أرقام');
      return;
    }
    setState(() => _errorMessage = null);
    context.read<AuthCubit>().signUp(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
          phone,
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
                      SizedBox(height: AppSpacing.verticalXXXLarge),
                      AppTextField(
                        controller: _nameController,
                        enabled: !isLoading,
                        label: 'الاسم الكامل',
                        focusNode: _nameFocusNode,
                      ),
                      SizedBox(height: AppSpacing.verticalLarge),
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
                      SizedBox(height: AppSpacing.verticalLarge),
                      AppTextField(
                        controller: _phoneController,
                        enabled: !isLoading,
                        keyboardType: TextInputType.phone,
                        label: 'رقم الواتساب *',
                        hintText: '05XXXXXXXX',
                        prefixIcon: Icons.phone,
                        focusNode: _phoneFocusNode,
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
