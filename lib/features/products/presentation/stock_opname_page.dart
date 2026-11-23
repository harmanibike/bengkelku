import 'package:flutter/material.dart';

import '../data/stock_opname_repository.dart';

class StockOpnamePage extends StatefulWidget {
  const StockOpnamePage({super.key});

  @override
  State<StockOpnamePage> createState() => _StockOpnamePageState();
}

class _StockOpnamePageState extends State<StockOpnamePage> {
  final _repo = StockOpnameRepository();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getSessions();
  }

  Future<void> _refresh() async {
    final future = _repo.getSessions();
    setState(() => _future = future);
    await future;
  }

  Future<void> _create() async {
    try {
      final id = await _repo.createSession();
      final items = await _repo.getItems(id);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) =>
        _OpnameDetailPage(sessionId: id, items: items, repo: _repo)));
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _open(Map<String, Object?> row) async {
    final id = row['id'] as int;
    final items = await _repo.getItems(id);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      _OpnameDetailPage(
        sessionId: id,
        items: items,
        repo: _repo,
        applied: row['status'] == 'applied',
        title: row['opname_number']?.toString() ?? 'Stok Opname',
      )));
    if (mounted) _refresh();
  }

  Future<void> _deleteDraft(Map<String, Object?> row) async {
    final number = row['opname_number']?.toString() ?? 'sesi ini';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan sesi draft?'),
        content: Text('Sesi $number dan hitungan yang tersimpan akan dihapus. Stok produk tidak berubah.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Kembali')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Batalkan sesi')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteDraft(row['id'] as int);
      if (mounted) await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stok Opname')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.playlist_add_check),
      label: const Text('Opname Baru'),
    ),
    body: FutureBuilder<List<Map<String, Object?>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Gagal memuat: ${snapshot.error}'));
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: Text('Belum ada sesi stok opname.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 84),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final done = row['status'] == 'applied';
              final total = (row['item_count'] as num?)?.toInt() ?? 0;
              final count = (row['counted_count'] as num?)?.toInt() ?? 0;
              final surplus = (row['total_surplus'] as num?)?.toInt() ?? 0;
              final shortage = (row['total_shortage'] as num?)?.toInt() ?? 0;
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Icon(
                  done ? Icons.check_circle : Icons.fact_check,
                  color: done ? Colors.green : Colors.orange,
                ),
                title: Text(
                  row['opname_number']?.toString() ?? 'Opname',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '$count/$total dihitung • Lebih: +$surplus • Kurang: -$shortage',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      done ? 'Selesai' : 'Draft',
                      style: TextStyle(
                        fontSize: 11,
                        color: done ? Colors.green : Colors.orange,
                      ),
                    ),
                    if (!done)
                      IconButton(
                        tooltip: 'Batalkan draft',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _deleteDraft(row),
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                  ],
                ),
                onTap: () => _open(row),
              );
            },
          ),
        );
      },
    ),
  );
}

class _OpnameDetailPage extends StatefulWidget {
  const _OpnameDetailPage({
    required this.sessionId,
    required this.items,
    required this.repo,
    this.applied = false,
    this.title = 'Detail Stok Opname',
  });

  final int sessionId;
  final List<Map<String, Object?>> items;
  final StockOpnameRepository repo;
  final bool applied;
  final String title;

  @override
  State<_OpnameDetailPage> createState() => _OpnameDetailPageState();
}

class _OpnameDetailPageState extends State<_OpnameDetailPage> {
  late List<Map<String, Object?>> _items;
  final Map<int, TextEditingController> _controllers = {};
  final TextEditingController _searchController = TextEditingController();
  bool _busy = false;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    for (final item in _items) {
      final id = item['id'] as int;
      _controllers[id] = TextEditingController(
        text: item['counted_quantity']?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, Object?>> get _filteredItems {
    final keyword = _keyword.trim().toLowerCase();
    if (keyword.isEmpty) return _items;
    return _items.where((item) {
      final values = [
        item['product_name'],
        item['sku'],
        item['barcode'],
      ];
      return values.any((value) =>
        value?.toString().toLowerCase().contains(keyword) ?? false);
    }).toList();
  }

  Future<void> _save(int id) async {
    final qty = int.tryParse(_controllers[id]!.text.trim());
    if (qty == null || qty < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jumlah fisik yang valid.')));
      return;
    }
    try {
      await widget.repo.setCount(id, qty);
      final refreshed = await widget.repo.getItems(widget.sessionId);
      if (mounted) setState(() => _items = refreshed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _apply() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terapkan hasil opname?'),
        content: const Text(
          'Stok sistem akan disesuaikan dengan jumlah fisik. '
          'Perubahan dicatat pada Audit Stok.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Periksa lagi')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Terapkan')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.repo.applySession(widget.sessionId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final counted = _items.where((e) => e['counted_quantity'] != null).length;
    final surplus = _items.fold<int>(0, (sum, item) {
      final variance = item['variance'] as int? ?? 0;
      return sum + (variance > 0 ? variance : 0);
    });
    final shortage = _items.fold<int>(0, (sum, item) {
      final variance = item['variance'] as int? ?? 0;
      return sum + (variance < 0 ? -variance : 0);
    });
    final visibleItems = _filteredItems;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: widget.applied
        ? null
        : SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: FilledButton.icon(
                onPressed: _busy || counted != _items.length ? null : _apply,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_busy
                  ? 'Menerapkan…'
                  : 'Terapkan Penyesuaian ($counted/${_items.length})'),
              ),
            ),
          ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _keyword = value),
              decoration: InputDecoration(
                hintText: 'Cari nama, SKU, atau barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _keyword.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Hapus pencarian',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _keyword = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                Text('Dihitung $counted/${_items.length}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('Lebih +$surplus',
                  style: const TextStyle(fontSize: 11, color: Colors.green)),
                const SizedBox(width: 10),
                Text('Kurang -$shortage',
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visibleItems.isEmpty
              ? const Center(child: Text('Produk tidak ditemukan.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: visibleItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    final id = item['id'] as int;
                    final system = (item['system_quantity'] as num?)?.toInt() ?? 0;
                    final controller = _controllers[id]!;
                    final countedQty = int.tryParse(controller.text);
                    final variance = countedQty == null ? null : countedQty-system;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['product_name']?.toString() ?? '-',
                                  style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'SKU: ${item['sku'] ?? '-'} • Barcode: ${item['barcode'] ?? '-'}',
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                                Text(
                                  'Sistem: $system ${item['unit'] ?? 'pcs'}'
                                  '${variance == null ? '' : ' • Selisih: ${variance > 0 ? '+' : ''}$variance'}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 82,
                            child: TextField(
                              controller: controller,
                              enabled: !widget.applied,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                labelText: 'Fisik',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 9),
                              ),
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _save(id),
                            ),
                          ),
                          if (!widget.applied)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Simpan hitungan',
                              onPressed: () => _save(id),
                              icon: const Icon(Icons.save_outlined, size: 20),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
