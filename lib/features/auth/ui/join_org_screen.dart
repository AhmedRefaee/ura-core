import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../logic/auth_cubit.dart';
import '../logic/auth_state.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/design_system/theme/theme.dart';
import '../../../core/design_system/widgets/widgets.dart';
import 'onboarding_validators.dart';

/// Join an existing organization two ways — public directory or join code.
/// Both paths leave the user pending manager approval.
class JoinOrgScreen extends StatefulWidget {
  const JoinOrgScreen({super.key});

  @override
  State<JoinOrgScreen> createState() => _JoinOrgScreenState();
}

class _JoinOrgScreenState extends State<JoinOrgScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _tabs.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Validates the shared name/phone fields. Returns the values or null (and
  /// sets an error message) when invalid.
  ({String fullName, String phone})? _sharedFields() {
    final fullName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (fullName.isEmpty) {
      setState(() => _errorMessage = 'الاسم الكامل مطلوب');
      return null;
    }
    final phoneError = validateSaudiPhone(phone);
    if (phoneError != null) {
      setState(() => _errorMessage = phoneError);
      return null;
    }
    setState(() => _errorMessage = null);
    return (fullName: fullName, phone: phone);
  }

  void _joinByCode() {
    final shared = _sharedFields();
    if (shared == null) return;
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _errorMessage = 'رمز الانضمام مطلوب');
      return;
    }
    context.read<AuthCubit>().joinByCode(
        code: code, fullName: shared.fullName, phone: shared.phone);
  }

  void _joinById(String orgId) {
    final shared = _sharedFields();
    if (shared == null) return;
    context.read<AuthCubit>().joinById(
        orgId: orgId, fullName: shared.fullName, phone: shared.phone);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        if (state is AuthError) setState(() => _errorMessage = state.message);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(
              onPressed: () => context.read<AuthCubit>().signOut()),
          title: const Text('الانضمام إلى مؤسسة'),
          bottom: TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'الدليل'),
              Tab(text: 'رمز'),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: AppSpacing.screenPaddingInsets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(controller: _nameController, label: 'الاسم الكامل'),
                    SizedBox(height: AppSpacing.verticalLarge),
                    AppTextField(
                      controller: _phoneController,
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
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _DirectoryTab(onPick: _joinById),
                    _CodeTab(controller: _codeController, onSubmit: _joinByCode),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeTab extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  const _CodeTab({required this.controller, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthCubit>().state is AuthLoading;
    return SingleChildScrollView(
      padding: AppSpacing.screenPaddingInsets,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('أدخل رمز الانضمام الذي حصلت عليه من مدير المؤسسة',
              style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
          SizedBox(height: AppSpacing.verticalLarge),
          AppTextField(
            controller: controller,
            enabled: !isLoading,
            label: 'رمز الانضمام',
            textCapitalization: TextCapitalization.characters,
          ),
          SizedBox(height: AppSpacing.verticalXXLarge),
          AppButton(
            text: 'انضمام',
            onPressed: isLoading ? null : onSubmit,
            isLoading: isLoading,
            variant: AppButtonVariant.elevated,
          ),
        ],
      ),
    );
  }
}

class _DirectoryTab extends StatefulWidget {
  final void Function(String orgId) onPick;
  const _DirectoryTab({required this.onPick});

  @override
  State<_DirectoryTab> createState() => _DirectoryTabState();
}

class _DirectoryTabState extends State<_DirectoryTab> {
  final _searchController = TextEditingController();
  List<({String id, String name})> _orgs = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final result =
        await context.read<AuthCubit>().listDiscoverableOrgs(_searchController.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result is AppSuccess<List<({String id, String name})>>) {
        _orgs = result.data;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: AppSpacing.screenPaddingInsets,
          child: AppTextField(
            controller: _searchController,
            label: 'ابحث عن مؤسسة',
            prefixIcon: Icons.search,
            onChanged: (_) => _search(),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _orgs.isEmpty
                  ? Center(
                      child: Text('لا توجد مؤسسات متاحة',
                          style: AppTextStyles.bodyMedium))
                  : ListView.builder(
                      itemCount: _orgs.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(_orgs[i].name),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => widget.onPick(_orgs[i].id),
                      ),
                    ),
        ),
      ],
    );
  }
}
