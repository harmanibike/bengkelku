import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../services/data/service_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../purchases/data/purchase_repository.dart';
import '../../reports/data/cashbook_repository.dart';

class TransactionCleanupPage extends StatefulWidget {
  const TransactionCleanupPage({super.key});

  @override
  State<TransactionCleanupPage> createState() => _TransactionCleanupPageState();
}

class _TransactionCleanupPageState extends State<TransactionCleanupPage> {
  final _repository = ServiceRepository();
  final _saleRepository = SaleRepository();
  final _purchaseRepository = PurchaseRepository();
  final _cashbookRepository = CashbookRepository();
  final Set<int> _selected = {};
  final Set<int> _selectedSales = {};
  final Set<int> _selectedCancelledSales = {};
  final Set<int> _selectedPurchases = {};
  final Set<int> _selectedCash = {};
  List<Map<String, Object?>> _orders = [];
  List<Map<String, Object?>> _sales = [];
  List<Map<String, Object?>> _cancelledSales = [];
  List<Map<String, Object?>> _purchases = [];
  List<Map<String, Object?>> _manualCash = [];
  bool _loading = true;
  bool _working = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthSession.instance.isAdmin) {
      setState(() {
        _loading = false;
        _error = 'Menu ini hanya dapat diakses Admin.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
      _selectedSales.clear();
      _selectedCancelledSales.clear();
      _selectedPurchases.clear();
      _selectedCash.clear();
    });
    try {
      final results = await Future.wait([
        _repository.getServiceOrders(),
        _saleRepository.getSales(),
        _purchaseRepository.getPurchases(),
        _cashbookRepository.getManualCashCandidates(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0].where((row) => row['service_status']?.toString() == 'waiting').toList();
        _sales = results[1].where((row) => row['payment_status']?.toString() == 'unpaid').toList();
        _cancelledSales = results[1].where((row) => row['payment_status']?.toString() == 'cancelled').toList();
        _purchases = results[2].where((row) => row['status']?.toString() != 'cancelled' && (row['paid'] as num? ?? 0) == 0 && (row['return_credit'] as num? ?? 0) == 0).toList();
        _manualCash = results[3];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
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

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty || _working) return;
    final ids = _selected.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus nota servis percobaan terpilih?'),
        content: Text(
          'Anda memilih ${ids.length} nota yang masih menunggu. Pastikan ini nota percobaan, bukan sepeda pelanggan yang benar-benar sudah diterima. Penghapusan hanya berhasil untuk nota tanpa pembayaran, saldo pelanggan, tip, pergerakan stok, batch biaya, riwayat audit, atau arsip nota.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus yang aman'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    var deleted = 0;
    final failures = <String>[];
    for (final id in ids) {
      try {
        deleted += await _repository.deleteServiceOrder(id);
      } catch (error) {
        failures.add('Nota #$id: $error');
      }
    }
    if (!mounted) return;
    setState(() => _working = false);
    await _load();
    if (!mounted) return;
    final message = failures.isEmpty
        ? '$deleted nota servis berhasil dihapus.'
        : '$deleted nota dihapus; ${failures.length} nota ditolak karena masih memiliki keterkaitan.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (failures.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sebagian nota tidak dapat dihapus'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Text(failures.join('\n\n')),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _deleteSelectedSales() async {
    if (_selectedSales.isEmpty || _working) return;
    final ids = _selectedSales.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus penjualan percobaan terpilih?'),
        content: Text('Anda memilih ${ids.length} transaksi belum dibayar. Pastikan semuanya benar-benar transaksi percobaan, bukan penjualan asli yang belum dibayar. Transaksi dengan pembayaran, retur, catatan saldo/poin, atau arsip nota akan ditolak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus yang aman'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    var deleted = 0;
    final failures = <String>[];
    for (final id in ids) {
      try { deleted += await _saleRepository.deleteDummySale(id); }
      catch (error) { failures.add('Penjualan #$id: $error'); }
    }
    if (!mounted) return;
    setState(() => _working = false);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failures.isEmpty
      ? '$deleted transaksi penjualan berhasil dihapus.'
      : '$deleted transaksi dihapus; ${failures.length} ditolak karena masih terkait data penting.')));
  }

  Future<void> _deleteSelectedCancelledSales() async {
    if (_selectedCancelledSales.isEmpty || _working) return;
    final ids = _selectedCancelledSales.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus riwayat penjualan dibatalkan?'),
        content: Text(
          'Anda memilih ${ids.length} nota berstatus Dibatalkan. Pastikan nota tersebut hanya transaksi percobaan. Penghapusan tidak mengubah stok karena stok sudah dikembalikan saat pembatalan. Nota yang memiliki pembayaran/pengembalian, retur, saldo pelanggan, poin, tip, atau arsip nota akan ditolak.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus permanen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    var deleted = 0;
    final failures = <String>[];
    for (final id in ids) {
      try {
        deleted += await _saleRepository.deleteCancelledDummySale(id);
      } catch (error) {
        failures.add('Penjualan #$id: $error');
      }
    }
    if (!mounted) return;
    setState(() => _working = false);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failures.isEmpty
        ? '$deleted riwayat penjualan dibatalkan berhasil dihapus.'
        : '$deleted riwayat dihapus; ${failures.length} ditolak karena masih terkait data penting.'),
    ));
    if (failures.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sebagian riwayat tidak dapat dihapus'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Text(failures.join('\\n\\n')))),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup'))],
        ),
      );
    }
  }

  Future<void> _deleteSelectedCash() async {
    if (_selectedCash.isEmpty || _working) return;
    final ids = _selectedCash.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus transaksi kas manual terpilih?'),
        content: Text('Anda memilih ${ids.length} transaksi kas manual. Pastikan semuanya hanya data percobaan. Hanya kas masuk/keluar manual yang dihapus; transaksi dari penjualan, pembelian, servis, retur, deposit, dan tip tidak ditampilkan atau dihapus di sini. Saldo dan laporan akan dihitung ulang dari transaksi tersisa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Kembali')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hapus permanen')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    var deleted = 0;
    final failures = <String>[];
    for (final id in ids) {
      try { deleted += await _cashbookRepository.deleteDummyManualCash(id); }
      catch (error) { failures.add('Kas #$id: $error'); }
    }
    if (!mounted) return;
    setState(() => _working = false);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failures.isEmpty
      ? '$deleted transaksi kas manual berhasil dihapus.'
      : '$deleted transaksi dihapus; ${failures.length} ditolak.')));
    if (failures.isNotEmpty) {
      await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
        title: const Text('Sebagian transaksi kas tidak dapat dihapus'),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Text(failures.join('\\n\\n')))),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup'))],
      ));
    }
  }

  Future<void> _deleteSelectedPurchases() async {
    if (_selectedPurchases.isEmpty || _working) return;
    final ids = _selectedPurchases.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus pembelian percobaan terpilih?'),
        content: Text('Anda memilih ${ids.length} faktur tanpa pembayaran dan kredit retur. Pastikan faktur ini benar-benar percobaan, bukan pembelian asli yang belum dibayar. Sistem akan memeriksa retur, batch biaya, stok, dan arsip nota sebelum penghapusan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus yang aman'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = true);
    var deleted = 0;
    final failures = <String>[];
    for (final id in ids) {
      try { deleted += await _purchaseRepository.deleteDummyPurchase(purchaseId: id); }
      catch (error) { failures.add('Pembelian #$id: $error'); }
    }
    if (!mounted) return;
    setState(() => _working = false);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failures.isEmpty
      ? '$deleted faktur pembelian berhasil dihapus.'
      : '$deleted faktur dihapus; ${failures.length} ditolak karena masih terkait data penting.')));
    if (failures.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Sebagian faktur tidak dapat dihapus'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: Text(failures.join('\\n\\n')))),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pemeliharaan Data')),
        body: const Center(child: Text('Menu ini hanya dapat diakses Admin.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pemeliharaan Data'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _working ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Daftar ini hanya menampilkan kandidat yang belum dibayar atau masih menunggu. Status tersebut bukan bukti bahwa transaksi adalah dummy. Pilih hanya transaksi percobaan yang memang ingin dihapus. Transaksi dengan pembayaran, retur, pergerakan stok, saldo, tip, riwayat, atau arsip akan dilindungi.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                        children: [
                          Row(children: [
                            const Expanded(child: Text('Riwayat penjualan dibatalkan', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selectedCancelledSales.length} dipilih', style: const TextStyle(fontSize: 11)),
                            IconButton(
                              tooltip: 'Hapus riwayat dibatalkan terpilih',
                              onPressed: _selectedCancelledSales.isEmpty || _working ? null : _deleteSelectedCancelledSales,
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                            ),
                          ]),
                          if (_cancelledSales.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 14),
                              child: Text('Tidak ada riwayat penjualan dibatalkan.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            )
                          else
                            ..._cancelledSales.map((row) {
                              final id = row['id'] as int;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: CheckboxListTile(
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: _selectedCancelledSales.contains(id),
                                  onChanged: _working ? null : (checked) => setState(() {
                                    if (checked == true) {
                                      _selectedCancelledSales.add(id);
                                    } else {
                                      _selectedCancelledSales.remove(id);
                                    }
                                  }),
                                  title: Text(row['invoice_number']?.toString() ?? 'Penjualan #$id', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text(
                                    '${row['customer_name'] ?? 'Pelanggan Umum'} • Dibatalkan • ${_money(row['total'])}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              );
                            }),
                          const Divider(height: 22),
                          Row(children: [
                            const Expanded(child: Text('Kandidat penjualan belum dibayar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selectedSales.length} dipilih', style: const TextStyle(fontSize: 11)),
                            IconButton(tooltip: 'Hapus penjualan terpilih', onPressed: _selectedSales.isEmpty || _working ? null : _deleteSelectedSales, icon: const Icon(Icons.delete_outline, color: Colors.red)),
                          ]),
                          if (_sales.isEmpty)
                            const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('Tidak ada penjualan belum dibayar.', style: TextStyle(fontSize: 12, color: Colors.grey)))
                          else
                            ..._sales.map((row) {
                              final id = row['id'] as int;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: CheckboxListTile(
                                  dense: true, controlAffinity: ListTileControlAffinity.leading,
                                  value: _selectedSales.contains(id),
                                  onChanged: _working ? null : (checked) => setState(() { if (checked == true) { _selectedSales.add(id); } else { _selectedSales.remove(id); } }),
                                  title: Text(row['invoice_number']?.toString() ?? 'Penjualan #$id', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text('${row['customer_name'] ?? 'Pelanggan Umum'} • ${_money(row['total'])}', style: const TextStyle(fontSize: 11)),
                                ),
                              );
                            }),
                          const Divider(height: 22),
                          Row(children: [
                            const Expanded(child: Text('Kandidat pembelian belum dibayar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selectedPurchases.length} dipilih', style: const TextStyle(fontSize: 11)),
                            IconButton(tooltip: 'Hapus pembelian terpilih', onPressed: _selectedPurchases.isEmpty || _working ? null : _deleteSelectedPurchases, icon: const Icon(Icons.delete_outline, color: Colors.red)),
                          ]),
                          if (_purchases.isEmpty)
                            const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('Tidak ada pembelian dummy yang memenuhi syarat.', style: TextStyle(fontSize: 12, color: Colors.grey)))
                          else
                            ..._purchases.map((row) {
                              final id = row['id'] as int;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: CheckboxListTile(
                                  dense: true, controlAffinity: ListTileControlAffinity.leading,
                                  value: _selectedPurchases.contains(id),
                                  onChanged: _working ? null : (checked) => setState(() { if (checked == true) { _selectedPurchases.add(id); } else { _selectedPurchases.remove(id); } }),
                                  title: Text(row['invoice_number']?.toString() ?? 'Pembelian #$id', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text('${row['supplier_name'] ?? 'Pemasok'} • ${_money(row['total'])}', style: const TextStyle(fontSize: 11)),
                                ),
                              );
                            }),
                          const Divider(height: 22),
                          const Divider(height: 22),
                          Row(children: [
                            const Expanded(child: Text('Kandidat kas manual (masuk/keluar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selectedCash.length} dipilih', style: const TextStyle(fontSize: 11)),
                            IconButton(tooltip: 'Hapus kas manual terpilih', onPressed: _selectedCash.isEmpty || _working ? null : _deleteSelectedCash, icon: const Icon(Icons.delete_outline, color: Colors.red)),
                          ]),
                          if (_manualCash.isEmpty)
                            const Padding(padding: EdgeInsets.only(bottom: 14), child: Text('Tidak ada transaksi kas manual.', style: TextStyle(fontSize: 12, color: Colors.grey)))
                          else
                            ..._manualCash.map((row) {
                              final id = row['id'] as int;
                              final income = row['transaction_type'] == 'income';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: CheckboxListTile(
                                  dense: true, controlAffinity: ListTileControlAffinity.leading,
                                  value: _selectedCash.contains(id),
                                  onChanged: _working ? null : (checked) => setState(() { if (checked == true) { _selectedCash.add(id); } else { _selectedCash.remove(id); } }),
                                  title: Text(row['description']?.toString() ?? row['category']?.toString() ?? 'Kas manual #$id', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text('${income ? 'Kas masuk' : 'Kas keluar'} • ${row['transaction_date'] ?? ''} • ${_money(row['amount'])}', style: const TextStyle(fontSize: 11)),
                                ),
                              );
                            }),
                          Row(children: [
                            const Expanded(child: Text('Kandidat nota servis (menunggu)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selected.length} dipilih', style: const TextStyle(fontSize: 11)),
                            IconButton(tooltip: 'Hapus nota servis terpilih', onPressed: _selected.isEmpty || _working ? null : _deleteSelected, icon: const Icon(Icons.delete_outline, color: Colors.red)),
                          ]),
                          if (_orders.isEmpty)
                            const Text('Belum ada nota servis.', style: TextStyle(fontSize: 12, color: Colors.grey))
                          else
                            ..._orders.map((row) {
                              final id = row['id'] as int;
                              final number = row['order_number']?.toString() ?? 'Servis #$id';
                              final customer = row['customer_name']?.toString() ?? 'Pelanggan Umum';
                              final status = row['service_status']?.toString() ?? '-';
                              return Card(
                                margin: const EdgeInsets.only(bottom: 4),
                                child: CheckboxListTile(
                                  value: _selected.contains(id),
                                  onChanged: _working ? null : (checked) => setState(() { if (checked == true) { _selected.add(id); } else { _selected.remove(id); } }),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text(number, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  subtitle: Text('$customer • $status • ${_money(row['total_cost'])}', style: const TextStyle(fontSize: 11)),
                                  dense: true,
                                ),
                              );
                            }),
                        ],
                      ),
          ),
          if (_working)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
