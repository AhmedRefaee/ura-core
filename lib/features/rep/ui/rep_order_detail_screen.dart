import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/design_system/widgets/feedback/app_snackbar.dart';
import '../../../shared/models/chat_message.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../../shared/widgets/invalid_order_view.dart';
import '../../../shared/widgets/order_status_stepper.dart';
import '../../../shared/widgets/order_status_timeline.dart';
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
              if (order.referenceCode != null)
                _ReferenceCodeBar(code: order.referenceCode!),
              OrderStatusStepper(order: order),
              const SizedBox(height: 16),
              OrderStatusTimeline(order: order, auditLog: state.auditLog),
              const SizedBox(height: 4),
              _InfoCard(order: order),
              const SizedBox(height: 16),
              _ItemsSection(
                order: order,
              ),
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
  const _CommunicationHistorySection({
    required this.history,
    required this.orderId,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 18,
              color: Colors.blueGrey,
            ),
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
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Items Section ────────────────────────────────────────────────────────────

class _ItemsSection extends StatelessWidget {
  final Order order;

  const _ItemsSection({
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    if (order.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'الأصناف',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...order.items.map(
          (item) => _ItemTile(
            item: item,
            direction: order.direction,
          ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final OrderItem item;
  final OrderDirection direction;

  const _ItemTile({
    required this.item,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final showWarning = !item.isCustom &&
        item.wasUnavailableAtCreation &&
        direction == OrderDirection.outbound;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          item.isCustom
              ? Icons.shopping_bag_outlined
              : Icons.inventory_outlined,
          color: item.isCustom ? Colors.orange : Colors.teal,
        ),
        title: Text(item.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('الكمية: ${formatQty(item.effectiveQuantity)}'),
            if (showWarning)
              Chip(
                avatar: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 16,
                ),
                label: const Text(
                  'غير متوفر',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
                backgroundColor: Colors.orange.withValues(alpha: 0.1),
                side: BorderSide(color: Colors.orange.withValues(alpha: 0.4)),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        trailing: item.isCustom ? null : _CheckStatusIcon(item.checkStatus),
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

  @override
  Widget build(BuildContext context) {
    final order = widget.state.order;
    final isActing = widget.state.isActing;
    final canProceed = true;
    final dir = order.direction;
    final status = order.status;

    if (status == OrderStatus.delivered &&
        (dir == OrderDirection.outbound ||
            dir == OrderDirection.inboundExternal)) {
      return _CompletedCard(
        icon: Icons.check_circle,
        message: 'تم تسليم هذا الطلب',
      );
    }

    if (status == OrderStatus.deliveredToStorage) {
      return _CompletedCard(
        icon: Icons.verified,
        message: 'تم الاستلام في المخزن',
      );
    }

    if (dir == OrderDirection.inboundRep && status == OrderStatus.onTheMove) {
      return _WaitingCard(
        icon: Icons.warehouse_outlined,
        message: 'في انتظار تأكيد أمين المخزن للاستلام',
      );
    }

    if (dir == OrderDirection.inboundRep && status == OrderStatus.delivered) {
      return _CompletedCard(
        icon: Icons.verified,
        message: 'تم الاستلام في المخزن',
      );
    }

    if (dir == OrderDirection.outbound &&
        order.involvesStorage &&
        status == OrderStatus.assigned) {
      return _WaitingCard(
        icon: Icons.warehouse_outlined,
        message: 'في انتظار أمين المخزن لإصدار البضاعة',
      );
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
  final VoidCallback onPressed;

  const _ActionButton({
    required this.isActing,
    required this.canAct,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: (isActing || !canAct) ? null : onPressed,
      icon: isActing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
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
            Text(
              message,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
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
            child: Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceCodeBar extends StatelessWidget {
  final String code;
  const _ReferenceCodeBar({required this.code});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          AppSnackbar.show(
            context,
            message: 'تم نسخ الرمز المرجعي',
            variant: AppSnackbarVariant.success,
            duration: const Duration(seconds: 2),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.tag, size: 16),
              const SizedBox(width: 8),
              Text(
                code,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              const Icon(Icons.content_copy_outlined, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
