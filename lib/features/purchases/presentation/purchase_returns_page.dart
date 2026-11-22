import 'package:material_ui/material_ui.dart';

import '../data/purchase_return_repository.dart';

class PurchaseReturnsPage extends StatefulWidget {
  const PurchaseReturnsPage({super.key});

  @override
  State<PurchaseReturnsPage> createState() => _PurchaseReturnsPageState();
}

class _PurchaseReturnsPageState extends State<PurchaseReturnsPage> {
  final _repository = PurchaseReturnRepository();
  late Future<List<Map<String, Object?>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repository.getReturns();
  }

  String _money(Object? value) {
    final amount = value is num ? value.toInt() : 0;
    final digits = amount.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return 'Rp$out';
  }

  Future<void> _reload() async {
    final next = _repository.getReturns();
    setState(() => _future = next);
    await next;
  }

  Future<void> _createReturn() async {
    final purchases = await _repository.getPurchases();
    if (!mounted) return;
    if (purchases.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada faktur pembelian yang dapat diretur.')),
      );
      return;
    }
    int? purchaseId = purchases.first['id'] as int;
    var itemsFuture = _repository.getReturnableItems(purchaseId);
    final quantities = <int, int>{};
    final notes = TextEditingController();
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Buat Retur Pembelian'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<int>(
                    value: purchaseId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Pilih faktur pembelian'),
                    items: purchases.map((p) => DropdownMenuItem<int>(
                      value: p['id'] as int,
                      child: Text('${p['invoice_number']} • ${p['supplier_name'] ?? 'Pemasok'}',
                        overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        purchaseId = value;
                        quantities.clear();
                        itemsFuture = _repository.getReturnableItems(value);
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, Object?>>>(
                    future: itemsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (snapshot.hasError) return Text('Gagal memuat barang: ${snapshot.error}');
                      final rows = snapshot.data ?? [];
                      if (rows.isEmpty) return const Text('Tidak ada barang pada faktur ini.');
                      return Column(
                        children: rows.map((item) {
                          final id = item['purchase_item_id'] as int;
                          final bought = item['purchased_quantity'] as int? ?? 0;
                          final returned = item['returned_quantity'] as int? ?? 0;
                          final available = bought - returned;
                          final current = quantities[id] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item['product_name'] as String? ?? '-',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                      Text('Beli $bought • Sudah retur $returned • Sisa $available',
                                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 68,
                                  child: TextFormField(
                                    key: ValueKey('return-$id-$available'),
                                    initialValue: current == 0 ? '' : current.toString(),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      labelText: 'Retur',
                                      hintText: '0',
                                      isDense: true,
                                    ),
                                    onChanged: (value) {
                                      final parsed = int.tryParse(value) ?? 0;
                                      quantities[id] = parsed.clamp(0, available).toInt();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Catatan retur (opsional)'),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Retur akan mengurangi stok yang tercatat. Pengembalian uang atau potongan utang pemasok dicatat terpisah setelah dikonfirmasi.',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final selected = Map<int, int>.from(quantities)..removeWhere((_, q) => q <= 0);
                if (selected.isNotEmpty && purchaseId != null) {
                  Navigator.pop(dialogContext, {
                    'purchase_id': purchaseId,
                    'quantities': selected,
                    'notes': notes.text,
                  });
                }
              },
              child: const Text('Simpan Retur'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
    if (result == null || !mounted) return;
    try {
      final number = 'RB-${DateTime.now().millisecondsSinceEpoch}';
      await _repository.createReturn(
        purchaseId: result['purchase_id'] as int,
        returnNumber: number,
        quantities: result['quantities'] as Map<int, int>,
        notes: result['notes'] as String?,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retur $number berhasil dicatat.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Retur gagal: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur Pembelian'),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createReturn,
        icon: const Icon(Icons.assignment_return),
        label: const Text('Buat Retur'),
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('Gagal memuat retur: ${snapshot.error}'));
          final rows = snapshot.data ?? [];
          if (rows.isEmpty) return const Center(child: Text('Belum ada retur pembelian.'));
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final row = rows[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    leading: const CircleAvatar(
                      radius: 18,
                      child: Icon(Icons.assignment_return, size: 19),
                    ),
                    title: Text(row['return_number'] as String? ?? '-',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Faktur ${row['invoice_number']} • ${row['supplier_name'] ?? 'Pemasok'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Text(_money(row['total_amount']),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
