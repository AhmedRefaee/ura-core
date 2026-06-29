import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/models/order.dart';
import '../../../../shared/utils/quantity_format.dart';
import '../../../../core/design_system/theme/theme.dart';

/// Shared widget for adding items to an order.
/// Used by both CreateOrderScreen and EditOrderScreen.
class AddItemSheet extends StatefulWidget {
  final List<InventoryItem> inventory;
  final OrderDirection orderDirection;
  final void Function(List<({InventoryItem item, double quantity})> items) onAddInventoryItems;
  final void Function(String description, double quantity, {String? sourceInventoryId}) onAddCustomItem;

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
  final _unitCtrl = TextEditingController(text: 'قطعة');
  final _skuCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _minQtyCtrl = TextEditingController(text: '0');
  final _extraDescCtrl = TextEditingController();
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
    _unitCtrl.dispose();
    _skuCtrl.dispose();
    _categoryCtrl.dispose();
    _minQtyCtrl.dispose();
    _extraDescCtrl.dispose();
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
    final inventoryItems = <({InventoryItem item, double quantity})>[];
    for (final item in widget.inventory) {
      final qty = double.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
      if (qty > 0) inventoryItems.add((item: item, quantity: qty));
    }
    if (inventoryItems.isNotEmpty) widget.onAddInventoryItems(inventoryItems);

    if (_isCustom) {
      final name = _descController.text.trim();
      final qty = double.tryParse(_customQtyController.text) ?? 0;
      if (name.isNotEmpty && qty > 0) {
        final payload = jsonEncode({
          'name': name,
          'qty': qty,
          'unit': _unitCtrl.text.trim().isEmpty ? 'قطعة' : _unitCtrl.text.trim(),
          if (_skuCtrl.text.trim().isNotEmpty) 'sku': _skuCtrl.text.trim(),
          if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
          'minQty': double.tryParse(_minQtyCtrl.text) ?? 0,
          if (_extraDescCtrl.text.trim().isNotEmpty) 'description': _extraDescCtrl.text.trim(),
        });
        widget.onAddCustomItem(payload, qty, sourceInventoryId: _convertSourceInventoryId);
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
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalXSmall, vertical: AppSpacing.verticalXSmall),
      decoration: BoxDecoration(
        color: Colors.teal.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.teal.withAlpha(120)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward, size: 10, color: Colors.teal),
          SizedBox(width: AppSpacing.horizontalXSmall),
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
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalXSmall, vertical: AppSpacing.verticalXSmall),
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

  bool get _hasAnySelection {
    if (_isCustom) {
      return _descController.text.trim().isNotEmpty &&
          (double.tryParse(_customQtyController.text) ?? 0) > 0;
    }
    for (final item in _filtered) {
      final qty = double.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
      if (qty > 0) return true;
    }
    return false;
  }

  /// Inbound orders restock — no depletion warning applies.
  String? _quantityWarning(InventoryItem item) {
    if (_isInbound) return null;
    final qty = double.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
    if (qty <= 0) return null;
    final result = item.checkStock(qty);
    if (result == StockCheckResult.partial) return 'المتوفر فقط: ${formatQty(item.quantity)}';
    if (result == StockCheckResult.outOfStock) return 'غير متوفر في المخزون';
    return null;
  }

  /// True when an inbound order is actively restocking an out-of-stock item.
  bool _isRestocking(InventoryItem item) {
    if (!_isInbound) return false;
    final qty = double.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
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
        padding: AppSpacing.allLarge,
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
            SizedBox(height: AppSpacing.verticalLarge),
            if (_isCustom) ...[
              if (_convertSourceInventoryId != null)
                Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.verticalSmall),
                  child: Container(
                    padding: AppSpacing.allSmall,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz, color: Colors.orange, size: 18),
                        SizedBox(width: AppSpacing.horizontalSmall),
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
              Expanded(
                child: ListView(
                  children: [
                    _CustomField(
                      controller: _descController,
                      label: 'اسم الصنف *',
                      onChanged: (_) => setState(() {}),
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _CustomField(
                            controller: _customQtyController,
                            label: 'الكمية *',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [quantityInputFormatter],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        SizedBox(width: AppSpacing.horizontalMedium),
                        Expanded(
                          child: _CustomField(
                            controller: _unitCtrl,
                            label: 'الوحدة *',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    _CustomField(
                      controller: _skuCtrl,
                      label: 'رمز SKU (اختياري)',
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    _CustomField(
                      controller: _categoryCtrl,
                      label: 'الفئة (اختياري)',
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    _CustomField(
                      controller: _minQtyCtrl,
                      label: 'حد التنبيه (اختياري)',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [quantityInputFormatter],
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    _CustomField(
                      controller: _extraDescCtrl,
                      label: 'الوصف (اختياري)',
                      maxLines: 3,
                    ),
                  ],
                ),
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
                      EdgeInsets.symmetric(horizontal: AppSpacing.horizontalLarge, vertical: 0),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
              SizedBox(height: AppSpacing.verticalSmall),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip(
                      label: 'متوفر',
                      status: AvailabilityStatus.available,
                      color: Colors.green,
                    ),
                    SizedBox(width: AppSpacing.horizontalSmall),
                    _buildStatusChip(
                      label: 'منخفض',
                      status: AvailabilityStatus.low,
                      color: Colors.orange,
                    ),
                    SizedBox(width: AppSpacing.horizontalSmall),
                    _buildStatusChip(
                      label: 'نفد',
                      status: AvailabilityStatus.outOfStock,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppSpacing.verticalSmall),
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
                          padding: EdgeInsets.symmetric(vertical: AppSpacing.verticalXSmall),
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
                                        SizedBox(height: AppSpacing.verticalXSmall),
                                        Row(
                                          children: [
                                            Text(
                                              'المتوفر: ${formatQty(item.quantity)}',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: _stockColor(item),
                                              ),
                                            ),
                                            SizedBox(width: AppSpacing.horizontalSmall),
                                            _buildStockBadge(item),
                                            if (restocking) ...[
                                              SizedBox(width: AppSpacing.horizontalSmall),
                                              _buildRestockingBadge(),
                                            ],
                                          ],
                                        ),
                                        if (item.description != null && item.description!.isNotEmpty)
                                          Padding(
                                            padding: EdgeInsets.only(top: AppSpacing.verticalXSmall),
                                            child: SelectableText(
                                              item.description!,
                                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: AppSpacing.horizontalSmall),
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
                                        SizedBox(height: AppSpacing.verticalXSmall),
                                        TextField(
                                          controller: _quantityControllers[item.id],
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [quantityInputFormatter],
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            border: const OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalSmall, vertical: AppSpacing.verticalMedium),
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
                                  padding: EdgeInsets.only(top: AppSpacing.verticalXSmall),
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
                                  padding: EdgeInsets.only(top: AppSpacing.verticalXSmall),
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
                            padding: EdgeInsets.only(right: AppSpacing.horizontalXXXLarge, left: AppSpacing.horizontalXXXLarge, top: AppSpacing.verticalMedium),
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
          padding: AppSpacing.allLarge,
          child: FilledButton(
            onPressed: !_hasAnySelection ? null : _submit,
            child: Text(_isCustom ? 'إضافة صنف مخصص' : 'إضافة الأصناف المحددة'),
          ),
        ),
      ),
    );
  }
}

class _CustomField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _CustomField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.horizontalMedium, vertical: AppSpacing.verticalMedium),
      ),
    );
  }
}
