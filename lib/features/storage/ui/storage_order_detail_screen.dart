import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/order_item.dart';
import '../../inventory/ui/inventory_form_screen.dart';
import '../../../shared/widgets/invalid_order_view.dart';
import '../../../shared/widgets/order_status_timeline.dart';
import '../../chat/ui/chat_thread_picker_sheet.dart';
import '../../chat/ui/chat_thread_screen.dart';
import '../logic/storage_order_detail_cubit.dart';

class StorageOrderDetailScreen extends StatelessWidget {
  const StorageOrderDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<StorageOrderDetailCubit, StorageOrderDetailState>(
      listener: (context, state) {
        if (state is StorageOrderDetailSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else if (state is StorageOrderDetailError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        if (state is StorageOrderDetailInitial ||
            state is StorageOrderDetailLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! StorageOrderDetailLoaded) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل الطلب')),
            body: Center(
              child: FilledButton(
                onPressed: () =>
                    context.read<StorageOrderDetailCubit>().load(),
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
                onPressed: () =>
                    context.read<StorageOrderDetailCubit>().load(),
              ),
            ],
          ),
          floatingActionButton: _ChatBridgeButton(order: order),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _InfoCard(order: order),
              const SizedBox(height: 16),
              OrderStatusTimeline(order: order, auditLog: state.auditLog),
              const SizedBox(height: 16),
              _ItemsSection(state: state),
              const SizedBox(height: 24),
              _ActionSection(state: state),
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
        if (mounted) context.read<StorageOrderDetailCubit>().load();
      });
    });
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
            _InfoRow(Icons.info_outline, 'الحالة', order.statusLabel),
            if (order.rep != null)
              _InfoRow(Icons.person_outline, 'المندوب', order.rep!.fullName),
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
          Text('$label: ',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ─── Items Section ────────────────────────────────────────────────────────────

class _ItemsSection extends StatelessWidget {
  final StorageOrderDetailLoaded state;
  const _ItemsSection({required this.state});

  /// True when the storage actor has an active task on this order.
  bool _isStorageTurn(Order order) {
    final dir = order.direction;
    final status = order.status;
    if (dir == OrderDirection.outbound &&
        order.involvesStorage &&
        status == OrderStatus.assigned) {
      return true;
    }
    if (dir == OrderDirection.inboundRep && status == OrderStatus.onTheMove) {
      return true;
    }
    if (dir == OrderDirection.inboundExternal &&
        status == OrderStatus.assigned) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (state.order.items.isEmpty) {
      return const Text('لا توجد أصناف في هذا الطلب',
          style: TextStyle(color: Colors.grey));
    }

    final storageTurn = _isStorageTurn(state.order);
    // Check controls only shown for inbound_external (items must be verified)
    final showCheckControls =
        storageTurn &&
        state.order.direction == OrderDirection.inboundExternal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الأصناف (${state.order.items.length})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...state.order.items.map(
          (item) => _ItemTile(
            item: item,
            state: state,
            showCheckControls: showCheckControls,
            showQtyEdit: storageTurn && item.inventoryId != null,
            isFinished: state.order.status == OrderStatus.delivered ||
                state.order.status == OrderStatus.deliveredToStorage,
          ),
        ),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  final OrderItem item;
  final StorageOrderDetailLoaded state;
  final bool showCheckControls;
  final bool showQtyEdit;
  final bool isFinished;

  const _ItemTile({
    required this.item,
    required this.state,
    required this.showCheckControls,
    required this.showQtyEdit,
    this.isFinished = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveQty = state.effectiveQuantity(item);
    final effectiveStatus = state.effectiveStatus(item);
    final showWarning = !item.isCustom && item.wasUnavailableAtCreation;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  item.isCustom
                      ? Icons.shopping_bag_outlined
                      : Icons.inventory_outlined,
                  color: item.isCustom ? Colors.orange : Colors.teal,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
                if (showCheckControls)
                  _ItemCheckControls(
                    status: effectiveStatus,
                    isActing: state.isActing,
                    onCheck: () => context
                        .read<StorageOrderDetailCubit>()
                        .checkItem(item.id, ItemCheckStatus.checked),
                    onReject: () => context
                        .read<StorageOrderDetailCubit>()
                        .checkItem(item.id, ItemCheckStatus.rejected),
                    onRevert: () => context
                        .read<StorageOrderDetailCubit>()
                        .checkItem(item.id, ItemCheckStatus.pending),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (showQtyEdit)
              _QuantityEditor(
                itemId: item.id,
                currentQty: effectiveQty,
                originalQty: item.quantity,
              )
            else
              Text('الكمية: $effectiveQty',
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
            if (item.isCustom)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text('إضافة للمخزن'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.teal,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  onPressed: () => _openAddToStorage(context, item),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openAddToStorage(BuildContext context, OrderItem item) async {
    final json = item.customItemJson;
    final prefill = CustomItemPrefill(
      name: json != null ? (json['name'] as String? ?? item.customDescription ?? '') : (item.customDescription ?? ''),
      quantity: item.effectiveQuantity,
      unit: json?['unit'] as String? ?? 'قطعة',
      sku: json?['sku'] as String?,
      category: json?['category'] as String?,
      minQuantity: (json?['minQty'] as num?)?.toInt() ?? 0,
      description: json?['description'] as String?,
    );

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryFormScreen(prefill: prefill),
      ),
    );

    if (added == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت إضافة "${prefill.name}" للمخزن'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }
}

class _QuantityEditor extends StatefulWidget {
  final String itemId;
  final int currentQty;
  final int originalQty;

  const _QuantityEditor({
    required this.itemId,
    required this.currentQty,
    required this.originalQty,
  });

  @override
  State<_QuantityEditor> createState() => _QuantityEditorState();
}

class _QuantityEditorState extends State<_QuantityEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentQty.toString());
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _submit(_controller.text);
  }

  void _submit(String val) {
    final qty = int.tryParse(val);
    if (qty != null && qty > 0) {
      context.read<StorageOrderDetailCubit>().editQuantity(widget.itemId, qty);
    }
  }

  @override
  void didUpdateWidget(_QuantityEditor old) {
    super.didUpdateWidget(old);
    if (old.currentQty != widget.currentQty &&
        _controller.text != widget.currentQty.toString()) {
      _controller.text = widget.currentQty.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final edited = widget.currentQty != widget.originalQty;
    return Row(
      children: [
        Text(
          'الكمية${edited ? ' (معدّلة)' : ''}: ',
          style: TextStyle(
              fontSize: 13,
              color: edited ? Colors.blue : Colors.grey,
              fontWeight: edited ? FontWeight.bold : FontWeight.normal),
        ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: const OutlineInputBorder(),
              hintText: widget.originalQty.toString(),
              suffixText: edited ? '✎' : null,
            ),
            onSubmitted: _submit,
          ),
        ),
        const SizedBox(width: 8),
        Text('(الأصلية: ${widget.originalQty})',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _ItemCheckControls extends StatelessWidget {
  final ItemCheckStatus status;
  final bool isActing;
  final VoidCallback onCheck;
  final VoidCallback onReject;
  final VoidCallback onRevert;

  const _ItemCheckControls({
    required this.status,
    required this.isActing,
    required this.onCheck,
    required this.onReject,
    required this.onRevert,
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

    switch (status) {
      case ItemCheckStatus.pending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
              tooltip: 'مطابق',
              onPressed: onCheck,
            ),
            IconButton(
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              tooltip: 'مرفوض',
              onPressed: onReject,
            ),
          ],
        );
      case ItemCheckStatus.checked:
        return IconButton(
          icon: const Icon(Icons.check_circle, color: Colors.green),
          tooltip: 'مطابق — اضغط للتراجع',
          onPressed: onRevert,
        );
      case ItemCheckStatus.rejected:
        return IconButton(
          icon: const Icon(Icons.cancel, color: Colors.red),
          tooltip: 'مرفوض — اضغط للتراجع',
          onPressed: onRevert,
        );
    }
  }
}

// ─── Action Section ───────────────────────────────────────────────────────────

/// Decides which action to show (or "done" badge) based on the flow.
class _ActionSection extends StatefulWidget {
  final StorageOrderDetailLoaded state;
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

  @override
  Widget build(BuildContext context) {
    final order = widget.state.order;
    final dir = order.direction;
    final status = order.status;

    // ── Flow 1: Outbound + storage items, awaiting storage release ──────────
    if (dir == OrderDirection.outbound &&
        order.involvesStorage &&
        status == OrderStatus.assigned) {
      return _buildActionCard(
        context,
        title: 'تأكيد الإرسال',
        subtitle: 'سيتم خصم الأصناف من المخزن فور التأكيد',
        icon: Icons.upload_outlined,
        color: Colors.orange,
        notesController: _notesController,
        buttonLabel: 'تأكيد الإرسال للمندوب',
        isActing: widget.state.isActing,
        canAct: true,
        onConfirm: () => context.read<StorageOrderDetailCubit>().confirmPickup(
              notes: _notesController.text.trim().isEmpty
                  ? null
                  : _notesController.text.trim(),
            ),
      );
    }

    // ── Flow 3: Inbound rep, rep is on the move toward storage ──────────────
    if (dir == OrderDirection.inboundRep && status == OrderStatus.onTheMove) {
      return _buildActionCard(
        context,
        title: 'تأكيد الاستلام',
        subtitle: 'سيتم إضافة الأصناف للمخزن فور التأكيد',
        icon: Icons.download_outlined,
        color: Colors.teal,
        notesController: _notesController,
        buttonLabel: 'تأكيد استلام البضاعة',
        isActing: widget.state.isActing,
        canAct: true,
        onConfirm: () =>
            context.read<StorageOrderDetailCubit>().confirmDelivery(
                  notes: _notesController.text.trim().isEmpty
                      ? null
                      : _notesController.text.trim(),
                ),
      );
    }

    // ── Flow 4: Inbound external, awaiting storage actor verification ────────
    if (dir == OrderDirection.inboundExternal &&
        status == OrderStatus.assigned) {
      final canConfirm = widget.state.allItemsReviewed;
      return _buildActionCard(
        context,
        title: 'تأكيد الاستلام',
        subtitle: canConfirm
            ? 'سيتم إضافة الأصناف للمخزن فور التأكيد'
            : 'يجب مراجعة جميع الأصناف (مطابق أو مرفوض) قبل التأكيد',
        icon: Icons.download_outlined,
        color: Colors.indigo,
        notesController: _notesController,
        buttonLabel: 'تأكيد استلام الشحنة',
        isActing: widget.state.isActing,
        canAct: canConfirm,
        onConfirm: () =>
            context.read<StorageOrderDetailCubit>().confirmDelivery(
                  notes: _notesController.text.trim().isEmpty
                      ? null
                      : _notesController.text.trim(),
                ),
      );
    }

    // ── Done / waiting state ─────────────────────────────────────────────────
    return _DoneOrWaitingBadge(order: order);
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required TextEditingController notesController,
    required String buttonLabel,
    required bool isActing,
    required bool canAct,
    required VoidCallback onConfirm,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: color)),
              ],
            ),
            const SizedBox(height: 6),
            if (!canAct)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        color: Colors.orange, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(subtitle,
                          style: const TextStyle(
                              color: Colors.orange, fontSize: 13)),
                    ),
                  ],
                ),
              )
            else
              Text(subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات (اختياري)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: canAct && !isActing ? onConfirm : null,
              icon: isActing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(icon),
              label: Text(buttonLabel),
              style: FilledButton.styleFrom(
                  backgroundColor: color,
                  minimumSize: const Size.fromHeight(50)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneOrWaitingBadge extends StatelessWidget {
  final Order order;
  const _DoneOrWaitingBadge({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDone = order.status == OrderStatus.delivered ||
        order.status == OrderStatus.deliveredToStorage;

    if (isDone) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('اكتمل إجراء المخزن على هذا الطلب',
                  style: TextStyle(
                      color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    // Waiting for another actor (e.g. rep hasn't started moving yet)
    return Card(
      color: Colors.grey.shade50,
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_top_outlined, color: Colors.grey),
            SizedBox(width: 8),
            Text('في انتظار إجراء المندوب',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
