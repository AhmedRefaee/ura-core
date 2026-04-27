import 'package:flutter/material.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/models/order.dart';

/// Shared widget for adding items to an order.
/// Used by both CreateOrderScreen and EditOrderScreen.
class AddItemSheet extends StatefulWidget {
  final List<InventoryItem> inventory;
  final OrderDirection orderDirection;
  final void Function(List<({InventoryItem item, int quantity})> items) onAddInventoryItems;
  final void Function(String description, int quantity, {String? sourceInventoryId}) onAddCustomItem;

  const AddItemSheet({
    super.key,
    required this.inventory,
    required this.orderDirection,
    required this.onAddInventoryItems,
    required this.onAddCustomItem,
  });

  @override
  State<AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<AddItemSheet> {
  bool _isCustom = false;
  final _descController = TextEditingController();
  final _customQtyController = TextEditingController(text: '1');
  final _searchController = TextEditingController();
  final Map<String, TextEditingController> _quantityControllers = {};
  String _search = '';
  AvailabilityStatus? _statusFilter;

  // For convert-to-custom flow
  String? _convertSourceInventoryId;

  @override
  void initState() {
    super.initState();
    for (final item in widget.inventory) {
      _quantityControllers[item.id] = TextEditingController(text: '');
    }
  }

  @override
  void dispose() {
    _descController.dispose();
    _customQtyController.dispose();
    _searchController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<InventoryItem> get _filtered => widget.inventory.where((i) {
        final matchesSearch = _search.isEmpty ||
            i.itemName.toLowerCase().contains(_search.toLowerCase());
        final matchesStatus =
            _statusFilter == null || i.availabilityStatus == _statusFilter;
        return matchesSearch && matchesStatus;
      }).toList();

  void _submit() {
    if (_isCustom) {
      final desc = _descController.text.trim();
      final qty = int.tryParse(_customQtyController.text) ?? 0;
      if (desc.isNotEmpty && qty > 0) {
        widget.onAddCustomItem(desc, qty, sourceInventoryId: _convertSourceInventoryId);
      }
    } else {
      final itemsWithQuantities = <({InventoryItem item, int quantity})>[];
      for (final item in _filtered) {
        final qty = int.tryParse(_quantityControllers[item.id]!.text) ?? 0;
        if (qty > 0) {
          itemsWithQuantities.add((item: item, quantity: qty));
        }
      }
      if (itemsWithQuantities.isNotEmpty) {
        widget.onAddInventoryItems(itemsWithQuantities);
      }
    }
    Navigator.pop(context);
  }

  void _convertToCustom(InventoryItem item) {
    setState(() {
      _isCustom = true;
      _convertSourceInventoryId = item.id;
      _descController.text = item.itemName;
      _customQtyController.text = '1';
    });
  }

  Widget _buildStatusChip({
    required String label,
    required AvailabilityStatus status,
    required Color color,
  }) {
    final selected = _statusFilter == status;
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: color.withAlpha(40),
      checkmarkColor: color,
      labelStyle: TextStyle(
        color: selected ? color : null,
        fontWeight: selected ? FontWeight.bold : null,
      ),
      side: selected ? BorderSide(color: color) : null,
      onSelected: (on) =>
          setState(() => _statusFilter = on ? status : null),
    );
  }

  Widget _buildRestockingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.teal.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.teal.withAlpha(120)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward, size: 10, color: Colors.teal),
          SizedBox(width: 2),
          Text(
            'إعادة تخزين',
            style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Color _stockColor(InventoryItem item) {
    switch (item.availabilityStatus) {
      case AvailabilityStatus.available:
        return Colors.green;
      case AvailabilityStatus.low:
        return Colors.orange;
      case AvailabilityStatus.outOfStock:
        return Colors.red;
    }
  }

  String _stockLabel(InventoryItem item) {
    switch (item.availabilityStatus) {
      case AvailabilityStatus.available:
        return 'متوفر';
      case AvailabilityStatus.low:
        return 'مخزون منخفض';
      case AvailabilityStatus.outOfStock:
        return 'غير متوفر';
    }
  }

  Widget _buildStockBadge(InventoryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _stockColor(item).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _stockLabel(item),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _stockColor(item),
        ),
      ),
    );
  }

  bool get _isInbound => widget.orderDirection != OrderDirection.outbound;

  /// Only blocks submission for outbound; inbound orders can restock any item.
  bool get _hasInvalidSelection {
    if (_isCustom || _isInbound) return false;
    for (final item in _filtered) {
      final qty = int.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
      if (qty > 0 && item.quantity == 0) return true;
    }
    return false;
  }

  /// True if at least one item has a quantity entered (for enabling the button).
  bool get _hasAnySelection {
    if (_isCustom) {
      return _descController.text.trim().isNotEmpty &&
          (int.tryParse(_customQtyController.text) ?? 0) > 0;
    }
    for (final item in _filtered) {
      final qty = int.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
      if (qty > 0) return true;
    }
    return false;
  }

  /// Inbound orders restock — no depletion warning applies.
  String? _quantityWarning(InventoryItem item) {
    if (_isInbound) return null;
    final qty = int.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
    if (qty <= 0) return null;
    final result = item.checkStock(qty);
    if (result == StockCheckResult.partial) return 'المتوفر فقط: ${item.quantity}';
    if (result == StockCheckResult.outOfStock) return 'غير متوفر في المخزون';
    return null;
  }

  /// True when an inbound order is actively restocking an out-of-stock item.
  bool _isRestocking(InventoryItem item) {
    if (!_isInbound) return false;
    final qty = int.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
    return qty > 0 && item.availabilityStatus == AvailabilityStatus.outOfStock;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة أصناف'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('وضع الإضافة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: _isCustom,
                  onChanged: (v) => setState(() {
                    _isCustom = v;
                    if (!v) _convertSourceInventoryId = null;
                  }),
                ),
                const Text('مخصص'),
              ],
            ),
            const SizedBox(height: 16),
            if (_isCustom) ...[
              if (_convertSourceInventoryId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz, color: Colors.orange, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'تم التحويل من صنف المخزون',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => setState(() {
                            _convertSourceInventoryId = null;
                            _descController.clear();
                            _isCustom = false;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              TextField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'وصف الصنف',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('الكمية',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      )),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _customQtyController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث باسم الصنف...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _search = '';
                          }),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip(
                      label: 'متوفر',
                      status: AvailabilityStatus.available,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 6),
                    _buildStatusChip(
                      label: 'منخفض',
                      status: AvailabilityStatus.low,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    _buildStatusChip(
                      label: 'نفد',
                      status: AvailabilityStatus.outOfStock,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final item = _filtered[i];
                    final warning = _quantityWarning(item);
                    final isOutOfStock = item.availabilityStatus == AvailabilityStatus.outOfStock;
                    final restocking = _isRestocking(item);

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        SelectableText(
                                          item.itemName,
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              'المتوفر: ${item.quantity}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: _stockColor(item),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            _buildStockBadge(item),
                                            if (restocking) ...[
                                              const SizedBox(width: 6),
                                              _buildRestockingBadge(),
                                            ],
                                          ],
                                        ),
                                        if (item.description != null && item.description!.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: SelectableText(
                                              item.description!,
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        const Text('الكمية',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            textAlign: TextAlign.center),
                                        const SizedBox(height: 4),
                                        TextField(
                                          controller: _quantityControllers[item.id],
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            border: const OutlineInputBorder(),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                            enabledBorder: restocking
                                                ? const OutlineInputBorder(
                                                    borderSide: BorderSide(color: Colors.teal, width: 2),
                                                  )
                                                : warning != null
                                                    ? OutlineInputBorder(
                                                        borderSide: BorderSide(
                                                          color: isOutOfStock ? Colors.red : Colors.orange,
                                                          width: 2,
                                                        ),
                                                      )
                                                    : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (warning != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    warning,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOutOfStock ? Colors.red : Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              if (isOutOfStock && !_isInbound)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TextButton.icon(
                                    onPressed: () => _convertToCustom(item),
                                    icon: const Icon(Icons.swap_horiz, size: 16),
                                    label: const Text('تحويل إلى صنف مخصص'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.orange,
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      textStyle: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (i < _filtered.length - 1)
                          const Padding(
                            padding: EdgeInsets.only(right: 30, left: 30, top: 10),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Color.fromARGB(255, 25, 88, 62),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: !_hasAnySelection || _hasInvalidSelection ? null : _submit,
            child: Text(_isCustom ? 'إضافة صنف مخصص' : 'إضافة الأصناف المحددة'),
          ),
        ),
      ),
    );
  }
}
