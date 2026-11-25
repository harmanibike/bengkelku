import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../services/data/service_repository.dart';
import '../../sales/data/sale_repository.dart';
import '../../purchases/data/purchase_repository.dart';

class TransactionCleanupPage extends StatefulWidget {
  const TransactionCleanupPage({super.key});

  @override
  State<TransactionCleanupPage> createState() => _TransactionCleanupPageState();
}

class _TransactionCleanupPageState extends State<TransactionCleanupPage> {
  final _repository = ServiceRepository();
  final _saleRepository = SaleRepository();
  final _purchaseRepository = PurchaseRepository();
  final Set<int> _selected = {};
  final Set<int> _selectedSales = {};
  final Set<int> _selectedPurchases = {};
  List<Map<String, Object?>> _orders = [];
  List<Map<String, Object?>> _sales = [];
  List<Map<String, Object?>> _purchases = [];
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
      _selectedPurchases.clear();
    });
    try {
      final results = await Future.wait([
        _repository.getServiceOrders(),
        _saleRepository.getSales(),
        _purchaseRepository.getPurchases(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0].where((row) => row['service_status']?.toString() == 'waiting').toList();
        _sales = results[1].where((row) => row['payment_status']?.toString() == 'unpaid').toList();
        _purchases = results[2].where((row) => row['status']?.toString() != 'cancelled' && (row['paid'] as num? ?? 0) == 0 && (row['return_credit'] as num? ?? 0) == 0).toList();
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
        title: const Text('Hapus nota servis terpilih?'),
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
        title: const Text('Hapus penjualan dummy terpilih?'),
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

  Future<void> _deleteSelectedPurchases() async {
    if (_selectedPurchases.isEmpty || _working) return;
    final ids = _selectedPurchases.toList(growable: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus pembelian dummy terpilih?'),
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
              'Pilih transaksi dummy penjualan, pembelian, atau servis yang ingin dibersihkan. Transaksi yang memiliki pembayaran, retur, pergerakan stok, saldo, tip, riwayat, atau arsip akan dilindungi.',
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
                            const Expanded(child: Text('Kandidat penjualan belum dibayar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selectedSales.length} dipilih', style: const TextStyle(fontSize: 11)),
                            TextButton(
                              onPressed: _working ? null : () => setState(() {
                                if (_selectedSales.length == _sales.length) { _selectedSales.clear(); }
                                else { _selectedSales..clear()..addAll(_sales.map((row) => row['id'] as int)); }
                              }),
                              child: Text(_selectedSales.length == _sales.length && _sales.isNotEmpty ? 'Batal' : 'Pilih'),
                            ),
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
                            TextButton(
                              onPressed: _working ? null : () => setState(() {
                                if (_selectedPurchases.length == _purchases.length) { _selectedPurchases.clear(); }
                                else { _selectedPurchases..clear()..addAll(_purchases.map((row) => row['id'] as int)); }
                              }),
                              child: Text(_selectedPurchases.length == _purchases.length && _purchases.isNotEmpty ? 'Batal' : 'Pilih'),
                            ),
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
                          Row(children: [
                            const Expanded(child: Text('Kandidat nota servis (menunggu)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            Text('${_selected.length} dipilih', style: const TextStyle(fontSize: 11)),
                            TextButton(
                              onPressed: _working ? null : () => setState(() {
                                if (_selected.length == _orders.length) { _selected.clear(); }
                                else { _selected..clear()..addAll(_orders.map((row) => row['id'] as int)); }
                              }),
                              child: Text(_selected.length == _orders.length && _orders.isNotEmpty ? 'Batal' : 'Pilih'),
                            ),
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
