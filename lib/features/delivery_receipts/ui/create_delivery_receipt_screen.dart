import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../../core/di/injection.dart';
import '../../../shared/models/entity.dart';
import '../../../shared/models/project.dart';
import '../../../shared/models/project_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../auth/logic/auth_cubit.dart';
import '../../projects/logic/boq_excel.dart';
import '../../auth/logic/auth_state.dart';
import '../logic/create_delivery_receipt_cubit.dart';

/// Opens the سند flow. Resolves to true once a سند was actually filed.
Future<bool> openCreateDeliveryReceipt(
  BuildContext context, {
  DeliveryReceiptLaunch launch = const DeliveryReceiptLaunch(),
}) async {
  final filed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => BlocProvider(
        create: (_) => sl<CreateDeliveryReceiptCubit>(param1: launch)..init(),
        child: const CreateDeliveryReceiptScreen(),
      ),
    ),
  );
  return filed ?? false;
}

class CreateDeliveryReceiptScreen extends StatelessWidget {
  const CreateDeliveryReceiptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CreateDeliveryReceiptCubit, CreateDeliveryReceiptState>(
      builder: (context, state) {
        if (state.receiptId != null && state.pdfBytes != null) {
          return _FiledView(state: state);
        }
        return Scaffold(
          appBar: AppBar(title: const Text('سند استلام جديد')),
          body: _Form(state: state),
        );
      },
    );
  }
}

class _FiledView extends StatelessWidget {
  final CreateDeliveryReceiptState state;
  const _FiledView({required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تم إنشاء السند'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تم'),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => state.pdfBytes!,
        pdfFileName: 'سند_استلام_${state.project?.name ?? ''}.pdf',
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }
}

class _Form extends StatefulWidget {
  final CreateDeliveryReceiptState state;
  const _Form({required this.state});

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final auth = context.read<AuthCubit>().state;
    final repName = auth is AuthAuthenticated ? auth.profile.fullName : '';
    context.read<CreateDeliveryReceiptCubit>().submit(repName: repName, notes: _notes.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final cubit = context.read<CreateDeliveryReceiptCubit>();
    final theme = Theme.of(context);

    if (state.loading && state.entities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Step(
                number: 1,
                title: 'الجهة',
                child: DropdownMenu<Entity>(
                  key: ValueKey('entity-${state.entity?.id}'),
                  initialSelection: state.entity,
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  hintText: 'اختر الجهة',
                  dropdownMenuEntries: [
                    for (final e in state.entities) DropdownMenuEntry(value: e, label: e.name),
                  ],
                  onSelected: (e) {
                    if (e != null && e.id != state.entity?.id) cubit.selectEntity(e);
                  },
                ),
              ),
              if (state.entity != null)
                _Step(
                  number: 2,
                  title: 'المشروع',
                  child: state.loading && state.projects.isEmpty
                      ? const LinearProgressIndicator()
                      : state.projects.isEmpty
                          ? Text(
                              'لا توجد مشاريع لهذه الجهة. يضيفها المشرف أو المدير من شاشة الجهات.',
                              style: TextStyle(color: theme.colorScheme.error),
                            )
                          : DropdownMenu<Project>(
                              key: ValueKey('project-${state.entity?.id}-${state.project?.id}'),
                              initialSelection: state.project,
                              expandedInsets: EdgeInsets.zero,
                              hintText: 'اختر المشروع',
                              dropdownMenuEntries: [
                                for (final p in state.projects) DropdownMenuEntry(value: p, label: p.name),
                              ],
                              onSelected: (p) {
                                if (p != null && p.id != state.project?.id) cubit.selectProject(p);
                              },
                            ),
                ),
              if (state.project != null)
                _Step(
                  number: 3,
                  title: 'البنود والكميات المسلّمة',
                  child: state.loading
                      ? const LinearProgressIndicator()
                      : state.items.isEmpty
                          ? const Text('لا توجد بنود في هذا المشروع بعد.')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final category in groupByCategory(state.items)) ...[
                                  if (category.name.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                                      child: Text(category.name, style: theme.textTheme.labelLarge),
                                    ),
                                  for (final item in category.items)
                                    _ItemRow(
                                      key: ValueKey(item.id),
                                      item: item,
                                      invalid: state.invalid.contains(item.id),
                                      onChanged: (v) => cubit.setQuantityText(item.id, v),
                                    ),
                                ],
                              ],
                            ),
                ),
              if (state.project != null && state.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: state.canSubmit ? _submit : null,
                icon: state.submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(state.submitting ? 'جارٍ إنشاء السند...' : 'إنشاء السند'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final Widget child;
  const _Step({required this.number, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(radius: 12, child: Text('$number', style: const TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ProjectItem item;
  final bool invalid;
  final ValueChanged<String> onChanged;
  const _ItemRow({super.key, required this.item, required this.invalid, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.itemName, style: theme.textTheme.bodyLarge),
                Text(
                  [
                    if (item.description != null && item.description!.isNotEmpty) item.description!,
                    'العرض: ${formatQty(item.quantity)} ${item.unit}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: TextField(
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0',
                suffixText: item.unit,
                errorText: invalid ? 'رقم غير صحيح' : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
