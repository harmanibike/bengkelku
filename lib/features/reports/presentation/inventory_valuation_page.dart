import 'package:material_ui/material_ui.dart';

import '../data/report_repository.dart';

class InventoryValuationPage extends StatefulWidget {
  const InventoryValuationPage({super.key});

  @override
  State<InventoryValuationPage> createState() => _InventoryValuationPageState();
}

class _InventoryValuationPageState extends State<InventoryValuationPage> {
  final ReportRepository _repository = ReportRepository();
  final TextEditingController _search = TextEditingController();
  late Future<List<Map<String, Object?>>> _future;
  String _category = 'Semua kategori';
  String _sort = 'value_desc';
  bool _showZeroStock = false;

  @override
  void initState() {
    super.initState();
    _future = _repository.getCurrentStockValuationItems();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = _repository.getCurrentStockValuationItems());
    await _future;
  }

  int _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

  String _rupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp$buffer';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rincian Nilai Persediaan'),
        actions: [
          IconButton(tooltip: 'Muat ulang', onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Gagal memuat rincian persediaan: ${snapshot.error}', textAlign: TextAlign.center),
            ));
          }

          final allItems = snapshot.data ?? <Map<String, Object?>>[];
          final categories = allItems
              .map((item) => item['category']?.toString() ?? 'Lainnya')
              .toSet()
              .toList()
            ..sort();
          final categoryOptions = ['Semua kategori', ...categories];
          if (!categoryOptions.contains(_category)) _category = 'Semua kategori';

          final query = _search.text.trim().toLowerCase();
          final items = allItems.where((item) {
            final name = item['product_name']?.toString().toLowerCase() ?? '';
            final sku = item['sku']?.toString().toLowerCase() ?? '';
            final category = item['category']?.toString() ?? 'Lainnya';
            final stock = _int(item['stock']);
            return (query.isEmpty || name.contains(query) || sku.contains(query)) &&
                (_category == 'Semua kategori' || category == _category) &&
                (_showZeroStock || stock > 0);
          }).toList();

          items.sort((left, right) {
            final leftValue = _int(left['cost_value']);
            final rightValue = _int(right['cost_value']);
            if (_sort == 'value_asc') return leftValue.compareTo(rightValue);
            if (_sort == 'name') {
              return (left['product_name']?.toString() ?? '')
                  .toLowerCase().compareTo((right['product_name']?.toString() ?? '').toLowerCase());
            }
            if (_sort == 'stock') return _int(right['stock']).compareTo(_int(left['stock']));
            return rightValue.compareTo(leftValue);
          });

          final totalStock = items.fold<int>(0, (sum, item) => sum + _int(item['stock']));
          final totalValue = items.fold<int>(0, (sum, item) => sum + _int(item['cost_value']));

          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Total nilai modal sesuai filter', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(_rupiah(totalValue), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Color(0xFF1565C0))),
                      const SizedBox(height: 4),
                      Text('${items.length} jenis barang • $totalStock unit stok', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cari nama barang atau SKU',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder(), isDense: true),
                  items: categoryOptions.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                  onChanged: (value) => setState(() => _category = value ?? 'Semua kategori'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: 'Urutkan', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'value_desc', child: Text('Nilai modal tertinggi')),
                    DropdownMenuItem(value: 'value_asc', child: Text('Nilai modal terendah')),
                    DropdownMenuItem(value: 'name', child: Text('Nama barang A–Z')),
                    DropdownMenuItem(value: 'stock', child: Text('Stok terbanyak')),
                  ],
                  onChanged: (value) => setState(() => _sort = value ?? 'value_desc'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _showZeroStock,
                  title: const Text('Tampilkan barang stok 0'),
                  onChanged: (value) => setState(() => _showZeroStock = value ?? false),
                ),
                const SizedBox(height: 4),
                if (items.isEmpty)
                  const Card(child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Center(child: Text('Tidak ada barang yang cocok dengan filter.')),
                  ))
                else
                  ...items.map((item) {
                    final stock = _int(item['stock']);
                    final costValue = _int(item['cost_value']);
                    final fallback = _int(item['fallback_unit_cost']);
                    final unitCost = stock > 0 ? (costValue / stock).round() : fallback;
                    final sku = item['sku']?.toString() ?? '';
                    final unit = item['unit']?.toString() ?? 'unit';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 7),
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(item['product_name']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 3),
                          Text('${sku.isEmpty ? 'Tanpa SKU' : sku} • ${item['category'] ?? 'Lainnya'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const Divider(height: 14),
                          Row(children: [
                            Expanded(child: Text('Stok: $stock $unit', style: const TextStyle(fontSize: 12))),
                            Expanded(child: Text('Modal/unit: ${_rupiah(unitCost)}', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12))),
                          ]),
                          const SizedBox(height: 5),
                          Row(children: [
                            const Expanded(child: Text('Nilai persediaan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                            Text(_rupiah(costValue), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1565C0))),
                          ]),
                        ]),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                const Text('Catatan: nilai modal dihitung dari sisa batch biaya yang tersedia. Jika jumlah batch belum mencukupi stok, selisih memakai harga pokok pada data barang.', style: TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          );
        },
      ),
    );
  }
}
