import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _mint = Color(0xFF167C65);
const _ink = Color(0xFF172D29);
const _muted = Color(0xFF74837E);
const _bg = Color(0xFFF5F7F4);
const _line = Color(0xFFE7ECE7);
const _categories = ['Electronics', 'Stationery', 'Hardware', 'Grocery'];

const _firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyATJ7BJcc6wq74orfUJBUJAAyXYOHS_atU',
  authDomain: 'azhar-inventory-1103.firebaseapp.com',
  projectId: 'azhar-inventory-1103',
  storageBucket: 'azhar-inventory-1103.firebasestorage.app',
  messagingSenderId: '305325777863',
  appId: '1:305325777863:web:3633d9b8ba7a67dd066fe2',
);

FirebaseFirestore? _database;
String? _startupError;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: _firebaseOptions);
    _database = FirebaseFirestore.instance;
  } on FirebaseException catch (error) {
    _startupError = 'Firebase connection failed (${error.code}): ${error.message ?? ''}';
  } catch (error) {
    _startupError = 'Firebase connection failed: $error';
  }
  runApp(const StockFlowApp());
}

class StockFlowApp extends StatelessWidget {
  const StockFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: _bg,
      colorScheme: ColorScheme.fromSeed(seedColor: _mint),
    );
    return MaterialApp(
      title: 'StockFlow · Inventory',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(base.textTheme).apply(
          bodyColor: _ink, displayColor: _ink,
        ),
        dividerColor: _line,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAF8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _mint, width: 1.5),
          ),
          errorMaxLines: 2,
          labelStyle: const TextStyle(color: _muted, fontSize: 13),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _mint,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _ink,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: _ink,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const StockFlowHome(),
    );
  }
}

class StockItem {
  const StockItem({
    required this.id,
    required this.sku,
    required this.itemName,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    required this.reorderLevel,
  });

  final String id, sku, itemName, category;
  final int quantity, reorderLevel;
  final double unitPrice;
  bool get lowStock => quantity <= reorderLevel;

  static StockItem? fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final sku = d['sku'], name = d['itemName'], category = d['category'];
    final qty = d['quantity'], price = d['unitPrice'], reorder = d['reorderLevel'];
    if (sku is! String || name is! String || category is! String ||
        qty is! int || reorder is! int || price is! num ||
        qty < 0 || reorder < 0 || !price.isFinite || price <= 0) {
      return null;
    }
    return StockItem(
      id: doc.id, sku: sku, itemName: name, category: category,
      quantity: qty, unitPrice: price.toDouble(), reorderLevel: reorder,
    );
  }
}

class StockFlowHome extends StatefulWidget {
  const StockFlowHome({super.key});

  @override
  State<StockFlowHome> createState() => _StockFlowHomeState();
}

class _StockFlowHomeState extends State<StockFlowHome> {
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _reorder = TextEditingController();
  final _search = TextEditingController();
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _saveTimer;
  List<StockItem> _items = [];
  String? _category, _readError, _saveError, _saveNotice;
  String _filterCategory = 'All';
  int _page = 0, _pending = 0, _invalid = 0;
  bool _loading = true, _cached = true, _saving = false;
  bool _lowOnly = false, _ascending = true, _grid = false;

