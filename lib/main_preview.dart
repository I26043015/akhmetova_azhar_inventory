import 'package:flutter/material.dart';

// Temporary UI preview only. Data lives in memory and is reset on reload.
// The submission version must use Cloud Firestore.
void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Stock Inventory Preview',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    ),
    home: const StockInventoryScreen(),
  ));
}

class StockInventoryScreen extends StatefulWidget {
  const StockInventoryScreen({super.key});

  @override
  State<StockInventoryScreen> createState() => _StockInventoryScreenState();
}

class _StockInventoryScreenState extends State<StockInventoryScreen> {
  static const _categories = [
    'Electronics',
    'Stationery',
    'Hardware',
    'Grocery',
  ];

  final _formKey = GlobalKey<FormState>();
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _reorder = TextEditingController();
  final _search = TextEditingController();
  final _previewItems = <_StockItem>[
    const _StockItem(id: 'demo-101', sku: 'STK-101', itemName: 'USB C Cable',
        category: 'Electronics', quantity: 4, unitPrice: 19.90, reorderLevel: 5),
    const _StockItem(id: 'demo-102', sku: 'STK-102', itemName: 'Notebook',
        category: 'Stationery', quantity: 25, unitPrice: 4.50, reorderLevel: 10),
    const _StockItem(id: 'demo-103', sku: 'STK-103', itemName: 'Wireless Mouse',
        category: 'Electronics', quantity: 1, unitPrice: 35.00, reorderLevel: 3),
  ];
  String? _category;
  String _filterCategory = 'All';
  bool _lowStockOnly = false;
  bool _ascending = true;
  final bool _saving = false;
  String? _saveMessage;

  @override
  void dispose() {
    for (final controller in [
      _sku, _name, _quantity, _price, _reorder, _search,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      errorMaxLines: 2,
    );
  }

  String? _validateSku(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'SKU is required.';
    if (!RegExp(r'^STK-[0-9]{3}$').hasMatch(text)) {
      return 'Use STK- followed by exactly 3 digits, e.g. STK-101.';
    }
    return null;
  }

  String? _validateName(String? value) {
    if ((value ?? '').trim().length < 3) {
      return 'Enter an item name with at least 3 characters.';
    }
    return null;
  }

  String? _validateInteger(String? value, String field) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '$field is required.';
    final number = int.tryParse(text);
    if (!RegExp(r'^[0-9]+$').hasMatch(text) ||
        number == null || number < 0) {
      return '$field must be a whole number, 0 or above.';
    }
    return null;
  }

  String? _validatePrice(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Unit price is required.';
    final number = double.tryParse(text);
    if (number == null || !number.isFinite || number <= 0) {
      return 'Enter a valid price greater than 0, e.g. 19.90.';
    }
    return null;
  }

