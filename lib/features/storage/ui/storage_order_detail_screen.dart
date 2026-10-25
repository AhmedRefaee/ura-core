import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/di/injection.dart';
import '../../../core/errors/app_result.dart';
import '../../../core/design_system/widgets/feedback/app_snackbar.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/order.dart';
import '../../../shared/models/off_stock_kind.dart';
import '../../../shared/models/order_item.dart';
import '../../../shared/utils/quantity_format.dart';
import '../../../shared/widgets/location_link.dart';
import '../../../shared/widgets/off_stock.dart';
import '../../inventory/data/inventory_management_repository.dart';
import '../../inventory/ui/inventory_form_screen.dart';
import '../../../shared/models/inventory_item.dart';
import '../../../shared/widgets/invalid_order_view.dart';
import '../../../shared/widgets/order_status_stepper.dart';
import '../../../shared/widgets/order_status_timeline.dart';
import '../../chat/ui/chat_thread_picker_sheet.dart';
import '../../chat/ui/chat_thread_screen.dart';
import '../logic/storage_order_detail_cubit.dart';
import 'widgets/catalog_search_sheet.dart';
import 'widgets/typed_line_review_sheet.dart';
import '../../delivery_receipts/ui/delivery_receipts_section.dart';

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
                onPressed: () => context.read<StorageOrderDetailCubit>().load(),
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
                onPressed: () => context.read<StorageOrderDetailCubit>().load(),
              ),
            ],
          ),
          floatingActionButton: kChatEnabled
              ? _ChatBridgeButton(order: order)
              : null,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (order.referenceCode != null)
                _ReferenceCodeBar(code: order.referenceCode!),
              _InfoCard(order: order),
              const SizedBox(height: 16),
              OrderStatusStepper(order: order),
              const SizedBox(height: 16),
              OrderStatusTimeline(order: order, auditLog: state.auditLog),
              DeliveryReceiptsSection.forOrder(order.id),
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
  final StorageOrderDetailLoaded state;
  const _ItemsSection({required this.state});

  /// True when the storage actor has an active task on this order.
  bool _isStorageTurn(Order order) {
    final dir = order.direction;
    final status = order.status;
    if (dir == OrderDirection.outbound &&
        !order.storageReviewed &&
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
      return const Text(
        'لا توجد أصناف في هذا الطلب',
        style: TextStyle(color: Colors.grey),
      );
    }

    final storageTurn = _isStorageTurn(state.order);
    // ✓/✗ on every row: for an incoming external shipment (items must be
    // verified) and for an outbound order (storage decides what it has).
    final showCheckControls = storageTurn &&
        (state.order.direction == OrderDirection.inboundExternal ||
            state.order.direction == OrderDirection.outbound);

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
            // On outbound, any row marked ✓ has a quantity to give -- linked
            // or "just available"; less than ordered leaves the rest to the
            // rep. Incoming orders count catalog rows only.
            showQtyEdit: storageTurn &&
                (state.order.direction == OrderDirection.outbound
                    ? state.effectiveStatus(item) == ItemCheckStatus.checked
                    : item.inventoryId != null),
            isFinished: state.order.status == OrderStatus.delivered,
          ),
        ),
      ],
    );
  }
}

