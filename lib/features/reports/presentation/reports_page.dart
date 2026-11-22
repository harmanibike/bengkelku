import 'package:material_ui/material_ui.dart';

import '../data/report_repository.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final ReportRepository _repository = ReportRepository();
  String _period = 'today';
  bool _loading = true;
  Map<String, Object?> _summary = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _rupiah(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp$buffer';
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
      final data = await _repository.getSummary(start: start, end: end);
      if (!mounted) return;
      setState(() {
        _summary = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat laporan: $error')),
      );
    }
  }

  Widget _metric(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final income = _summary['income'] as int? ?? 0;
    final expense = _summary['expense'] as int? ?? 0;
    final categories = (_summary['categories'] as List?) ?? [];
    final latest = (_summary['latest'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  DropdownButtonFormField<String>(
                    value: _period,
                    decoration: const InputDecoration(labelText: 'Periode laporan', border: OutlineInputBorder()),
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
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.45,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    children: [
                      _metric('Kas Masuk', _rupiah(income), Icons.trending_up, Colors.green),
                      _metric('Kas Keluar', _rupiah(expense), Icons.trending_down, Colors.red),
                      _metric('Arus Kas Bersih', _rupiah((_summary['net_cash_flow'] as num?)?.toInt() ?? (income - expense)), Icons.account_balance, (income - expense) >= 0 ? Colors.green : Colors.red),
                      _metric('Penjualan Bersih', _rupiah((_summary['net_sales_amount'] as num?)?.toInt() ?? 0), Icons.shopping_cart, Colors.orange),
                      _metric('Retur Penjualan', _rupiah((_summary['sales_return_amount'] as num?)?.toInt() ?? 0), Icons.assignment_return, Colors.deepOrange),
                      _metric('HPP Bersih Barang', _rupiah((_summary['net_cogs_amount'] as num?)?.toInt() ?? 0), Icons.inventory_2, Colors.blueGrey),
                      _metric('Laba Kotor Barang', _rupiah((_summary['gross_profit_amount'] as num?)?.toInt() ?? 0), Icons.account_balance_wallet, Colors.green),
                      _metric('Pendapatan Servis Selesai', _rupiah((_summary['service_revenue'] as num?)?.toInt() ?? 0), Icons.handyman, Colors.teal),
                      _metric('Servis Selesai', '${_summary['completed_service_count'] ?? 0} nota', Icons.build, Colors.blue),
                      _metric('Biaya Langsung Servis', _rupiah((_summary['service_direct_cost_amount'] as num?)?.toInt() ?? 0), Icons.receipt, Colors.red),
                      _metric('Laba Kotor Servis', _rupiah((_summary['service_gross_profit_amount'] as num?)?.toInt() ?? 0), Icons.handyman, Colors.teal),
                      _metric('Total Laba Kotor', _rupiah((_summary['combined_gross_profit_amount'] as num?)?.toInt() ?? 0), Icons.account_balance_wallet, Colors.green),
                      _metric('Stok Menipis', '${_summary['low_stock'] ?? 0} produk', Icons.inventory, Colors.deepOrange),
                      _metric('Transaksi Kas', '${_summary['transaction_count'] ?? 0}', Icons.receipt_long, Colors.purple),
                    ],
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Saldo kas awal', style: TextStyle(fontSize: 12)),
                              Text(_rupiah((_summary['opening_cash_balance'] as num?)?.toInt() ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const Divider(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Saldo kas akhir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              Text(_rupiah((_summary['closing_cash_balance'] as num?)?.toInt() ?? (income - expense)), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Arus kas menunjukkan uang yang benar-benar masuk dan keluar, bukan laba. Pendapatan servis dihitung dari nota selesai/diambil berdasarkan tanggal selesai. Laba kotor servis mengurangi biaya modal sparepart dan biaya langsung lain yang diinput manual; pastikan nilainya dicatat lengkap. Biaya operasional, gaji, komisi, pajak, dan biaya tidak langsung belum seluruhnya dikurangkan, sehingga total laba kotor bukan laba bersih. DP/pelunasan tetap hanya dihitung pada arus kas agar tidak dihitung dua kali.',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Rincian Kas per Kategori', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (categories.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada transaksi pada periode ini.')))
                  else
                    ...categories.map((row) {
                      final item = row as Map<String, Object?>;
                      final type = item['transaction_type'] == 'income' ? 'Masuk' : 'Keluar';
                      return Card(
                        child: ListTile(
                          title: Text('${item['category']} • $type'),
                          trailing: Text(_rupiah(item['amount'] as int? ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      );
                    }),
                  const SizedBox(height: 20),
                  Text('Transaksi Terbaru', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (latest.isEmpty)
                    const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada transaksi.')))
                  else
                    ...latest.map((row) {
                      final item = row as Map<String, Object?>;
                      final isIncome = item['transaction_type'] == 'income';
                      return Card(
                        child: ListTile(
                          leading: Icon(isIncome ? Icons.add_circle : Icons.remove_circle, color: isIncome ? Colors.green : Colors.red),
                          title: Text(item['description']?.toString() ?? item['category']?.toString() ?? 'Transaksi'),
                          subtitle: Text(item['transaction_date']?.toString() ?? ''),
                          trailing: Text('${isIncome ? '+' : '-'}${_rupiah(item['amount'] as int? ?? 0)}'),
                        ),
                      );
                    }),
                  const SizedBox(height: 8),
                  Text('Saldo bersih: ${_rupiah(income - expense)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
    );
  }
}