  void _saveItem() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    final sku = _sku.text.trim();
    final item = _StockItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sku: sku,
      itemName: _name.text.trim(),
      category: _category!,
      quantity: int.parse(_quantity.text.trim()),
      unitPrice: double.parse(_price.text.trim()),
      reorderLevel: int.parse(_reorder.text.trim()),
    );
    _formKey.currentState?.reset();
    for (final controller in [_sku, _name, _quantity, _price, _reorder]) {
      controller.clear();
    }
    setState(() {
      _previewItems.add(item);
      _category = null;
      _saveMessage = '$sku added to this preview only. No Firebase write.';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$sku added to preview only.')),
    );
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _filterCategory = 'All';
      _lowStockOnly = false;
      _ascending = true;
    });
  }

  Widget _entryForm() {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 650
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            final fields = <Widget>[
              TextFormField(
                controller: _sku,
                enabled: !_saving,
                decoration: _decoration('SKU *', hint: 'STK-101'),
                textCapitalization: TextCapitalization.characters,
                validator: _validateSku,
              ),
              TextFormField(
                controller: _name,
                enabled: !_saving,
                decoration: _decoration('Item name *', hint: 'USB C Cable'),
                validator: _validateName,
              ),
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration: _decoration('Category *'),
                items: _categories.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: _saving ? null : (value) {
                  setState(() => _category = value);
                },
                validator: (value) => _categories.contains(value)
                    ? null : 'Please select a category.',
              ),
              TextFormField(
                controller: _quantity,
                enabled: !_saving,
                decoration: _decoration('Quantity *', hint: '4'),
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                validator: (value) => _validateInteger(value, 'Quantity'),
              ),
              TextFormField(
                controller: _price,
                enabled: !_saving,
                decoration: _decoration('Unit price (RM) *', hint: '19.90'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true,
                ),
                validator: _validatePrice,
              ),
              TextFormField(
                controller: _reorder,
                enabled: !_saving,
                decoration: _decoration('Reorder level *', hint: '5'),
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                validator: (value) => _validateInteger(value, 'Reorder level'),
              ),
            ];
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: fields.map((field) {
                return SizedBox(width: width, child: field);
              }).toList(),
            );
          }),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _saving ? null : _saveItem,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Saving...' : 'Save Item'),
          ),
          if (_saveMessage != null) ...[
            const SizedBox(height: 8),
            Text(_saveMessage!),
          ],
        ],
      ),
    );
  }

  Widget _searchControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _search,
          decoration: _decoration('Search name or SKU', hint: 'mouse or stk-102')
              .copyWith(prefixIcon: const Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          // A changed key also resets the internal field on Clear Filters.
          key: ValueKey('category-$_filterCategory'),
          value: _filterCategory,
          isExpanded: true,
          decoration: _decoration('Filter category'),
          items: ['All', ..._categories].map((category) {
            return DropdownMenuItem(value: category, child: Text(category));
          }).toList(),
          onChanged: (value) {
            if (value != null) setState(() => _filterCategory = value);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          key: ValueKey('sort-$_ascending'),
          value: _ascending,
          isExpanded: true,
          decoration: _decoration('Sort by quantity'),
          items: const [
            DropdownMenuItem(value: true, child: Text('Quantity: low to high')),
            DropdownMenuItem(value: false, child: Text('Quantity: high to low')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _ascending = value);
          },
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Low stock only'),
          subtitle: const Text('Quantity is less than or equal to reorder level'),
          value: _lowStockOnly,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) => setState(() => _lowStockOnly = value ?? false),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off),
            label: const Text('Clear Filters'),
          ),
        ),
      ],
    );
  }

  Widget _inventory() {
    final keyword = _search.text.trim().toLowerCase();
    final visible = _previewItems.where((item) {
      final keywordMatches = keyword.isEmpty ||
          item.itemName.toLowerCase().contains(keyword) ||
          item.sku.toLowerCase().contains(keyword);
      final categoryMatches = _filterCategory == 'All' ||
          item.category == _filterCategory;
      final stockMatches = !_lowStockOnly || item.isLowStock;
      return keywordMatches && categoryMatches && stockMatches;
    }).toList();
    visible.sort((a, b) {
      final order = _ascending
          ? a.quantity.compareTo(b.quantity)
          : b.quantity.compareTo(a.quantity);
      return order != 0 ? order : a.sku.compareTo(b.sku);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Showing ${visible.length} of ${_previewItems.length} preview items'),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No items match these filters. Use Clear Filters.'),
          )
        else
          for (final item in visible) _itemCard(item),
      ],
    );
  }

  Widget _itemCard(_StockItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.sku}  |  ${item.itemName}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Category: ${item.category}'),
            Text('Quantity: ${item.quantity}'),
            Text('Unit price: RM ${item.unitPrice.toStringAsFixed(2)}'),
            Text('Reorder level: ${item.reorderLevel}'),
            const SizedBox(height: 8),
            Text(
              item.isLowStock ? 'LOW STOCK' : 'Stock sufficient',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: item.isLowStock ? Colors.red.shade800 : Colors.green.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock Inventory — UI Preview')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('LOCAL PREVIEW: sample data in memory. Firebase not connected.'),
                const SizedBox(height: 16),
                Text('New stock item',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('All six fields are required. Prices are in RM.'),
                const SizedBox(height: 16),
                _entryForm(),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(),
                ),
                Text('Inventory preview',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                _searchControls(),
                const SizedBox(height: 12),
                _inventory(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StockItem {
  const _StockItem({
    required this.id,
    required this.sku,
    required this.itemName,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    required this.reorderLevel,
  });

  final String id;
  final String sku;
  final String itemName;
  final String category;
  final int quantity;
  final double unitPrice;
  final int reorderLevel;

  bool get isLowStock => quantity <= reorderLevel;

}