String _fmtPurchased(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '${l.day}/${l.month}/${l.year} $h:$m';
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
    final kind = offStockKindOf(item, state.order.direction);
    // Storage is reviewing an outbound order and this line was typed, not
    // picked: ✓ asks what it is (link / add / just available).
    final reviewingTyped = showCheckControls &&
        state.order.direction == OrderDirection.outbound &&
        item.isTypedLine;
    // A line on a real catalog row (picked by the verifier, from a template,
    // or linked by storage): storage may swap it to another row or correct
    // the row's count -- the app's numbers are not always the shelf's.
    final reviewingCatalog = showCheckControls &&
        state.order.direction == OrderDirection.outbound &&
        item.inventoryId != null &&
        !item.isCustom &&
        item.sourceInventoryId == null;
    final stock = item.inventoryStock;

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
                  kind == null ? Icons.inventory_outlined : OffStock.iconFor(kind),
                  color: kind == null ? Colors.teal : OffStock.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      // Linked by storage: keep what was actually asked for
                      // in view, so a wrong link is easy to spot.
                      if (item.isLinkedTypedLine)
                        Text(
                          'كتبها المدقق: ${item.typedName}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                    ],
                  ),
                ),
                if (showCheckControls)
                  _ItemCheckControls(
                    status: effectiveStatus,
                    isActing: state.isActing,
                    onCheck: () => reviewingTyped && item.isCustom
                        ? _reviewTypedLine(context)
                        : context
                            .read<StorageOrderDetailCubit>()
                            .checkItem(item.id, ItemCheckStatus.checked),
                    onReject: () => context
                        .read<StorageOrderDetailCubit>()
                        .checkItem(item.id, ItemCheckStatus.rejected),
                    // Undoing a link puts the line back exactly as typed.
                    onRevert: () => item.isLinkedTypedLine
                        ? context.read<StorageOrderDetailCubit>().linkItem(item.id, null)
                        : context
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
              Text(
                'الكمية: ${formatQty(effectiveQty)}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            if (reviewingCatalog && stock != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'في المخزن: ${formatQty(stock)} ${item.inventoryUnit ?? ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: stock < effectiveQty ? Colors.orange : Colors.grey,
                    fontWeight: stock < effectiveQty ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
            if (showQtyEdit &&
                state.order.direction == OrderDirection.outbound &&
                effectiveQty < item.quantity)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'الباقي (${formatQty(item.quantity - effectiveQty)}) سيشتريه المندوب',
                  style: TextStyle(fontSize: 12, color: OffStock.color),
                ),
              ),
            if (showQtyEdit &&
                state.order.direction == OrderDirection.outbound &&
                effectiveQty > item.quantity)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'أكثر من المطلوب بـ ${formatQty(effectiveQty - item.quantity)}',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ),
            if (kind != null) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: OffStock.badge(kind),
              ),
              if (state.order.direction == OrderDirection.outbound) ...[
                Row(
                  children: [
                    Icon(
                      item.purchasedAt != null
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: item.purchasedAt != null ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.purchasedAt != null
                          ? 'تم الشراء ${_fmtPurchased(item.purchasedAt!)}'
                          : 'لم يُشترَ بعد',
                      style: TextStyle(
                        fontSize: 12,
                        color: item.purchasedAt != null ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
                if (item.purchasedAt != null)
                  if (state.auditLog.forOffStockItem(item.id) case final entry?
                    when entry.locationLat != null && entry.locationLng != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LocationLink(lat: entry.locationLat!, lng: entry.locationLng!),
                    ),
              ],
            ],
            // "Add to storage" turns a خارج المخزون item into a real
            // inventory row. Only offered for the genuinely new ones -- an
            // out-of-stock item is already an inventory row, so there would
            // be nothing to create and a duplicate to risk.
            if (item.isCustom || reviewingCatalog)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  tooltip: 'خيارات الصنف',
                  onSelected: (value) => switch (value) {
                    'add_to_storage' => _openAddToStorage(context, item, link: reviewingTyped),
                    'swap' => _swapItem(context),
                    'stock' => _correctStock(context),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    if (item.isCustom)
                      const PopupMenuItem(
                        value: 'add_to_storage',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.add_box_outlined, color: Colors.teal),
                          title: Text('إضافة للمخزن'),
                        ),
                      ),
                    if (reviewingCatalog) ...const [
                      PopupMenuItem(
                        value: 'swap',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.swap_horiz, color: Colors.teal),
                          title: Text('تغيير الصنف'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'stock',
                        child: ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.inventory_outlined, color: Colors.teal),
                          title: Text('تصحيح رصيد المخزن'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewTypedLine(BuildContext context) async {
    final cubit = context.read<StorageOrderDetailCubit>();
    final choice = await showTypedLineReviewSheet(
      context,
      item: item,
      loadInventory: _loadInventory,
    );
    if (!context.mounted) return;
    switch (choice) {
      case LinkToCatalog(:final item, :final quantity):
        await cubit.linkItem(this.item.id, item.id, quantity: quantity);
      case AddAsNewItem():
        await _openAddToStorage(context, item, link: true);
      case JustAvailable():
        await cubit.checkItem(item.id, ItemCheckStatus.checked);
      case null:
        break;
    }
  }

  static Future<List<InventoryItem>> _loadInventory() async {
    final result = await sl<InventoryManagementRepository>().fetchInventory();
    return switch (result) {
      AppSuccess<List<InventoryItem>>(:final data) => data,
      AppFailure(:final error) => throw Exception(error.message),
    };
  }

  /// Points the line at another catalog row (the verifier picked the wrong
  /// size, say). Same server call as linking a typed line.
  Future<void> _swapItem(BuildContext context) async {
    final cubit = context.read<StorageOrderDetailCubit>();
    final swap = await showCatalogSwapSheet(context, item: item, loadInventory: _loadInventory);
    if (swap == null) return;
    await cubit.linkItem(item.id, swap.item.id, quantity: swap.quantity);
  }

  /// The app's count for this row is not what is on the shelf: storage sets
  /// the real one (audited like any other stock change), then the order
  /// re-reads it.
  Future<void> _correctStock(BuildContext context) async {
    final cubit = context.read<StorageOrderDetailCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: formatQty(item.inventoryStock ?? 0));
    final count = await showDialog<double>(
      context: context,
      builder: (dialog) {
        void submit() {
          final q = double.tryParse(controller.text.trim().replaceAll(',', '.'));
          if (q != null && q >= 0) Navigator.pop(dialog, q);
        }

        return AlertDialog(
          title: const Text('تصحيح رصيد المخزن'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                'في التطبيق: ${formatQty(item.inventoryStock ?? 0)} ${item.inventoryUnit ?? ''} — كم الموجود فعلاً؟',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [quantityInputFormatter],
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  suffixText: item.inventoryUnit,
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('إلغاء')),
            FilledButton(onPressed: submit, child: const Text('حفظ')),
          ],
        );
      },
    );
    controller.dispose();
    if (count == null) return;

    final result = await sl<InventoryManagementRepository>()
        .bulkUpdateQuantities([(itemId: item.inventoryId!, quantity: count)]);
    switch (result) {
      case AppSuccess():
        await cubit.refresh();
        messenger.showSnackBar(const SnackBar(
          content: Text('تم تصحيح رصيد المخزن'),
          backgroundColor: Colors.teal,
        ));
      case AppFailure(:final error):
        messenger.showSnackBar(SnackBar(content: Text(error.message), backgroundColor: Colors.red));
    }
  }

  /// [link]: storage is mid-review, so the new row is also linked to this
  /// line (and the line marked ✓) in the same server call.
  Future<void> _openAddToStorage(BuildContext context, OrderItem item, {bool link = false}) async {
    final cubit = context.read<StorageOrderDetailCubit>();
    final json = item.customItemJson;
    final prefill = CustomItemPrefill(
      name: json != null
          ? (json['name'] as String? ?? item.customDescription ?? '')
          : (item.customDescription ?? ''),
      // Deliberately NOT item.effectiveQuantity. How many were ordered says
      // nothing about how many are on the shelf, and a wrong number that looks
      // deliberate is worse than a blank one -- someone must enter a real count.
      quantity: 0,
      unit: json?['unit'] as String? ?? 'قطعة',
      sku: json?['sku'] as String?,
      category: json?['category'] as String?,
      minQuantity: (json?['minQty'] as num?)?.toDouble() ?? 0,
      description: json?['description'] as String?,
      // Filled in by the verifier while building the order, if they bothered.
      // Absent is fine -- the inventory form leaves them blank and editable.
      brand: json?['brand'] as String?,
      variety: json?['variety'] as String?,
      packagingSize: (json?['packagingSize'] as num?)?.toDouble(),
      packagingSizeUnit: json?['packagingSizeUnit'] as String?,
      linkOrderItemId: link ? item.id : null,
    );

    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => InventoryFormScreen(prefill: prefill)),
    );

    if (added == true && link) await cubit.refresh(forgetItem: item.id);
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
  final double currentQty;
  final double originalQty;

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
    _controller = TextEditingController(text: formatQty(widget.currentQty));
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _submit(_controller.text);
  }

  void _submit(String val) {
    final qty = double.tryParse(val);
    if (qty != null && qty > 0) {
      context.read<StorageOrderDetailCubit>().editQuantity(widget.itemId, qty);
    }
  }

  @override
  void didUpdateWidget(_QuantityEditor old) {
    super.didUpdateWidget(old);
    if (old.currentQty != widget.currentQty &&
        _controller.text != formatQty(widget.currentQty)) {
      _controller.text = formatQty(widget.currentQty);
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
            fontWeight: edited ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [quantityInputFormatter],
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: const OutlineInputBorder(),
              hintText: formatQty(widget.originalQty),
              suffixText: edited ? '✎' : null,
            ),
            onSubmitted: _submit,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '(الأصلية: ${formatQty(widget.originalQty)})',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
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

    // ── Outbound: storage marks every item ✓ / ✗, then confirms ──────────────
    if (dir == OrderDirection.outbound &&
        !order.storageReviewed &&
        status == OrderStatus.assigned) {
      final canConfirm = widget.state.allItemsReviewed;
      final sendsAny = order.items.any(
        (i) => widget.state.effectiveStatus(i) == ItemCheckStatus.checked,
      );
      return _buildActionCard(
        context,
        title: 'تأكيد المراجعة',
        subtitle: !canConfirm
            ? 'يجب مراجعة جميع الأصناف (متوفر أو غير متوفر) قبل التأكيد'
            : sendsAny
                ? 'سيتم خصم الأصناف المتوفرة من المخزن، وما لم يتوفر يشتريه المندوب'
                : 'لا شيء متوفر — سيشتري المندوب كل الأصناف',
        icon: Icons.upload_outlined,
        color: Colors.orange,
        notesController: _notesController,
        buttonLabel: canConfirm && !sendsAny
            ? 'تأكيد — كل الأصناف للشراء'
            : 'تأكيد الإرسال للمندوب',
        isActing: widget.state.isActing,
        canAct: canConfirm,
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
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (!canAct)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border.all(color: Colors.orange.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber,
                      color: Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
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
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon),
              label: Text(buttonLabel),
              style: FilledButton.styleFrom(
                backgroundColor: color,
                minimumSize: const Size.fromHeight(50),
              ),
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
    final isDone = order.status == OrderStatus.delivered;

    if (isDone) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text(
                'اكتمل إجراء المخزن على هذا الطلب',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
            Text(
              'في انتظار إجراء المندوب',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
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
