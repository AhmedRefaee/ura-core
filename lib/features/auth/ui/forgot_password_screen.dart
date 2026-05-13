import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await context.read<AuthCubit>().sendPasswordResetEmail(email);
      if (mounted) setState(() => _emailSent = true);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
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
      child: Scaffold(
        appBar: AppBar(title: const Text('نسيت كلمة المرور؟')),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: AppSpacing.screenPaddingInsets,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: _emailSent ? _SuccessView(email: _emailController.text.trim()) : _FormView(
                  emailController: _emailController,
                  isLoading: _isLoading,
                  errorMessage: _errorMessage,
                  onSubmit: _submit,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final TextEditingController emailController;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onSubmit;

  const _FormView({
    required this.emailController,
    required this.isLoading,
    required this.errorMessage,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'إعادة تعيين كلمة المرور',
          style: AppTextStyles.headlineSmall,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.verticalMedium),
        Text(
          'أدخل بريدك الإلكتروني وسنرسل لك رابط إعادة التعيين',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.verticalXXXLarge),
        AppTextField(
          controller: emailController,
          enabled: !isLoading,
          keyboardType: TextInputType.emailAddress,
          label: 'البريد الإلكتروني',
        ),
        if (errorMessage != null) ...[
          SizedBox(height: AppSpacing.verticalMedium),
          Text(
            errorMessage!,
            style: TextStyle(color: AppColors.error),
            textAlign: TextAlign.center,
          ),
        ],
        SizedBox(height: AppSpacing.verticalXXLarge),
        AppButton(
          text: 'إرسال رابط إعادة التعيين',
          onPressed: isLoading ? null : onSubmit,
          isLoading: isLoading,
          variant: AppButtonVariant.elevated,
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String email;
  const _SuccessView({required this.email});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined,
            size: 64, color: AppColors.success),
        SizedBox(height: AppSpacing.verticalXXLarge),
        Text(
          'تم الإرسال!',
          style: AppTextStyles.headlineSmall,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.verticalMedium),
        Text(
          'تم إرسال رابط إعادة تعيين كلمة المرور إلى\n$email',
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.verticalSmall),
        Text(
          'افتح بريدك الإلكتروني واضغط على الرابط للمتابعة',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSpacing.verticalXXXLarge),
        AppButton(
          text: 'العودة لتسجيل الدخول',
          onPressed: () => Navigator.of(context).pop(),
          variant: AppButtonVariant.outlined,
        ),
      ],
    );
  }
}
