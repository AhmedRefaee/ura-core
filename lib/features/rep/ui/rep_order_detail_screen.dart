import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/order_status_theme.dart';
import '../../../shared/widgets/invalid_order_view.dart';
import '../../../shared/widgets/order_status_timeline.dart';
import '../../../shared/widgets/receipt_viewer_screen.dart';
import '../../chat/ui/chat_thread_picker_sheet.dart';
import '../../chat/ui/chat_thread_screen.dart';
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

        // 0-item guard: refuse to render any action UI for a corrupt order.
        if (order.items.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(order.entity?.name ?? 'تفاصيل الطلب')),
            body: const InvalidOrderView(),
          );
        }

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
          floatingActionButton: _ChatBridgeButton(order: order),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusStepper(order.status, order.direction, order.involvesStorage),
              const SizedBox(height: 16),
              OrderStatusTimeline(order: order, auditLog: state.auditLog),
              const SizedBox(height: 4),
              _InfoCard(order: order),
              const SizedBox(height: 16),
              _ItemsSection(order: order, receipts: state.receipts, isActing: state.isActing),
              const SizedBox(height: 24),
              _ActionSection(state: state),
              const SizedBox(height: 24),
              _CommunicationHistorySection(
                history: state.communicationHistory,
                orderId: order.id,
              ),
              const SizedBox(height: 80), // FAB clearance
            ],
          ),
        );
      },
    );
  }
}

// ─── Chat Bridge FAB ──────────────────────────────────────────────────────────

class _ChatBridgeButton extends StatefulWidget {
  final Order order;
  const _ChatBridgeButton({required this.order});

  @override
  State<_ChatBridgeButton> createState() => _ChatBridgeButtonState();
}

class _ChatBridgeButtonState extends State<_ChatBridgeButton> {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _openThreadPicker,
      icon: const Icon(Icons.add_comment_outlined),
      label: const Text('إرسال ملاحظة'),
      backgroundColor: Colors.orange,
      foregroundColor: Colors.white,
    );
  }

  void _openThreadPicker() {
    final creator = widget.order.creator;
    if (creator == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر تحديد المسؤول عن الطلب')),
      );
      return;
    }

    final entityName = widget.order.entity?.name ?? 'طلب';

    showModalBottomSheet<({String threadId, String threadTitle})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChatThreadPickerSheet(
        verifierId: creator.id,
        verifierName: creator.fullName,
      ),
    ).then((result) {
      if (result == null || !mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatThreadScreen(
            threadId: result.threadId,
            threadTitle: result.threadTitle,
            initialText: '@$entityName ',
            isUrgentEntry: true,
            mentionedOrderId: widget.order.id,
            mentionedOrderTitle: entityName,
          ),
        ),
      ).then((_) {
        if (mounted) context.read<RepOrderDetailCubit>().load();
      });
    });
  }
}

// ─── Communication History Section ───────────────────────────────────────────

