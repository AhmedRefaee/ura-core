import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../logic/auth_cubit.dart';
import '../../../router/app_router.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';

/// Pre-auth step: name the organization before creating an account. The
/// caller becomes the org's first (auto-approved) member after sign-up.
class CreateOrgNameScreen extends StatefulWidget {
  const CreateOrgNameScreen({super.key});

  @override
  State<CreateOrgNameScreen> createState() => _CreateOrgNameScreenState();
}

class _CreateOrgNameScreenState extends State<CreateOrgNameScreen> {
  final _orgController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _orgController.dispose();
    super.dispose();
  }

  void _submit() {
    final orgName = _orgController.text.trim();
    if (orgName.isEmpty) {
      setState(() => _errorMessage = 'اسم المؤسسة مطلوب');
      return;
    }
    context.read<AuthCubit>().setPendingOrgName(orgName);
    context.go(AppRoutes.register);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(AppRoutes.login)),
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
                  Text('إنشاء مؤسسة جديدة',
                      style: AppTextStyles.headlineMedium,
                      textAlign: TextAlign.center),
                  SizedBox(height: AppSpacing.verticalSmall),
                  Text('ستكون أول عضو فيها، وسيتم اعتمادك تلقائياً كمدير',
                      style: AppTextStyles.bodySmall,
                      textAlign: TextAlign.center),
                  SizedBox(height: AppSpacing.verticalXXLarge),
                  AppTextField(
                    controller: _orgController,
                    label: 'اسم المؤسسة',
                  ),
                  if (_errorMessage != null) ...[
                    SizedBox(height: AppSpacing.verticalMedium),
                    Text(_errorMessage!,
                        style: TextStyle(color: AppColors.error),
                        textAlign: TextAlign.center),
                  ],
                  SizedBox(height: AppSpacing.verticalXXLarge),
                  AppButton(
                    text: 'متابعة',
                    onPressed: _submit,
                    variant: AppButtonVariant.elevated,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
