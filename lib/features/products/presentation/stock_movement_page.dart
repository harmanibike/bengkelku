import 'package:flutter/material.dart';

import '../data/product_repository.dart';

class StockMovementPage extends StatefulWidget {
  const StockMovementPage({super.key});

  @override
  State<StockMovementPage> createState() => _StockMovementPageState();
}

class _StockMovementPageState extends State<StockMovementPage> {
  final _repository = ProductRepository();
  final _search = TextEditingController();
  String _type = 'all';
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, Object?>>> _load() => _repository.getStockMovements(
    keyword: _search.text,
    movementType: _type,
  );

  void _refresh() => setState(() => _future = _load());

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return value?.toString() ?? '';
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    final hour = parsed.hour.toString().padLeft(2, '0');
    final minute = parsed.minute.toString().padLeft(2, '0');
    return '$day/$month/${parsed.year} $hour:$minute';
  }

  String _reference(Object? value) {
    switch (value?.toString()) {
      case 'purchase': return 'Pembelian';
      case 'purchase_return': return 'Retur pembelian';
      case 'purchase_cancel': return 'Pembatalan pembelian';
      case 'sale': return 'Penjualan';
      case 'sale_cancel': return 'Pembatalan penjualan';
      case 'manual_adjustment': return 'Penyesuaian manual';
      case 'initial_stock': return 'Stok awal';
      case 'service': return 'Servis';
      default: return value?.toString().replaceAll('_', ' ') ?? 'Pergerakan stok';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Stok')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: TextField(
              controller: _search,
              onChanged: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Cari produk, varian, SKU, atau keterangan',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Bersihkan pencarian',
                  onPressed: () { _search.clear(); _refresh(); },
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('Semua')),
                ButtonSegment(value: 'in', label: Text('Masuk')),
                ButtonSegment(value: 'out', label: Text('Keluar')),
              ],
              selected: {_type},
              onSelectionChanged: (value) {
                setState(() { _type = value.first; _future = _load(); });
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Gagal memuat riwayat stok: ${snapshot.error}'));
                }
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) return const Center(child: Text('Belum ada riwayat pergerakan stok.'));
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final incoming = row['movement_type']?.toString() == 'in';
                      final qty = (row['quantity'] as num?)?.toInt() ?? 0;
                      final before = (row['stock_before'] as num?)?.toInt() ?? 0;
                      final after = (row['stock_after'] as num?)?.toInt() ?? 0;
                      final unit = row['product_unit']?.toString() ?? 'pcs';
                      final notes = row['notes']?.toString();
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        leading: CircleAvatar(
                          radius: 17,
                          backgroundColor: incoming ? Colors.green.withValues(alpha: .12) : Colors.red.withValues(alpha: .10),
                          child: Icon(incoming ? Icons.south_west : Icons.north_east, color: incoming ? Colors.green : Colors.red, size: 18),
                        ),
                        title: Text([row['product_name'], row['variant_name']].where((value) => value != null && value.toString().isNotEmpty).join(' - '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                          '${_reference(row['reference_type'])} • ${_date(row['created_at'])}\nStok: $before → $after $unit${notes == null || notes.isEmpty ? '' : '\n$notes'}',
                          style: const TextStyle(fontSize: 11, height: 1.35),
                        ),
                        isThreeLine: true,
                        trailing: Text(
                          '${incoming ? '+' : '-'}$qty $unit',
                          textAlign: TextAlign.end,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: incoming ? Colors.green : Colors.red),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text('Menampilkan maksimal 300 pergerakan terbaru.', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}