  CollectionReference<Map<String, dynamic>>? get _collection =>
      _database?.collection('stockItems');

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _subscription?.cancel();
    final collection = _collection;
    if (collection == null) {
      _loading = false;
      _readError = _startupError ?? 'Firebase is not initialized.';
      return;
    }
    _subscription = collection.snapshots(includeMetadataChanges: true).listen(
          (snapshot) {
        if (!mounted) return;
        final items = <StockItem>[];
        var pending = 0, invalid = 0;
        for (final doc in snapshot.docs) {
          if (doc.metadata.hasPendingWrites) {
            pending++;
            continue;
          }
          final item = StockItem.fromDocument(doc);
          if (item == null) {
            invalid++;
          } else {
            items.add(item);
          }
        }
        setState(() {
          _items = items;
          _pending = pending;
          _invalid = invalid;
          _cached = snapshot.metadata.isFromCache;
          _loading = false;
          _readError = null;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _readError = error is FirebaseException
              ? '${error.code}: ${error.message ?? 'Unable to read inventory.'}'
              : 'Unable to read inventory: $error';
        });
      },
    );
  }

  void _retry() {
    setState(() { _loading = true; _readError = null; });
    _listen();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _subscription?.cancel();
    for (final c in [_sku, _name, _quantity, _price, _reorder, _search]) {
      c.dispose();
    }
    super.dispose();
  }

  void _goTo(int page, {bool drawer = false, bool lowStock = false}) {
    if (_saving) return;
    if (drawer) Navigator.of(context).pop();
    setState(() {
      _page = page;
      if (lowStock) _lowOnly = true;
    });
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _filterCategory = 'All';
      _lowOnly = false;
      _ascending = true;
    });
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    for (final c in [_sku, _name, _quantity, _price, _reorder]) {
      c.clear();
    }
    setState(() {
      _category = null;
      _formKey = GlobalKey<FormState>();
      _saveError = null;
      _saveNotice = null;
    });
  }

  String? _validateInteger(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '$label is required.';
    final number = int.tryParse(text);
    if (!RegExp(r'^[0-9]+$').hasMatch(text) || number == null || number < 0) {
      return '$label must be a whole number, 0 or above.';
    }
    return null;
  }

  Future<void> _saveItem() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final collection = _collection;
    if (collection == null) {
      setState(() => _saveError = 'Firebase is not connected. Your input is kept.');
      return;
    }
    FocusScope.of(context).unfocus();
    final sku = _sku.text.trim();
    final data = <String, dynamic>{
      'sku': sku,
      'itemName': _name.text.trim(),
      'category': _category!,
      'quantity': int.parse(_quantity.text.trim()),
      'unitPrice': double.parse(_price.text.trim()),
      'reorderLevel': int.parse(_reorder.text.trim()),
      'createdAt': FieldValue.serverTimestamp(),
    };
    setState(() {
      _saving = true;
      _saveError = null;
      _saveNotice = 'Saving securely to Cloud Firestore…';
    });
    _saveTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _saving) {
        setState(() => _saveNotice =
        'Waiting for Firebase confirmation. Check your internet and keep this page open.');
      }
    });
    try {
      // An auto ID is generated. Success is shown only after server acknowledgement.
      await collection.add(data);
      _saveTimer?.cancel();
      if (!mounted) return;
      _clearForm();
      setState(() => _page = 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$sku saved to Cloud Firestore.')),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Save failed (${error.code}). ${error.message ?? ''} Your input is kept.';
        _saveNotice = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = 'Save failed. Your input is kept. $error';
        _saveNotice = null;
      });
    } finally {
      _saveTimer?.cancel();
      if (mounted) setState(() => _saving = false);
    }
  }

  List<StockItem> get _visible {
    final keyword = _search.text.trim().toLowerCase();
    final result = _items.where((item) {
      final matchesText = keyword.isEmpty ||
          item.itemName.toLowerCase().contains(keyword) ||
          item.sku.toLowerCase().contains(keyword);
      final matchesCategory =
          _filterCategory == 'All' || item.category == _filterCategory;
      final matchesStock = !_lowOnly || item.lowStock;
      return matchesText && matchesCategory && matchesStock;
    }).toList();
    result.sort((a, b) {
      final order = _ascending
          ? a.quantity.compareTo(b.quantity)
          : b.quantity.compareTo(a.quantity);
      if (order != 0) return order;
      final skuOrder = a.sku.compareTo(b.sku);
      return skuOrder != 0 ? skuOrder : a.id.compareTo(b.id);
    });
    return result;
  }

  Widget _brand({bool light = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 39, height: 39,
        decoration: BoxDecoration(
          color: light ? const Color(0xFFCDF3C9) : _mint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.layers_rounded, color: light ? _ink : Colors.white, size: 25),
      ),
      const SizedBox(width: 11),
      Text('stockflow', style: TextStyle(
        fontSize: 22, fontWeight: FontWeight.w800,
        letterSpacing: -1, color: light ? Colors.white : _ink,
      )),
      Text('.', style: TextStyle(
        fontSize: 27, fontWeight: FontWeight.w800,
        color: light ? const Color(0xFFCDF3C9) : _mint,
      )),
    ],
  );

  Widget _navItem(String title, IconData icon, bool selected, VoidCallback onTap,
      {String? trailing}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: selected ? const Color(0xFFDDF3DB) : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: _saving ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(children: [
            Icon(icon, color: selected ? _ink : const Color(0xFF9EB1A8), size: 21),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: selected ? _ink : const Color(0xFFC6D2CC),
            ))),
            if (trailing != null) Text(trailing, style: TextStyle(
              color: selected ? _ink : const Color(0xFF9EB1A8), fontSize: 12,
            )),
          ]),
        ),
      ),
    ),
  );

  Widget _sidebar(bool drawer) {
    final low = _items.where((item) => item.lowStock).length;
    return Container(
      width: 228, color: const Color(0xFF172D29),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(19, 27, 19, 21),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _brand(light: true),
            const Padding(
              padding: EdgeInsets.only(top: 9, left: 50),
              child: Text('INVENTORY WORKSPACE', style: TextStyle(
                color: Color(0xFF8FA99B), fontSize: 8, letterSpacing: 1.5,
              )),
            ),
            const SizedBox(height: 48),
            const Text('WORKSPACE', style: TextStyle(
              color: Color(0xFF7D9A8A), fontSize: 9, letterSpacing: 2,
            )),
            const SizedBox(height: 15),
            _navItem('Inventory', Icons.grid_view_rounded, _page == 0,
                    () => _goTo(0, drawer: drawer),
                trailing: _loading ? '—' : '${_items.length}'),
            _navItem('Add item', Icons.add_box_outlined, _page == 1,
                    () => _goTo(1, drawer: drawer)),
            _navItem('Low stock', Icons.tune_rounded, false,
                    () => _goTo(0, drawer: drawer, lowStock: true),
                trailing: '$low'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF244037),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.cloud_done_outlined, color: Color(0xFFB5D6AA), size: 22),
                  SizedBox(height: 12),
                  Text('A little more organized.', style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12,
                  )),
                  SizedBox(height: 7),
                  Text('Your inventory, connected to Cloud Firestore.', style: TextStyle(
                    color: Color(0xFFABC2B5), fontSize: 11, height: 1.6,
                  )),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: Color(0xFF355046)),
            const SizedBox(height: 13),
            const Row(children: [
              CircleAvatar(
                radius: 18, backgroundColor: Color(0xFFCDEBBF),
                child: Text('AZ', style: TextStyle(
                  color: _ink, fontSize: 11, fontWeight: FontWeight.w800,
                )),
              ),
              SizedBox(width: 10),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Azhar Akhmetova', style: TextStyle(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
                )),
                SizedBox(height: 3),
                Text('Stock manager', style: TextStyle(color: Color(0xFF94AD9F), fontSize: 10)),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _connectionPill() {
    final error = _readError != null;
    final label = error ? 'Connection issue' :
    (_loading ? 'Connecting' : (_cached ? 'Syncing' : 'Live inventory'));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFF0E9) : const Color(0xFFE6F2E6),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(
          shape: BoxShape.circle, color: error ? Colors.orange.shade700 : _mint,
        )),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(
          color: error ? Colors.orange.shade900 : _mint,
          fontWeight: FontWeight.w700, fontSize: 10,
        )),
      ]),
    );
  }

  Widget _topbar() => Padding(
    padding: const EdgeInsets.only(bottom: 29),
    child: Row(children: [
      const Text('Workspace', style: TextStyle(color: _muted, fontSize: 12)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
      ),
      Expanded(child: Text(_page == 0 ? 'Inventory' : 'Add item',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      _connectionPill(),
    ]),
  );

  Widget _hero() {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 710;
      return Container(
        padding: EdgeInsets.all(wide ? 29 : 22),
        decoration: BoxDecoration(
          color: const Color(0xFFE3EEDC),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.auto_awesome_outlined, size: 14, color: _mint),
              SizedBox(width: 7),
              Text('A CLEARER PICTURE OF YOUR STOCK', style: TextStyle(
                fontSize: 9, letterSpacing: 1.4, color: _mint, fontWeight: FontWeight.w800,
              )),
            ]),
            const SizedBox(height: 15),
            Text('Everything in stock.\nEverything in view.', style: TextStyle(
              fontSize: wide ? 34 : 27, height: 1.15,
              letterSpacing: -1.5, fontWeight: FontWeight.w800,
            )),
            const SizedBox(height: 11),
            const Text('One place for your products, quantities and daily stock decisions.',
                style: TextStyle(color: Color(0xFF627563), fontSize: 12, height: 1.6)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _goTo(1),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add a stock item'),
            ),
          ])),
          if (wide) ...[
            const SizedBox(width: 20),
            SizedBox(
              width: 278, height: 210,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  right: 8, top: 0,
                  child: Transform.rotate(
                    angle: 0.11,
                    child: _photoTile('STK-103', 'Wireless mouse', 145),
                  ),
                ),
                Positioned(
                  left: 0, bottom: 0,
                  child: Transform.rotate(
                    angle: -0.10,
                    child: _photoTile('STK-102', 'Daily essentials', 130),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      );
    });
  }

  Widget _photoTile(String sku, String label, double size) => Container(
    width: size,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(19),
      boxShadow: const [BoxShadow(color: Color(0x15243D26), blurRadius: 23, offset: Offset(0, 10))],
    ),
    child: Column(children: [
      ProductPhoto(sku: sku, size: size - 20),
      const SizedBox(height: 9),
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
    ]),
  );

  Widget _stats() {
    final units = _items.fold<int>(0, (total, item) => total + item.quantity);
    final value = _items.fold<double>(0, (total, item) => total + item.quantity * item.unitPrice);
    final low = _items.where((item) => item.lowStock).length;
    final cards = [
      _stat('Products', _loading ? '—' : '${_items.length}', 'Saved stock items',
          Icons.inventory_2_outlined, const Color(0xFFEAF3F0)),
      _stat('Total units', _loading ? '—' : '$units', 'Across your inventory',
          Icons.layers_outlined, const Color(0xFFE9EEFA)),
      _stat('Low stock', _loading ? '—' : '$low', 'At or below reorder level',
          Icons.warning_amber_rounded, const Color(0xFFFFF1D7), attention: low > 0),
      _stat('Stock value', _loading ? '—' : 'RM ${value.toStringAsFixed(2)}', 'Quantity × unit price',
          Icons.payments_outlined, const Color(0xFFEDE8F6)),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth >= 850 ? 4 : (constraints.maxWidth >= 430 ? 2 : 1);
      final width = (constraints.maxWidth - (columns - 1) * 13) / columns;
      return Wrap(spacing: 13, runSpacing: 13, children: [
        for (final card in cards) SizedBox(width: width, child: card),
      ]);
    });
  }

  Widget _stat(String label, String value, String caption, IconData icon, Color color,
      {bool attention = false}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _line),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(
          color: _muted, fontSize: 11, fontWeight: FontWeight.w600,
        ))),
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: attention ? const Color(0xFFAD761A) : _ink),
        ),
      ]),
      const SizedBox(height: 15),
      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
          child: Text(value, style: const TextStyle(
            fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -1,
          ))),
      const SizedBox(height: 6),
      Text(caption, style: const TextStyle(color: _muted, fontSize: 9)),
    ]),
  );

  Widget _filters() {
    return _panel(
      padding: const EdgeInsets.all(17),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: width >= 720 ? math.max(230.0, width - 448) : width,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search by product name or SKU…',
                    prefixIcon: Icon(Icons.search_rounded, size: 21, color: _muted),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: width >= 720 ? 194 : math.min(width, 240.0),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('filter-$_filterCategory'),
                  value: _filterCategory,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category', isDense: true),
                  items: ['All', ..._categories].map((c) =>
                      DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (value) => setState(() => _filterCategory = value ?? 'All'),
                ),
              ),
              SizedBox(
                width: width >= 720 ? 230 : math.min(width, 240.0),
                child: DropdownButtonFormField<bool>(
                  key: ValueKey('sort-$_ascending'),
                  value: _ascending,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sort by quantity', isDense: true),
                  items: const [
                    DropdownMenuItem(value: true, child: Text('Low to high', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(value: false, child: Text('High to low', style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (value) => setState(() => _ascending = value ?? true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Low stock only', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                selected: _lowOnly,
                selectedColor: const Color(0xFFE2F1E1),
                backgroundColor: Colors.white,
                side: const BorderSide(color: _line),
                avatar: Icon(Icons.tune_rounded, size: 15, color: _lowOnly ? _mint : _muted),
                onSelected: (value) => setState(() => _lowOnly = value),
              ),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Clear Filters', style: TextStyle(fontSize: 11)),
              ),
              const Text('Low stock = quantity ≤ reorder level',
                  style: TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
        ]);
      }),
    );
  }

  Widget _status(StockItem item) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: item.lowStock ? const Color(0xFFFFF2DB) : const Color(0xFFE6F2E5),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Text(item.lowStock ? 'Low stock' : 'In stock', style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w700,
      color: item.lowStock ? const Color(0xFF9C6B14) : _mint,
    )),
  );

  Widget _table(List<StockItem> visible) => _panel(
    padding: EdgeInsets.zero,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: DataTable(
            headingRowHeight: 45,
            dataRowMinHeight: 88, dataRowMaxHeight: 88,
            horizontalMargin: 22, columnSpacing: 30,
            dividerThickness: 0.6,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFFAFCF9)),
            headingTextStyle: GoogleFonts.manrope(
                fontSize: 10, fontWeight: FontWeight.w700, color: _muted),
            sortColumnIndex: 2, sortAscending: _ascending,
            columns: [
              const DataColumn(label: Text('PRODUCT / SKU')),
              const DataColumn(label: Text('CATEGORY')),
              DataColumn(
                label: const Text('QUANTITY'),
                onSort: (_, ascending) => setState(() => _ascending = ascending),
              ),
              const DataColumn(label: Text('UNIT PRICE')),
              const DataColumn(label: Text('REORDER')),
              const DataColumn(label: Text('STATUS')),
            ],
            rows: visible.map((item) => DataRow(cells: [
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                ProductPhoto(sku: item.sku, size: 52),
                const SizedBox(width: 13),
                SizedBox(width: 170, child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.itemName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(item.sku, style: const TextStyle(fontSize: 10, color: _muted)),
                  ],
                )),
              ])),
              DataCell(Text(item.category, style: const TextStyle(fontSize: 11, color: _muted))),
              DataCell(Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
              DataCell(Text('RM ${item.unitPrice.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
              DataCell(Text('${item.reorderLevel}', style: const TextStyle(fontSize: 11))),
              DataCell(_status(item)),
            ])).toList(),
          ),
        ),
      )),
    ),
  );

  Widget _productCards(List<StockItem> visible) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 450 ? 1 :
      (constraints.maxWidth < 750 ? 2 : 3);
      final width = (constraints.maxWidth - 15 * (columns - 1)) / columns;
      return Wrap(spacing: 15, runSpacing: 15, children: [
        for (final item in visible) SizedBox(
          width: width,
          child: _panel(
            padding: const EdgeInsets.all(15),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 145, width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F6F0),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(child: ProductPhoto(sku: item.sku, size: 130)),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(item.category, style: const TextStyle(fontSize: 10, color: _muted))),
                _status(item),
              ]),
              const SizedBox(height: 9),
              Text(item.itemName, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text(item.sku, style: const TextStyle(color: _muted, fontSize: 10)),
              const SizedBox(height: 15),
              Row(children: [
                Expanded(child: Text('RM ${item.unitPrice.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                Text('${item.quantity} units', style: const TextStyle(
                    fontSize: 11, color: _mint, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text('Reorder level: ${item.reorderLevel}',
                  style: const TextStyle(color: _muted, fontSize: 10)),
            ]),
          ),
        ),
      ]);
    },
  );

  Widget _inventoryBody(List<StockItem> visible) {
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(45),
        child: Center(child: CircularProgressIndicator(color: _mint)),
      );
    }
    if (_readError != null) {
      return _panel(child: Column(children: [
        const Icon(Icons.cloud_off_outlined, color: _muted, size: 35),
        const SizedBox(height: 12),
        Text(_readError!, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh),
            label: const Text('Retry connection')),
      ]));
    }
    if (visible.isEmpty) {
      final empty = _items.isEmpty;
      return _panel(child: Center(child: Column(children: [
        Icon(empty ? Icons.inventory_2_outlined : Icons.search_off_rounded, size: 42, color: _mint),
        const SizedBox(height: 14),
        Text(empty ? 'Your inventory starts here.' : 'No matching products.',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        Text(empty ? 'Add your first item to Cloud Firestore.' : 'Try another keyword or clear your filters.',
            textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 18),
        OutlinedButton(
          onPressed: empty ? () => _goTo(1) : _clearFilters,
          child: Text(empty ? 'Add first item' : 'Clear Filters'),
        ),
      ])));
    }
    if (_grid || MediaQuery.sizeOf(context).width < 750) {
      return _productCards(visible);
    }
    return _table(visible);
  }

  Widget _dashboard() {
    final visible = _visible;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20, runSpacing: 12,
        children: [
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Inventory overview', style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1,
            )),
            SizedBox(height: 6),
            Text('A good day starts with knowing what is in stock.',
                style: TextStyle(color: _muted, fontSize: 12)),
          ]),
        ],
      ),
      const SizedBox(height: 24),
      _hero(),
      const SizedBox(height: 20),
      _stats(),
      const SizedBox(height: 31),
      Row(children: [
        const Expanded(child: Text('Your products', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5,
        ))),
        Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _line),
          ),
          child: Row(children: [
            IconButton(
              tooltip: 'Table view',
              onPressed: () => setState(() => _grid = false),
              icon: Icon(Icons.view_list_outlined, color: !_grid ? _mint : _muted, size: 21),
            ),
            IconButton(
              tooltip: 'Photo cards',
              onPressed: () => setState(() => _grid = true),
              icon: Icon(Icons.grid_view_rounded, color: _grid ? _mint : _muted, size: 19),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      _filters(),
      const SizedBox(height: 15),
      _inventoryBody(visible),
      const SizedBox(height: 15),
      Wrap(spacing: 18, runSpacing: 6, children: [
        Text('Showing ${visible.length} of ${_items.length} saved products',
            style: const TextStyle(color: _muted, fontSize: 10)),
        Text(_cached ? 'Cached data · synchronizing with Firestore' : 'Updated from Cloud Firestore',
            style: const TextStyle(color: _muted, fontSize: 10)),
        if (_pending > 0) Text('$_pending awaiting server confirmation',
            style: const TextStyle(color: _muted, fontSize: 10)),
        if (_invalid > 0) Text('$_invalid existing records have an incompatible schema',
            style: const TextStyle(color: _muted, fontSize: 10)),
      ]),
      const SizedBox(height: 16),
    ]);
  }

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    IconData? icon,
  }) => TextFormField(
    controller: controller,
    enabled: !_saving,
    validator: validator,
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label, hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 18, color: _muted),
    ),
  );

  Widget _formPage() {
    final form = _panel(
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Product details', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          const Text('All six fields are required. Prices are in Malaysian ringgit.',
              style: TextStyle(fontSize: 11, color: _muted, height: 1.6)),
          const SizedBox(height: 26),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth >= 520
                ? (constraints.maxWidth - 15) / 2 : constraints.maxWidth;
            final fields = <Widget>[
              _field(label: 'SKU *', hint: 'STK-101', controller: _sku, icon: Icons.qr_code_2_rounded,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'SKU is required.';
                    return RegExp(r'^STK-[0-9]{3}$').hasMatch(v!.trim())
                        ? null : 'Use STK- followed by exactly three digits.';
                  }),
              _field(label: 'Item name *', hint: 'USB C Cable', controller: _name,
                  validator: (v) => (v ?? '').trim().length >= 3
                      ? null : 'Enter at least 3 characters.'),
              DropdownButtonFormField<String>(
                value: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category *'),
                hint: const Text('Choose category', style: TextStyle(fontSize: 12)),
                items: _categories.map((c) =>
                    DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: _saving ? null : (value) => setState(() => _category = value),
                validator: (value) => _categories.contains(value)
                    ? null : 'Please select a category.',
              ),
              _field(label: 'Quantity *', hint: '4', controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  validator: (v) => _validateInteger(v, 'Quantity')),
              _field(label: 'Unit price (RM) *', hint: '19.90', controller: _price,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'Unit price is required.';
                    final number = double.tryParse(v!.trim());
                    return number != null && number.isFinite && number > 0
                        ? null : 'Enter a valid price greater than 0.';
                  }),
              _field(label: 'Reorder level *', hint: '5', controller: _reorder,
                  keyboardType: const TextInputType.numberWithOptions(signed: true),
                  validator: (v) => _validateInteger(v, 'Reorder level')),
            ];
            return Wrap(spacing: 15, runSpacing: 19, children: [
              for (final field in fields) SizedBox(width: width, child: field),
            ]);
          }),
          const SizedBox(height: 19),
          const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 16, color: _muted),
            SizedBox(width: 8),
            Expanded(child: Text(
              'An item is flagged as low stock when its quantity is at or below its reorder level.',
              style: TextStyle(fontSize: 11, color: _muted, height: 1.6),
            )),
          ]),
          if (_saveError != null) ...[
            const SizedBox(height: 16),
            Text(_saveError!, style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
          ],
          if (_saveNotice != null) ...[
            const SizedBox(height: 16),
            Text(_saveNotice!, style: const TextStyle(color: _mint, fontSize: 12)),
          ],
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Divider(height: 1)),
          Wrap(spacing: 12, runSpacing: 12, children: [
            FilledButton.icon(
              onPressed: _saving ? null : _saveItem,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_rounded, size: 19),
              label: Text(_saving ? 'Saving…' : 'Save Item'),
            ),
            OutlinedButton(onPressed: _saving ? null : _clearForm, child: const Text('Clear form')),
            TextButton(onPressed: _saving ? null : () => _goTo(0), child: const Text('Back to inventory')),
          ]),
        ]),
      ),
    );
    final guide = _panel(
      color: const Color(0xFFE7EFDF),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('A place for every product.', style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.2,
        )),
        const SizedBox(height: 18),
        const Center(child: ProductPhoto(sku: 'STK-103', size: 160)),
        const SizedBox(height: 18),
        const Text('A few useful details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _tip('01', 'Use a clear product name.'),
        _tip('02', 'Keep quantities as whole numbers.'),
        _tip('03', 'Set a reorder level that suits your stock.'),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Add a new item', style: TextStyle(
        fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -1,
      )),
      const SizedBox(height: 7),
      const Text('A new product, with everything in the right place.',
          style: TextStyle(fontSize: 12, color: _muted)),
      const SizedBox(height: 27),
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 960) return form;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: form),
          const SizedBox(width: 19),
          Expanded(child: guide),
        ]);
      }),
    ]);
  }

  Widget _tip(String number, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(number, style: const TextStyle(color: _mint, fontSize: 10, fontWeight: FontWeight.w800)),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: _muted, fontSize: 11, height: 1.6))),
    ]),
  );

  Widget _panel({required Widget child, EdgeInsets? padding, Color color = Colors.white}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(25),
        decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _line),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: wide ? null : AppBar(
        backgroundColor: _bg,
        title: _brand(),
        actions: [Padding(padding: const EdgeInsets.only(right: 15), child: _connectionPill())],
      ),
      drawer: wide ? null : Drawer(width: 228, child: _sidebar(true)),
      body: Row(children: [
        if (wide) _sidebar(false),
        Expanded(child: SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 30 : 17),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1370),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (wide) _topbar(),
                _page == 0 ? _dashboard() : _formPage(),
              ]),
            ),
          ),
        )),
      ]),
    );
  }
}

class ProductPhoto extends StatelessWidget {
  const ProductPhoto({super.key, required this.sku, required this.size});
  final String sku;
  final double size;

  static const _assets = {
    'STK-101': 'assets/images/cable.jpg',
    'STK-102': 'assets/images/notebook.jpg',
    'STK-103': 'assets/images/mouse.jpg',
  };

  Widget _placeholder() => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFEEF3EA), borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(Icons.inventory_2_outlined, color: _mint, size: size * 0.38),
  );

  @override
  Widget build(BuildContext context) {
    final asset = _assets[sku];
    if (asset == null) return _placeholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        asset, width: size, height: size, fit: BoxFit.contain,
        errorBuilder: (context, error, stack) {
          if (sku == 'STK-101') {
            return Image.asset(
              'assets/images/cabel.jpg', width: size, height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
          }
          return _placeholder();
        },
      ),
    );
  }
}
