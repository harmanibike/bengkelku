import 'package:material_ui/material_ui.dart';

import '../data/purchase_report_repository.dart';

class PurchaseReportsPage extends StatefulWidget {
  const PurchaseReportsPage({super.key});

  @override
  State<PurchaseReportsPage> createState() => _PurchaseReportsPageState();
}

class _PurchaseReportsPageState extends State<PurchaseReportsPage> {
  final _repository = PurchaseReportRepository();
  String _period = 'month';
  bool _loading = true;
  Map<String, Object?> _report = {};

  @override
  void initState() {
    super.initState();
    _load();
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

  String _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '-';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    late DateTime start;
    late DateTime end;
    if (_period == 'today') {
      start = DateTime(now.year, now.month, now.day);
      end = start.add(const Duration(days: 1));
    } else if (_period == 'month') {
      start = DateTime(now.year, now.month);
      end = DateTime(now.year, now.month + 1);
    } else {
      start = DateTime(2000);
      end = now.add(const Duration(days: 1));
    }
    try {
      final data = await _repository.getReport(start: start, end: end);
      if (!mounted) return;
      setState(() { _report = data; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat laporan pembelian: $error')),
      );
    }
  }

  Widget _metric(String label, Object? value, IconData icon, Color color) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 5),
            Text(_money(value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = _report['suppliers'] as List? ?? [];
    final latest = _report['latest'] as List? ?? [];
    final net = ((_report['purchase_total'] as num?)?.toInt() ?? 0) -
        ((_report['return_amount'] as num?)?.toInt() ?? 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Pembelian'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  DropdownButtonFormField<String>(
                    value: _period,
                    isDense: true,
                    decoration: const InputDecoration(labelText: 'Periode laporan'),
                    items: const [
                      DropdownMenuItem(value: 'today', child: Text('Hari ini')),
                      DropdownMenuItem(value: 'month', child: Text('Bulan ini')),
                      DropdownMenuItem(value: 'all', child: Text('Semua waktu')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _period = value);
                      _load();
                    },
                  ),
                  const SizedBox(height: 9),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.9,
                    children: [
                      _metric('Total pembelian', _report['purchase_total'], Icons.shopping_cart_outlined, Colors.blue),
                      _metric('Pembayaran tercatat', _report['payment_amount'], Icons.payments_outlined, Colors.green),
                      _metric('Sisa utang faktur', _report['outstanding'], Icons.account_balance_wallet_outlined, Colors.deepOrange),
                      _metric('Nilai retur', _report['return_amount'], Icons.assignment_return_outlined, Colors.purple),
                      _metric('Kredit retur diterapkan', _report['return_credit'], Icons.price_check_rounded, Colors.teal),
                    ],
                  ),
                  Card(
                    margin: const EdgeInsets.only(top: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Pembelian bersih setelah retur', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          Text(_money(net), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 15, 2, 7),
                    child: Text('Ringkasan Aktivitas', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Column(
                        children: [
                          _row('Jumlah faktur pembelian', '${_report['purchase_count'] ?? 0}'),
                          _row('Jumlah transaksi pembayaran', '${_report['payment_count'] ?? 0}'),
                          _row('Jumlah retur', '${_report['return_count'] ?? 0}'),
                          _row('Jumlah pemasok aktif pada periode', '${suppliers.length}'),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 15, 2, 7),
                    child: Text('Pembelian per Pemasok', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (suppliers.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada pembelian pada periode ini.', style: TextStyle(fontSize: 12))))
                  else
                    ...suppliers.map((raw) {
                      final row = raw as Map<String, Object?>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
                          title: Text(row['supplier_name'] as String? ?? 'Pemasok tidak diketahui', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          subtitle: Text('${row['invoice_count']} faktur • Sisa ${_money(row['outstanding'])}', style: const TextStyle(fontSize: 10)),
                          trailing: Text(_money(row['total_amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      );
                    }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 15, 2, 7),
                    child: Text('Faktur Terbaru', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (latest.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada faktur pembelian.', style: TextStyle(fontSize: 12))))
                  else
                    ...latest.map((raw) {
                      final row = raw as Map<String, Object?>;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
                          title: Text(row['invoice_number'] as String? ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          subtitle: Text('${row['supplier_name'] ?? 'Pemasok'} • ${_date(row['purchase_date'])}', style: const TextStyle(fontSize: 10)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(_money(row['total']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              Text('Sisa ${_money(row['outstanding'])}', style: const TextStyle(fontSize: 9, color: Colors.deepOrange)),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
        Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    ),
  );
}
