import 'package:flutter/material.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../manager/data/manager_repository.dart';

/// Settings entry shown only to managers. Tapping it opens a modal bottom
/// sheet to edit optional company info — nothing here is required.
class CompanyInfoCard extends StatelessWidget {
  const CompanyInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const Icon(Icons.apartment_outlined),
        title: const Text('بيانات الشركة'),
        subtitle: const Text('اختيارية — عنوان، بريد، رقم تواصل، ووصف'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => const _CompanyInfoSheet(),
        ),
      ),
    );
  }
}

class _CompanyInfoSheet extends StatefulWidget {
  const _CompanyInfoSheet();

  @override
  State<_CompanyInfoSheet> createState() => _CompanyInfoSheetState();
}

class _CompanyInfoSheetState extends State<_CompanyInfoSheet> {
  final _repo = sl<ManagerRepository>();
  final _descriptionController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _orgId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final result = await _repo.fetchCompanyInfo();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result case AppSuccess(:final data)) {
        _orgId = data.id;
        _descriptionController.text = data.description ?? '';
        _addressController.text = data.address ?? '';
        _emailController.text = data.contactEmail ?? '';
        _phoneController.text = data.contactPhone ?? '';
      }
    });
  }

  Future<void> _save() async {
    final orgId = _orgId;
    if (orgId == null) return;
    setState(() => _saving = true);
    final result = await _repo.updateCompanyInfo(
      orgId: orgId,
      description: _blankToNull(_descriptionController.text),
      address: _blankToNull(_addressController.text),
      contactEmail: _blankToNull(_emailController.text),
      contactPhone: _blankToNull(_phoneController.text),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is AppSuccess) {
      Navigator.of(context).pop();
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        result is AppSuccess ? 'تم حفظ بيانات الشركة' : 'فشل حفظ البيانات',
      ),
    ));
  }

  String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).disabledColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('بيانات الشركة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              'اختيارية — يمكنك تركها فارغة',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).disabledColor),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(
                  child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else ...[
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'وصف الشركة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'العنوان',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'البريد الإلكتروني للتواصل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم التواصل',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
