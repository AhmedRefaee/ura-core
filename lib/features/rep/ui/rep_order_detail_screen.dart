import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../logic/rep_order_detail_cubit.dart';

class RepOrderDetailScreen extends StatelessWidget {
  const RepOrderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<RepOrderDetailCubit, RepOrderDetailState>(
      listener: (context, state) {
        if (state is RepOrderDetailError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          // Reload after showing error so screen recovers
          context.read<RepOrderDetailCubit>().load();
        }
      },
      builder: (context, state) {
        if (state is RepOrderDetailLoading || state is RepOrderDetailInitial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! RepOrderDetailLoaded) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل الطلب')),
            body: Center(
              child: FilledButton(
                onPressed: () => context.read<RepOrderDetailCubit>().load(),
                child: const Text('إعادة المحاولة'),
              ),
            ),
          );
        }

        final order = state.order;
        return Scaffold(
          appBar: AppBar(
            title: Text(order.entity?.name ?? 'تفاصيل الطلب'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => context.read<RepOrderDetailCubit>().load(),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusStepper(order.status),
              const SizedBox(height: 20),
              _InfoCard(order: order),
              const SizedBox(height: 16),
              _ItemsSection(
                order: order,
                receipts: state.receipts,
                isActing: state.isActing,
              ),
              const SizedBox(height: 24),
              _ActionButtons(state: state),
            ],
          ),
        );
      },
    );
  }
}

