import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../shared/models/inventory_item.dart';
import '../../../../shared/models/order.dart';
import '../../../../shared/utils/quantity_format.dart';
import '../../../../core/design_system/theme/theme.dart';
import '../../../../core/di/injection.dart';
import '../../logic/ai_add_item_cubit.dart';
import 'paste_add_item_view.dart';
import '../../../../shared/widgets/off_stock.dart';

/// Shared widget for adding items to an order.
/// Used by both CreateOrderScreen and EditOrderScreen.
class AddItemSheet extends StatefulWidget {
  final List<InventoryItem> inventory;
  final OrderDirection orderDirection;
  final void Function(List<({InventoryItem item, double quantity})> items) onAddInventoryItems;
  final void Function(String description, double quantity, {String? sourceInventoryId}) onAddCustomItem;

  /// When non-null the sheet opens straight into the custom-item form,
  /// pre-filled from this payload, and submitting calls [onUpdateCustomItem]
  /// instead of [onAddCustomItem]. This is how a draft off-stock item gets its
  /// brand/variety/packaging filled in after it was first added.
  final String? initialCustomJson;
  final void Function(String description, double quantity)? onUpdateCustomItem;

  const AddItemSheet({
    super.key,
    required this.inventory,
    required this.orderDirection,
    required this.onAddInventoryItems,
    required this.onAddCustomItem,
    this.initialCustomJson,
    this.onUpdateCustomItem,
  });

  bool get isEditingCustom => initialCustomJson != null;

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
  final _brandCtrl = TextEditingController();
  final _varietyCtrl = TextEditingController();
  final _packSizeCtrl = TextEditingController();
  final _packUnitCtrl = TextEditingController();
  final _searchController = TextEditingController();
  final Map<String, TextEditingController> _quantityControllers = {};
  String _search = '';
  AvailabilityStatus? _statusFilter;

  /// Selected category chip, or null for "all". Distinct from [_categoryCtrl],
  /// which is the category *typed in* when creating an outside-inventory item.
  String? _categoryFilter;

  // For convert-to-custom flow
  String? _convertSourceInventoryId;

  // Controllers are created lazily (see _controllerFor) rather than one per
  // inventory item up front, so memory scales with items actually rendered
  // rather than total inventory size.
  TextEditingController _controllerFor(String itemId) =>
      _quantityControllers.putIfAbsent(itemId, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    final raw = widget.initialCustomJson;
    if (raw == null) return;

    _isCustom = true;
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Items added before the payload was JSON stored a bare description.
      _descController.text = raw;
      return;
    }

