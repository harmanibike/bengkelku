import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../services/data/service_repository.dart';

class TransactionCleanupPage extends StatefulWidget {
  const TransactionCleanupPage({super.key});

  @override
  State<TransactionCleanupPage> createState() => _TransactionCleanupPageState();
}

class _TransactionCleanupPageState extends State<TransactionCleanupPage> {
  final _repository = ServiceRepository();
  final Set<int> _selected = {};
  List<Map<String, Object?>> _orders = [];
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
    });
    try {
      final rows = await _repository.getServiceOrders();
      if (!mounted) return;
      setState(() {
        _orders = rows;
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
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!, textAlign: TextAlign.center),
                      ))
                    : _orders.isEmpty
                        ? const Center(child: Text('Belum ada nota servis.'))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                            itemCount: _orders.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final row = _orders[index];
                              final id = row['id'] as int;
                              final number = row['order_number']?.toString() ?? 'Servis #$id';
                              final customer = row['customer_name']?.toString() ?? 'Pelanggan Umum';
                              final status = row['service_status']?.toString() ?? '-';
                              return Card(
                                margin: EdgeInsets.zero,
                                child: CheckboxListTile(
                                  value: _selected.contains(id),
                                  onChanged: _working
                                      ? null
                                      : (checked) => setState(() {
                                            if (checked == true) {
                                              _selected.add(id);
                                            } else {
                                              _selected.remove(id);
                                            }
                                          }),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: Text(number, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  subtitle: Text('$customer • $status • ${_money(row['total_cost'])}', style: const TextStyle(fontSize: 11)),
                                  dense: true,
                                ),
                              );
                            },
                          ),
          ),
          if (_working)
            const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }
}