// ─── Status Stepper ───────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  final OrderStatus status;
  const _StatusStepper(this.status);

  static const _steps = [
    (OrderStatus.assigned, 'معين'),
    (OrderStatus.pickedUp, 'تم الاستلام'),
    (OrderStatus.onTheMove, 'في الطريق'),
    (OrderStatus.delivered, 'مُسلَّم'),
  ];

  int get _currentIndex =>
      _steps.indexWhere((s) => s.$1 == status).clamp(0, _steps.length - 1);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: List.generate(_steps.length * 2 - 1, (i) {
            if (i.isOdd) {
              // connector line
              final stepIndex = i ~/ 2;
              final done = stepIndex < _currentIndex;
              return Expanded(
                child: Container(
                  height: 2,
                  color: done ? colorScheme.primary : Colors.grey.shade300,
                ),
              );
            }
            final stepIndex = i ~/ 2;
            final done = stepIndex <= _currentIndex;
            final current = stepIndex == _currentIndex;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done ? colorScheme.primary : Colors.grey.shade300,
                  child: Icon(
                    done ? Icons.check : Icons.circle,
                    size: 14,
                    color: done ? Colors.white : Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _steps[stepIndex].$2,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: current ? FontWeight.bold : FontWeight.normal,
                    color: done ? colorScheme.primary : Colors.grey,
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final Order order;
  const _InfoCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InfoRow(Icons.business, 'الجهة', order.entity?.name ?? '—'),
            _InfoRow(Icons.swap_horiz, 'الاتجاه', order.directionLabel),
            if (order.notes != null && order.notes!.isNotEmpty)
              _InfoRow(Icons.notes, 'ملاحظات', order.notes!),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Items Section ────────────────────────────────────────────────────────────

class _ItemsSection extends StatelessWidget {
  final Order order;
  final Map<String, String> receipts;
  final bool isActing;

  const _ItemsSection({
    required this.order,
    required this.receipts,
    required this.isActing,
  });

  @override
  Widget build(BuildContext context) {
    if (order.items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('الأصناف',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        ...order.items.map((item) => _ItemTile(
              item: item,
              receiptUrl: receipts[item.id],
              isActing: isActing,
              canUpload: order.status == OrderStatus.pickedUp ||
                  order.status == OrderStatus.onTheMove,
            )),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final OrderItem item;
  final String? receiptUrl;
  final bool isActing;
  final bool canUpload;

  const _ItemTile({
    required this.item,
    required this.receiptUrl,
    required this.isActing,
    required this.canUpload,
  });

  @override
  Widget build(BuildContext context) {
    final hasReceipt = receiptUrl != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          item.isCustom ? Icons.shopping_bag_outlined : Icons.inventory_outlined,
          color: item.isCustom ? Colors.orange : Colors.teal,
        ),
        title: Text(item.displayName),
        subtitle: Text('الكمية: ${item.quantity}'),
        trailing: item.isCustom
            ? _ReceiptButton(
                hasReceipt: hasReceipt,
                receiptUrl: receiptUrl,
                isActing: isActing,
                canUpload: canUpload,
                onUpload: () => _pickAndUpload(context),
              )
            : _CheckStatusIcon(item.checkStatus),
      ),
    );
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    final picker = ImagePicker();
    final source = await _pickSource(context);
    if (source == null) return;

    final picked = await picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;
    if (!context.mounted) return;

    context.read<RepOrderDetailCubit>().uploadReceipt(
          orderItemId: item.id,
          imageFile: File(picked.path),
        );
  }

  Future<ImageSource?> _pickSource(BuildContext context) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('التقاط صورة'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('اختيار من المعرض'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptButton extends StatelessWidget {
  final bool hasReceipt;
  final String? receiptUrl;
  final bool isActing;
  final bool canUpload;
  final VoidCallback onUpload;

  const _ReceiptButton({
    required this.hasReceipt,
    required this.receiptUrl,
    required this.isActing,
    required this.canUpload,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    if (isActing) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (hasReceipt) {
      return IconButton(
        icon: const Icon(Icons.receipt_long, color: Colors.green),
        tooltip: 'عرض الإيصال',
        onPressed: () => _viewReceipt(context),
      );
    }
    if (!canUpload) {
      return const Icon(Icons.receipt_long_outlined, color: Colors.grey);
    }
    return IconButton(
      icon: const Icon(Icons.upload_file, color: Colors.orange),
      tooltip: 'رفع إيصال',
      onPressed: onUpload,
    );
  }

  void _viewReceipt(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ReceiptViewerScreen(url: receiptUrl!),
      ),
    );
  }
}

class _CheckStatusIcon extends StatelessWidget {
  final ItemCheckStatus status;
  const _CheckStatusIcon(this.status);

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ItemCheckStatus.checked:
        return const Icon(Icons.check_circle, color: Colors.green);
      case ItemCheckStatus.rejected:
        return const Icon(Icons.cancel, color: Colors.red);
      case ItemCheckStatus.pending:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    }
  }
}

// ─── Action Buttons ───────────────────────────────────────────────────────────

class _ActionButtons extends StatelessWidget {
  final RepOrderDetailLoaded state;
  const _ActionButtons({required this.state});

  @override
  Widget build(BuildContext context) {
    final order = state.order;
    final isActing = state.isActing;

    if (order.status == OrderStatus.delivered) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('تم تسليم هذا الطلب',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    if (order.status == OrderStatus.assigned) {
      return _DisabledActionCard(
        icon: Icons.local_shipping_outlined,
        message: 'في انتظار موافقة أمين المخزن لبدء التنقل',
      );
    }

    if (order.status == OrderStatus.pickedUp) {
      return FilledButton.icon(
        onPressed: isActing
            ? null
            : () => context.read<RepOrderDetailCubit>().startMove(),
        icon: isActing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.local_shipping),
        label: const Text('ابدأ التنقل'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
      );
    }

    if (order.status == OrderStatus.onTheMove) {
      final canDeliver = state.allCustomItemsHaveReceipts;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!canDeliver)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'يجب رفع إيصال لكل الأصناف المخصصة قبل التسليم',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          FilledButton.icon(
            onPressed: (isActing || !canDeliver)
                ? null
                : () => context.read<RepOrderDetailCubit>().markDelivered(),
            icon: isActing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('تم التسليم'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _DisabledActionCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _DisabledActionCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Receipt Viewer ───────────────────────────────────────────────────────────

class _ReceiptViewerScreen extends StatelessWidget {
  final String url;
  const _ReceiptViewerScreen({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('الإيصال', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(
            url,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : const CircularProgressIndicator(color: Colors.white),
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image,
                color: Colors.white, size: 64),
          ),
        ),
      ),
    );
  }
}
