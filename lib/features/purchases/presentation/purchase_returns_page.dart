import 'package:material_ui/material_ui.dart';

import '../../../core/formatters/currency_input_formatter.dart';

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

  Future<void> _applyCredit(Map<String, Object?> row) async {
    final returnId = row['id'] as int;
    final total = (row['total_amount'] as num?)?.toInt() ?? 0;
    final applied = (row['credit_applied'] as num?)?.toInt() ?? 0;
    final refunded = (row['refund_received'] as num?)?.toInt() ?? 0;
    final available = total - applied - refunded;
    if (available <= 0) return;
    final invoices = await _repository.getCreditTargetInvoices(returnId);
    if (!mounted) return;
    if (invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pemasok ini belum memiliki faktur dengan sisa utang.')),
      );
      return;
    }
    int? purchaseId = invoices.first['id'] as int;
    final maxAmount = (invoices.first['remaining_amount'] as num?)?.toInt() ?? 0;
    final amountController = TextEditingController(
      text: formatCurrencyInput(available < maxAmount ? available : maxAmount),
    );
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gunakan Kredit Pemasok'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Saldo kredit tersedia: ${_money(available)}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: purchaseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Faktur tujuan', isDense: true),
                items: invoices.map((invoice) => DropdownMenuItem<int>(
                  value: invoice['id'] as int,
                  child: Text(
                    '${invoice['invoice_number']} • Sisa ${_money(invoice['remaining_amount'])}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                )).toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setDialogState(() {
                    purchaseId = value;
                    final target = invoices.firstWhere((item) => item['id'] == value);
                    final remaining = (target['remaining_amount'] as num?)?.toInt() ?? 0;
                    amountController.text = formatCurrencyInput(available < remaining ? available : remaining);
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                inputFormatters: const [CurrencyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Jumlah kredit yang digunakan',
                  prefixText: 'Rp ',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kredit hanya dapat digunakan untuk faktur milik pemasok yang sama. Tidak ada uang kas yang keluar.',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                final amount = parseCurrencyInput(amountController.text);
                if (purchaseId != null && amount > 0) {
                  Navigator.pop(dialogContext, {'purchase_id': purchaseId!, 'amount': amount});
                }
              },
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    if (result == null || !mounted) return;
    try {
      await _repository.applyReturnCredit(
        returnId: returnId,
        purchaseId: result['purchase_id']!,
        amount: result['amount']!,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kredit berhasil diterapkan ke faktur pemasok.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kredit gagal diterapkan: $error')),
        );
      }
    }
  }

  Future<void> _cancelReturn(Map<String, Object?> row) async {
    if (row['status']?.toString() == 'cancelled') return;
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batalkan Retur Pembelian'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nomor retur: ${row['return_number']}'),
            const SizedBox(height: 8),
            const Text(
              'Retur hanya dapat dibatalkan jika belum digunakan sebagai kredit pemasok atau menerima pengembalian uang. Stok akan dikembalikan ke batch asal dan riwayat tetap disimpan.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alasan pembatalan *',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final value = reasonController.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Batalkan Retur'),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || !mounted) return;
    try {
      await _repository.cancelReturn(
        returnId: row['id'] as int,
        reason: reason,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retur dibatalkan dan stok dikembalikan ke batch asal.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pembatalan ditolak: $error')),
        );
      }
    }
  }

  Future<void> _settleReturn(Map<String, Object?> row) async {
    if (row['status']?.toString() == 'cancelled') return;
    final total = (row['total_amount'] as num?)?.toInt() ?? 0;
    final applied = (row['credit_applied'] as num?)?.toInt() ?? 0;
    final refunded = (row['refund_received'] as num?)?.toInt() ?? 0;
    final pending = total - applied - refunded;
    if (pending <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nilai retur ini sudah diselesaikan seluruhnya.')),
      );
      return;
    }
    final creditController = TextEditingController();
    final refundController = TextEditingController();
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Penyelesaian ${row['return_number']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nilai retur: ${_money(total)}', style: const TextStyle(fontSize: 12)),
            Text('Belum diselesaikan: ${_money(pending)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
            const SizedBox(height: 10),
            TextField(
              controller: creditController,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Kredit untuk mengurangi utang faktur',
                prefixText: 'Rp ',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: refundController,
              keyboardType: TextInputType.number,
              inputFormatters: const [CurrencyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Uang yang benar-benar diterima',
                prefixText: 'Rp ',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Isi sesuai kesepakatan pemasok. Kredit mengurangi sisa utang faktur; uang kembali baru masuk kas setelah benar-benar diterima.',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final credit = parseCurrencyInput(creditController.text);
              final refund = parseCurrencyInput(refundController.text);
              if (credit >= 0 && refund >= 0 && credit + refund > 0 && credit + refund <= pending) {
                Navigator.pop(dialogContext, {'credit': credit, 'refund': refund});
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    creditController.dispose();
    refundController.dispose();
    if (result == null || !mounted) return;
    try {
      await _repository.settleReturn(
        returnId: row['id'] as int,
        creditApplied: result['credit']!,
        refundReceived: result['refund']!,
      );
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Penyelesaian retur berhasil dicatat.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Penyelesaian gagal: $error')),
        );
      }
    }
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
                    initialValue: purchaseId,
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
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Faktur ${row['invoice_number']} • ${row['supplier_name'] ?? 'Pemasok'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        if (row['status']?.toString() == 'cancelled')
                          Text('DIBATALKAN • ${row['cancel_reason'] ?? '-'}', style: const TextStyle(fontSize: 10, color: Colors.red)),
                        if (row['status']?.toString() != 'cancelled' && ((row['total_amount'] as num?)?.toInt() ?? 0) -
                            ((row['credit_applied'] as num?)?.toInt() ?? 0) -
                            ((row['refund_received'] as num?)?.toInt() ?? 0) > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => _applyCredit(row),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
                                minimumSize: const Size(0, 26),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.account_balance_wallet_outlined, size: 14),
                              label: const Text('Gunakan saldo kredit', style: TextStyle(fontSize: 10)),
                            ),
                          ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_money(row['total_amount']),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text(row['status']?.toString() == 'cancelled' ? 'Dibatalkan' : 'Sisa ${_money(((row['total_amount'] as num?)?.toInt() ?? 0) - ((row['credit_applied'] as num?)?.toInt() ?? 0) - ((row['refund_received'] as num?)?.toInt() ?? 0))}',
                          style: TextStyle(fontSize: 9, color: row['status']?.toString() == 'cancelled' ? Colors.red : Colors.deepOrange)),
                        if (row['status']?.toString() != 'cancelled')
                          TextButton(
                            onPressed: () => _cancelReturn(row),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 22), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            child: const Text('Batalkan', style: TextStyle(fontSize: 10, color: Colors.red)),
                          ),
                      ],
                    ),
                    onTap: () => _settleReturn(row),
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
