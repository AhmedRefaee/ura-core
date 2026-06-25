import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import 'onboarding_validators.dart';

/// Shown right after sign-up when the account is the first member of a
/// just-named organization. Collects personal details only — the org was
/// already named on [CreateOrgNameScreen] before sign-up, and the caller is
/// auto-approved as manager server-side.
class CreateOrgDetailsScreen extends StatefulWidget {
  const CreateOrgDetailsScreen({super.key});

  @override
  State<CreateOrgDetailsScreen> createState() =>
      _CreateOrgDetailsScreenState();
}

class _CreateOrgDetailsScreenState extends State<CreateOrgDetailsScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final fullName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (fullName.isEmpty) {
      setState(() => _errorMessage = 'الاسم الكامل مطلوب');
      return;
    }
    final phoneError = validateSaudiPhone(phone);
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return;
    }
    setState(() => _errorMessage = null);
    context.read<AuthCubit>().createOrganization(
          fullName: fullName,
          phone: phone,
        );
  }

  @override
  Widget build(BuildContext context) {
    final orgName = context.read<AuthCubit>().pendingOrgName ?? '';
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthError) setState(() => _errorMessage = state.message);
      },
      child: Scaffold(
        appBar: AppBar(),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: AppSpacing.screenPaddingInsets,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: BlocBuilder<AuthCubit, AuthState>(
                  builder: (context, state) {
                    final isLoading = state is AuthLoading;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('بياناتك كأول عضو',
                            style: AppTextStyles.headlineMedium,
                            textAlign: TextAlign.center),
                        SizedBox(height: AppSpacing.verticalSmall),
                        Text('مؤسسة "$orgName" — ستُعتمد تلقائياً كمدير لها',
                            style: AppTextStyles.bodySmall,
                            textAlign: TextAlign.center),
                        SizedBox(height: AppSpacing.verticalXXLarge),
                        AppTextField(
                          controller: _nameController,
                          enabled: !isLoading,
                          label: 'الاسم الكامل',
                        ),
                        SizedBox(height: AppSpacing.verticalLarge),
                        AppTextField(
                          controller: _phoneController,
                          enabled: !isLoading,
                          keyboardType: TextInputType.phone,
                          label: 'رقم الواتساب *',
                          hintText: '05XXXXXXXX',
                          prefixIcon: Icons.phone,
                        ),
                        if (_errorMessage != null) ...[
                          SizedBox(height: AppSpacing.verticalMedium),
                          Text(_errorMessage!,
                              style: TextStyle(color: AppColors.error),
                              textAlign: TextAlign.center),
                        ],
                        SizedBox(height: AppSpacing.verticalXXLarge),
                        AppButton(
                          text: 'إنشاء',
                          onPressed: isLoading ? null : _submit,
                          isLoading: isLoading,
                          variant: AppButtonVariant.elevated,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