    _descController.text = json['name'] as String? ?? '';
    _customQtyController.text = formatQty((json['qty'] as num?)?.toDouble() ?? 1);
    _unitCtrl.text = json['unit'] as String? ?? 'قطعة';
    _skuCtrl.text = json['sku'] as String? ?? '';
    _categoryCtrl.text = json['category'] as String? ?? '';
    _minQtyCtrl.text = formatQty((json['minQty'] as num?)?.toDouble() ?? 0);
    _extraDescCtrl.text = json['description'] as String? ?? '';
    _brandCtrl.text = json['brand'] as String? ?? '';
    _varietyCtrl.text = json['variety'] as String? ?? '';
    final packSize = (json['packagingSize'] as num?)?.toDouble();
    _packSizeCtrl.text = packSize != null ? formatQty(packSize) : '';
    _packUnitCtrl.text = json['packagingSizeUnit'] as String? ?? '';
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
    _brandCtrl.dispose();
    _varietyCtrl.dispose();
    _packSizeCtrl.dispose();
    _packUnitCtrl.dispose();
    _searchController.dispose();
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Categories present in the catalogue, derived from the items already in
  /// memory rather than fetched -- same approach as InventoryListCubit's
  /// availableCategories, so the picker offers exactly the categories the
  /// inventory screen does without any extra loading.
  List<String> get _categories {
    final cats = widget.inventory
        .map((i) => i.category)
        .whereType<String>()
        .where((c) => c.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cats;
  }

  List<InventoryItem> get _filtered => widget.inventory.where((i) {
        final matchesSearch = _search.isEmpty ||
            i.itemName.toLowerCase().contains(_search.toLowerCase());
        final matchesStatus =
            _statusFilter == null || i.availabilityStatus == _statusFilter;
        final matchesCategory =
            _categoryFilter == null || i.category == _categoryFilter;
        return matchesSearch && matchesStatus && matchesCategory;
      }).toList();

  void _submit() {
    if (_isCustom) {
      final name = _descController.text.trim();
      final qty = double.tryParse(_customQtyController.text) ?? 0;
      if (name.isNotEmpty && qty > 0) {
        final packSize = double.tryParse(_packSizeCtrl.text.trim());
        final payload = jsonEncode({
          'name': name,
          'qty': qty,
          'unit': _unitCtrl.text.trim().isEmpty ? 'قطعة' : _unitCtrl.text.trim(),
          if (_skuCtrl.text.trim().isNotEmpty) 'sku': _skuCtrl.text.trim(),
          if (_categoryCtrl.text.trim().isNotEmpty) 'category': _categoryCtrl.text.trim(),
          'minQty': double.tryParse(_minQtyCtrl.text) ?? 0,
          if (_extraDescCtrl.text.trim().isNotEmpty) 'description': _extraDescCtrl.text.trim(),
          // Optional throughout -- an item that needs no such detail is saved
          // without it, and can be filled in later when it is promoted into
          // the inventory.
          if (_brandCtrl.text.trim().isNotEmpty) 'brand': _brandCtrl.text.trim(),
          if (_varietyCtrl.text.trim().isNotEmpty) 'variety': _varietyCtrl.text.trim(),
          'packagingSize': ?packSize,
          if (_packUnitCtrl.text.trim().isNotEmpty)
            'packagingSizeUnit': _packUnitCtrl.text.trim(),
        });
        if (widget.isEditingCustom) {
          widget.onUpdateCustomItem?.call(payload, qty);
        } else {
          widget.onAddCustomItem(payload, qty, sourceInventoryId: _convertSourceInventoryId);
        }
      }
    } else {
      final inventoryItems = <({InventoryItem item, double quantity})>[];
      for (final item in widget.inventory) {
        final qty = double.tryParse(_quantityControllers[item.id]?.text ?? '') ?? 0;
        if (qty > 0) inventoryItems.add((item: item, quantity: qty));
      }
      if (inventoryItems.isNotEmpty) widget.onAddInventoryItems(inventoryItems);
    }

    Navigator.pop(context);
  }

  Future<void> _openPasteAddItem() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<AiAddItemCubit>(),
          child: PasteAddItemView(
            inventory: widget.inventory,
            onAddInventoryItems: widget.onAddInventoryItems,
            onAddCustomItem: widget.onAddCustomItem,
          ),
        ),
      ),
    );
    if (added == true && mounted) Navigator.pop(context);
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

  Widget _buildCategoryChip(String category) {
    final selected = _categoryFilter == category;
    return FilterChip(
      label: Text(category),
      selected: selected,
      // Tapping the selected chip clears it back to "all", matching how the
      // status chips above already behave.
      onSelected: (on) =>
          setState(() => _categoryFilter = on ? category : null),
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditingCustom ? 'تعديل الصنف' : 'إضافة أصناف'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!widget.isEditingCustom)
            IconButton(
              icon: const Icon(Icons.content_paste),
              tooltip: 'إضافة من رسالة',
              onPressed: _openPasteAddItem,
            ),
        ],
      ),
      body: Padding(
        padding: AppSpacing.allLarge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Editing an existing off-stock item -- there is nothing to switch
            // to, the item is already custom.
            if (!widget.isEditingCustom)
            Row(
              children: [
                const Text('وضع الإضافة',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: _isCustom,
                  onChanged: (v) => setState(() {
                    _isCustom = v;
                    if (!v) {
                      _convertSourceInventoryId = null;
                    } else {
                      // Clear stale inventory quantities so switching back to
                      // inventory mode later starts from a clean slate.
                      for (final controller in _quantityControllers.values) {
                        controller.clear();
                      }
                    }
                  }),
                ),
                Text(OffStock.label),
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
                      color: OffStock.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: OffStock.color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz, color: OffStock.color, size: 18),
                        SizedBox(width: AppSpacing.horizontalSmall),
                        Expanded(
                          child: Text(
                            'تم التحويل من صنف المخزون',
                            style: TextStyle(fontSize: 12, color: OffStock.color),
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
                    Row(
                      children: [
                        Expanded(
                          child: _CustomField(
                            controller: _brandCtrl,
                            label: 'العلامة التجارية (اختياري)',
                          ),
                        ),
                        SizedBox(width: AppSpacing.horizontalMedium),
                        Expanded(
                          child: _CustomField(
                            controller: _varietyCtrl,
                            label: 'النوع (اختياري)',
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.verticalMedium),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _CustomField(
                            controller: _packSizeCtrl,
                            label: 'حجم التعبئة (اختياري)',
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [quantityInputFormatter],
                          ),
                        ),
                        SizedBox(width: AppSpacing.horizontalMedium),
                        Expanded(
                          child: _CustomField(
                            controller: _packUnitCtrl,
                            label: 'وحدة التعبئة',
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
              // Wrap, never a horizontal scroll strip. A horizontal
              // SingleChildScrollView cannot be dragged with a mouse -- Flutter
              // leaves PointerDeviceKind.mouse out of the default drag devices
              // and draws no scrollbar -- so on desktop web every chip past the
              // right edge is simply unreachable. Wrapping is also what the
              // inventory screen's own filter card does.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatusChip(
                    label: 'متوفر',
                    status: AvailabilityStatus.available,
                    color: Colors.green,
                  ),
                  _buildStatusChip(
                    label: 'منخفض',
                    status: AvailabilityStatus.low,
                    color: Colors.orange,
                  ),
                  _buildStatusChip(
                    label: 'نفد',
                    status: AvailabilityStatus.outOfStock,
                    color: Colors.red,
                  ),
                ],
              ),
              // Categories keep their own block rather than joining the status
              // chips: there are many of them (18 in the live catalogue, several
              // long), and mixing the two kinds of filter makes neither easy to
              // scan. Capped in height and scrolled VERTICALLY when they
              // overflow -- a mouse wheel and a finger both work that way -- so
              // a long category list cannot swallow the item list below.
              if (_categories.isNotEmpty) ...[
                SizedBox(height: AppSpacing.verticalSmall),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 112),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in _categories)
                          _buildCategoryChip(category),
                      ],
                    ),
                  ),
                ),
              ],
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
                                          controller: _controllerFor(item.id),
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
                                    label: Text('تحويل إلى ${OffStock.label}'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: OffStock.color,
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
                          Padding(
                            padding: EdgeInsets.only(right: AppSpacing.horizontalXXXLarge, left: AppSpacing.horizontalXXXLarge, top: AppSpacing.verticalMedium),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: theme.dividerColor,
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
            child: Text(
              widget.isEditingCustom
                  ? 'حفظ التعديل'
                  : _isCustom
                      ? 'إضافة ${OffStock.label}'
                      : 'إضافة الأصناف المحددة',
            ),
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
