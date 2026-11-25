import 'package:material_ui/material_ui.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class TestTransactionCleanupPage extends StatefulWidget {
  const TestTransactionCleanupPage({super.key});

  @override
  State<TestTransactionCleanupPage> createState() => _TestTransactionCleanupPageState();
}

class _TestTransactionCleanupPageState extends State<TestTransactionCleanupPage> {
  String _type = 'all';
  String _classification = 'all';
  bool _loading = true;
  String? _error;
  List<Map<String, Object?>> _rows = [];
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthSession.instance.isAdmin) {
      setState(() {
        _loading = false;
        _error = 'Hanya Admin yang dapat membuka pembersihan transaksi.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = await AppDatabase.instance.database;
      final rows = <Map<String, Object?>>[];
      Future<void> collect(String table, String type, String numberColumn,
          String dateColumn, String totalColumn) async {
        final data = await db.query(
          table,
          columns: ['id', numberColumn, dateColumn, totalColumn, 'is_test'],
          orderBy: '$dateColumn DESC, id DESC',
          limit: 300,
        );
        for (final row in data) {
          final isTest = (row['is_test'] as num?)?.toInt() == 1;
          if (_classification == 'test' && !isTest) continue;
          if (_classification == 'legacy' && isTest) continue;
          rows.add({
            'key': '$type:${row['id']}',
            'type': type,
            'id': row['id'],
            'number': row[numberColumn]?.toString() ?? '-',
            'date': row[dateColumn]?.toString() ?? '-',
            'total': (row[totalColumn] as num?)?.toInt() ?? 0,
            'is_test': isTest,
          });
        }
      }

      if (_type == 'all' || _type == 'sale') {
        await collect('sales', 'Penjualan', 'invoice_number',
            'transaction_date', 'total');
      }
      if (_type == 'all' || _type == 'purchase') {
        await collect('purchases', 'Pembelian', 'invoice_number',
            'purchase_date', 'total');
      }
      if (_type == 'all' || _type == 'service') {
        await collect('service_orders', 'Servis', 'order_number',
            'received_at', 'total_cost');
      }
      rows.sort((a, b) =>
          (b['date'] as String).compareTo(a['date'] as String));
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _selected.removeWhere((key) =>
            !rows.any((row) => row['key'] == key));
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat daftar transaksi: $error';
        _loading = false;
      });
    }
  }

  String _rupiah(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${value < 0 ? '-' : ''}Rp$buffer';
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthSession.instance.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pembersihan Transaksi')),
        body: const Center(child: Text('Akses khusus Admin.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Pilih Transaksi Percobaan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: 'Jenis transaksi',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Semua jenis')),
                    DropdownMenuItem(value: 'sale', child: Text('Penjualan')),
                    DropdownMenuItem(value: 'purchase', child: Text('Pembelian')),
                    DropdownMenuItem(value: 'service', child: Text('Servis')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _type = value);
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _classification,
                  decoration: const InputDecoration(
                    labelText: 'Klasifikasi transaksi',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('Semua transaksi')),
                    DropdownMenuItem(value: 'test', child: Text('Ditandai percobaan')),
                    DropdownMenuItem(value: 'legacy', child: Text('Transaksi lama / belum ditandai')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _classification = value);
                    _load();
                  },
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Dipilih: ${_selected.length} dari ${_rows.length} transaksi. Transaksi lama tidak otomatis dianggap percobaan; pilih secara manual.',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_error!, textAlign: TextAlign.center)))
                    : _rows.isEmpty
                        ? const Center(child: Text('Tidak ada transaksi pada filter ini.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
                              itemCount: _rows.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 6),
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                final key = row['key'] as String;
                                final isTest = row['is_test'] as bool;
                                return Card(
                                  margin: EdgeInsets.zero,
                                  child: CheckboxListTile(
                                    value: _selected.contains(key),
                                    controlAffinity: ListTileControlAffinity.leading,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                    onChanged: (checked) => setState(() {
                                      if (checked == true) {
                                        _selected.add(key);
                                      } else {
                                        _selected.remove(key);
                                      }
                                    }),
                                    title: Text(
                                      '${row['type']} • ${row['number']}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    subtitle: Text(
                                      '${row['date']}\n${_rupiah(row['total'] as int)} • ${isTest ? 'Ditandai percobaan' : 'Belum ditandai (perlu pemeriksaan manual)'}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: const [BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, -2),
                )],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_selected.length} transaksi dipilih',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tahap ini hanya memilih dan memeriksa daftar. Penghapusan belum diaktifkan sampai pembalikan stok, kas, saldo, retur, dan seluruh relasi data lolos pemeriksaan keamanan.',
                    style: TextStyle(fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => setState(() => _selected.clear()),
                    child: const Text('Batalkan pilihan'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
