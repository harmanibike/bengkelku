import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../services/data/service_repository.dart';
import '../../sales/data/sale_repository.dart';

class TransactionCleanupPage extends StatefulWidget {
  const TransactionCleanupPage({super.key});

  @override
  State<TransactionCleanupPage> createState() => _TransactionCleanupPageState();
}

class _TransactionCleanupPageState extends State<TransactionCleanupPage> {
  final _repository = ServiceRepository();
  final _saleRepository = SaleRepository();
  final Set<int> _selected = {};
  final Set<int> _selectedSales = {};
  List<Map<String, Object?>> _orders = [];
  List<Map<String, Object?>> _sales = [];
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
    });
    try {
      final results = await Future.wait([
        _repository.getServiceOrders(),
        _saleRepository.getSales(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] as List<Map<String, Object?>>;
        _sales = (results[1] as List<Map<String, Object?>>).where((row) => row['payment_status']?.toString() == 'unpaid').toList();
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
          'Anda memilih ${ids.length} nota. Penghapusan hanya berhasil untuk nota tanpa pembayaran, saldo pelanggan, tip, pergerakan stok, batch biaya, riwayat audit, atau arsip nota. Nota yang memiliki keterkaitan akan ditolak otomatis.',
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
        content: Text('Anda memilih ${ids.length} transaksi belum dibayar. Transaksi dengan pembayaran, retur, catatan saldo/poin, atau arsip nota akan ditolak.'),
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
              'Pembersihan nota servis dummy. Nota yang sudah memiliki pembayaran, penggunaan stok, retur/saldo, tip, riwayat, atau arsip akan dilindungi. Penghapusan tidak mengubah format nota maupun transaksi lain.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          if (_orders.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Text('${_selected.length} dipilih', style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  TextButton(
                    onPressed: _working
                        ? null
                        : () => setState(() {
                              if (_selected.length == _orders.length) {
                                _selected.clear();
                              } else {
                                _selected
                                  ..clear()
                                  ..addAll(_orders.map((row) => row['id'] as int));
                              }
                            }),
                    child: Text(_selected.length == _orders.length ? 'Batal pilih' : 'Pilih semua'),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: _selected.isEmpty || _working ? null : _deleteSelected,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Hapus'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  ),
                ],
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
                            const Expanded(child: Text('Penjualan dummy (belum dibayar)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
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
                            const Expanded(child: Text('Nota servis', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
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