class _CommunicationHistorySection extends StatelessWidget {
  final List<ChatMessage> history;
  final String orderId;
  const _CommunicationHistorySection({required this.history, required this.orderId});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.blueGrey),
            const SizedBox(width: 8),
            Text(
              'سجل التواصل (${history.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...history.map((msg) => _HistoryTile(msg: msg)),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final ChatMessage msg;
  const _HistoryTile({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: msg.isUrgent
            ? Icon(Icons.priority_high, color: Colors.orange.shade700)
            : const Icon(Icons.chat_bubble_outline, color: Colors.blueGrey),
        title: Text(
          msg.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text(
          '${msg.senderName} · ${msg.threadTitle ?? ''} · ${_fmt(msg.createdAt)}',
          style: const TextStyle(fontSize: 11),
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatThreadScreen(
              threadId: msg.threadId,
              threadTitle: msg.threadTitle ?? '',
            ),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} س';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Status Stepper ───────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  final OrderStatus status;
  final OrderDirection direction;
  final bool involvesStorage;
  const _StatusStepper(this.status, this.direction, this.involvesStorage);

  List<(OrderStatus, String)> get _steps {
    switch (direction) {
      case OrderDirection.inboundRep:
        return [
          (OrderStatus.assigned, 'معين'),
          (OrderStatus.pickedUp, 'تم الاستلام'),
          (OrderStatus.onTheMove, 'في الطريق'),
          (OrderStatus.delivered, 'مُسلَّم للمخزن'),
        ];
      case OrderDirection.outbound when involvesStorage:
        return [
          (OrderStatus.assigned, 'معين'),
          (OrderStatus.pickedUp, 'أُرسل من المخزن'),
          (OrderStatus.onTheMove, 'في الطريق'),
          (OrderStatus.delivered, 'تم التسليم'),
        ];
      default:
        return [
          (OrderStatus.assigned, 'معين'),
          (OrderStatus.pickedUp, 'تم الاستلام'),
          (OrderStatus.onTheMove, 'في الطريق'),
          (OrderStatus.delivered, 'تم التسليم'),
        ];
    }
  }

  int get _currentIndex =>
      _steps.indexWhere((s) => s.$1 == status).clamp(0, _steps.length - 1);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: List.generate(_steps.length * 2 - 1, (i) {
            if (i.isOdd) {
              final stepIndex = i ~/ 2;
              final done = stepIndex < _currentIndex;
              return Expanded(
                child: Container(
                  height: 2,
                  color: done ? _steps[stepIndex].$1.color : Colors.grey.shade300,
                ),
              );
            }
            final stepIndex = i ~/ 2;
            final done = stepIndex <= _currentIndex;
            final current = stepIndex == _currentIndex;
            final stepColor = _steps[stepIndex].$1.color;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done ? stepColor : Colors.grey.shade300,
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
                    color: done ? stepColor : Colors.grey,
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

    final canUpload = order.status == OrderStatus.assigned ||
        order.status == OrderStatus.pickedUp ||
        order.status == OrderStatus.onTheMove;

    final isFinished = order.status == OrderStatus.delivered ||
        order.status == OrderStatus.deliveredToStorage;

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
              canUpload: canUpload,
              isFinished: isFinished,
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
  final bool isFinished;

  const _ItemTile({
    required this.item,
    required this.receiptUrl,
    required this.isActing,
    required this.canUpload,
    this.isFinished = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasReceipt = receiptUrl != null;
    final showWarning = !item.isCustom && item.wasUnavailableAtCreation;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          item.isCustom ? Icons.shopping_bag_outlined : Icons.inventory_outlined,
          color: item.isCustom ? Colors.orange : Colors.teal,
        ),
        title: Text(item.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الكمية: ${item.effectiveQuantity}'),
            if (showWarning)
              Chip(
                avatar: const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 16),
                label: const Text(
                  'غير متوفر',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                side: BorderSide(
                    color: Colors.orange.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
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
          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (hasReceipt) {
      return IconButton(
        icon: const Icon(Icons.receipt_long, color: Colors.green),
        tooltip: 'عرض الإيصال',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReceiptViewerScreen(url: receiptUrl!)),
        ),
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

// ─── Action Section ───────────────────────────────────────────────────────────

class _ActionSection extends StatefulWidget {
  final RepOrderDetailLoaded state;
  const _ActionSection({required this.state});

  @override
  State<_ActionSection> createState() => _ActionSectionState();
}

class _ActionSectionState extends State<_ActionSection> {
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String? get _notes {
    final t = _notesController.text.trim();
    return t.isEmpty ? null : t;
  }

  String? _getWarningMessage(RepOrderDetailLoaded state) {
    if (!state.allCustomItemsHaveReceipts) {
      return 'يجب رفع إيصال لجميع الأصناف المخصصة';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.state.order;
    final isActing = widget.state.isActing;
    final canProceed = true;
    final dir = order.direction;
    final status = order.status;

    if (status == OrderStatus.delivered &&
        (dir == OrderDirection.outbound || dir == OrderDirection.inboundExternal)) {
      return _CompletedCard(icon: Icons.check_circle, message: 'تم تسليم هذا الطلب');
    }

    if (status == OrderStatus.deliveredToStorage) {
      return _CompletedCard(icon: Icons.verified, message: 'تم الاستلام في المخزن');
    }

    if (dir == OrderDirection.inboundRep && status == OrderStatus.onTheMove) {
      return _WaitingCard(
          icon: Icons.warehouse_outlined,
          message: 'في انتظار تأكيد أمين المخزن للاستلام');
    }

    if (dir == OrderDirection.inboundRep && status == OrderStatus.delivered) {
      return _CompletedCard(icon: Icons.verified, message: 'تم الاستلام في المخزن');
    }

    if (dir == OrderDirection.outbound &&
        order.involvesStorage &&
        status == OrderStatus.assigned) {
      return _WaitingCard(
          icon: Icons.warehouse_outlined,
          message: 'في انتظار أمين المخزن لإصدار البضاعة');
    }

    Widget? actionButton;

    if (status == OrderStatus.assigned &&
        (dir == OrderDirection.inboundRep ||
            (dir == OrderDirection.outbound && !order.involvesStorage))) {
      actionButton = _ActionButton(
        isActing: isActing,
        canAct: canProceed,
        icon: Icons.inventory_2_outlined,
        label: 'تأكيد الاستلام',
        warningMessage: _getWarningMessage(widget.state),
        onPressed: () =>
            context.read<RepOrderDetailCubit>().markPickedUp(notes: _notes),
      );
    }

    if (status == OrderStatus.pickedUp && dir == OrderDirection.outbound) {
      actionButton = _ActionButton(
        isActing: isActing,
        canAct: canProceed,
        icon: Icons.local_shipping_outlined,
        label: 'ابدأ التنقل',
        warningMessage: _getWarningMessage(widget.state),
        onPressed: () =>
            context.read<RepOrderDetailCubit>().startMove(notes: _notes),
      );
    }

    if (status == OrderStatus.pickedUp && dir == OrderDirection.inboundRep) {
      actionButton = _ActionButton(
        isActing: isActing,
        canAct: canProceed,
        icon: Icons.local_shipping_outlined,
        label: 'ابدأ التنقل نحو المخزن',
        warningMessage: _getWarningMessage(widget.state),
        onPressed: () =>
            context.read<RepOrderDetailCubit>().startMove(notes: _notes),
      );
    }

    if (status == OrderStatus.onTheMove && dir == OrderDirection.outbound) {
      actionButton = _ActionButton(
        isActing: isActing,
        canAct: canProceed,
        icon: Icons.check_circle_outline,
        label: 'تم التسليم للعميل',
        warningMessage: _getWarningMessage(widget.state),
        onPressed: () =>
            context.read<RepOrderDetailCubit>().markDelivered(notes: _notes),
      );
    }

    if (actionButton == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'ملاحظات (اختياري)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.notes),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),
        actionButton,
      ],
    );
  }
}

// ─── Shared Action Widgets ────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final bool isActing;
  final bool canAct;
  final IconData icon;
  final String label;
  final String? warningMessage;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.isActing,
    required this.canAct,
    required this.icon,
    required this.label,
    this.warningMessage,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!canAct && warningMessage != null && !isActing)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border.all(color: Colors.orange),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(warningMessage!,
                      style: const TextStyle(color: Colors.orange, fontSize: 13)),
                ),
              ],
            ),
          ),
        FilledButton.icon(
          onPressed: (isActing || !canAct) ? null : onPressed,
          icon: isActing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ],
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _CompletedCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.green),
            const SizedBox(width: 8),
            Text(message,
                style: const TextStyle(
                    color: Colors.green, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _WaitingCard({required this.icon, required this.message});

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

