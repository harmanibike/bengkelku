import 'package:material_ui/material_ui.dart';

import '../data/report_repository.dart';
import '../../purchases/presentation/purchase_reports_page.dart';
import 'tip_report_page.dart';

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
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
                  const Text('Jenis Laporan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8EAF6),
                        child: Icon(Icons.shopping_bag_outlined, color: Color(0xFF3949AB)),
                      ),
                      title: const Text('Laporan Pembelian', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Ringkasan pembelian, pemasok, dan transaksi pembelian'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PurchaseReportsPage()),
                        );
                      },
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8F5E9),
                        child: Icon(Icons.volunteer_activism_outlined, color: Color(0xFF2E7D32)),
                      ),
                      title: const Text('Laporan Uang Tip', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: const Text('Tip diterima, belum diserahkan, dan sudah diserahkan; terpisah dari omzet'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TipReportPage()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Ringkasan Keuangan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _period,
                    decoration: const InputDecoration(labelText: 'Periode laporan', border: OutlineInputBorder(), isDense: true),
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
                    childAspectRatio: 1.25,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    children: [
                      _metric('Kas Masuk', _rupiah(income), Icons.trending_up, Colors.green),
                      _metric('Kas Keluar', _rupiah(expense), Icons.trending_down, Colors.red),
                      _metric('Arus Kas Bersih', _rupiah((_summary['net_cash_flow'] as num?)?.toInt() ?? (income - expense)), Icons.account_balance, (income - expense) >= 0 ? Colors.green : Colors.red),
                      _metric('Titipan Deposit Pelanggan', _rupiah((_summary['customer_wallet_balance'] as num?)?.toInt() ?? 0), Icons.account_balance_wallet_outlined, Colors.blue),
                      _metric('Penjualan Bersih', _rupiah((_summary['net_sales_amount'] as num?)?.toInt() ?? 0), Icons.shopping_cart, Colors.orange),
                      _metric('Retur Penjualan', _rupiah((_summary['sales_return_amount'] as num?)?.toInt() ?? 0), Icons.assignment_return, Colors.deepOrange),
                      _metric('HPP Bersih Barang', _rupiah((_summary['net_cogs_amount'] as num?)?.toInt() ?? 0), Icons.inventory_2, Colors.blueGrey),
                      _metric('Laba Kotor Barang', _rupiah((_summary['gross_profit_amount'] as num?)?.toInt() ?? 0), Icons.account_balance_wallet, Colors.green),
                      _metric('Pendapatan Servis Selesai', _rupiah((_summary['service_revenue'] as num?)?.toInt() ?? 0), Icons.handyman, Colors.teal),
                      _metric('Servis Selesai', '${_summary['completed_service_count'] ?? 0} nota', Icons.build, Colors.blue),
                      _metric('Biaya Langsung Servis', _rupiah((_summary['service_direct_cost_amount'] as num?)?.toInt() ?? 0), Icons.receipt, Colors.red),
                      _metric('Laba Kotor Servis', _rupiah((_summary['service_gross_profit_amount'] as num?)?.toInt() ?? 0), Icons.handyman, Colors.teal),
                      _metric('Total Laba Kotor', _rupiah((_summary['combined_gross_profit_amount'] as num?)?.toInt() ?? 0), Icons.account_balance_wallet, Colors.green),
                      _metric('Pengeluaran Operasional Manual', _rupiah((_summary['manual_operating_expense_amount'] as num?)?.toInt() ?? 0), Icons.money_off, Colors.red),
                      _metric('Sisa Setelah Beban Tercatat', _rupiah((_summary['profit_after_recorded_operating_expense'] as num?)?.toInt() ?? 0), Icons.calculate, Colors.indigo),
                      _metric('Stok Menipis', '${_summary['low_stock'] ?? 0} produk', Icons.inventory, Colors.deepOrange),
                      _metric('Transaksi Kas', '${_summary['transaction_count'] ?? 0}', Icons.receipt_long, Colors.purple),
                      _metric('Piutang Servis Saat Ini', _rupiah((_summary['service_receivable_amount'] as num?)?.toInt() ?? 0), Icons.build_circle_outlined, Colors.orange),
                      _metric('Piutang Penjualan Saat Ini', _rupiah((_summary['sale_receivable_amount'] as num?)?.toInt() ?? 0), Icons.shopping_bag_outlined, Colors.orange),
                      _metric('Total Piutang Pelanggan', _rupiah((_summary['customer_receivable_amount'] as num?)?.toInt() ?? 0), Icons.people_outline, Colors.deepOrange),
                      _metric('Utang Pemasok Saat Ini', _rupiah((_summary['supplier_payable_amount'] as num?)?.toInt() ?? 0), Icons.local_shipping_outlined, Colors.red),
                    ],
                  ),
                  Builder(builder: (context) {
                    final issues = (_summary['return_refund_audit_issues'] as List?) ?? [];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(issues.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
                                  color: issues.isEmpty ? Colors.green : Colors.orange),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Audit pengembalian uang retur',
                                  style: TextStyle(fontWeight: FontWeight.w600))),
                                Text('${issues.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (issues.isEmpty)
                              const Text('Nilai refund pada nota retur cocok dengan pengembalian kas dan saldo pelanggan pada periode ini.',
                                style: TextStyle(fontSize: 12, color: Colors.grey))
                            else ...[
                              const Text('Perbedaan nilai refund nota dengan pengembalian kas dan saldo pelanggan:',
                                style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 6),
                              ...issues.take(5).map((row) {
                                final item = row as Map<String, Object?>;
                                final difference = (item['difference'] as num?)?.toInt() ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${item['return_number'] ?? '-'} • Nota ${item['invoice_number'] ?? '-'}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    Text('Refund: ${_rupiah((item['recorded_refund'] as num?)?.toInt() ?? 0)} | Kas: ${_rupiah((item['cash_refund'] as num?)?.toInt() ?? 0)} | Saldo: ${_rupiah((item['wallet_refund'] as num?)?.toInt() ?? 0)} | Selisih: ${_rupiah(difference)}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ]),
                                );
                              }),
                              if (issues.length > 5)
                                Text('${issues.length - 5} retur lainnya perlu diperiksa.',
                                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  Builder(builder: (context) {
                    final issues = (_summary['purchase_return_audit_issues'] as List?) ?? [];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(issues.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
                                  color: issues.isEmpty ? Colors.green : Colors.orange),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Audit retur pembelian',
                                  style: TextStyle(fontWeight: FontWeight.w600))),
                                Text('${issues.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (issues.isEmpty)
                              const Text('Nilai item, kredit pemasok, refund kas, dan alokasi batch retur cocok pada periode ini.',
                                style: TextStyle(fontSize: 12, color: Colors.grey))
                            else ...[
                              const Text('Ditemukan data retur yang perlu diperiksa:',
                                style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 6),
                              ...issues.take(5).map((row) {
                                final item = row as Map<String, Object?>;
                                final rupiah = (value) => _rupiah((value as num?)?.toInt() ?? 0);
                                final batchIssues = (item['batch_issue_count'] as num?)?.toInt() ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${item['return_number'] ?? '-'} • Faktur ${item['invoice_number'] ?? '-'}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    Text('Nilai retur: ${rupiah(item['total_amount'])} / item: ${rupiah(item['item_total'])}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    Text('Kredit: ${rupiah(item['credit_applied'])} / riwayat: ${rupiah(item['applied_credit_total'])} • Refund: ${rupiah(item['refund_received'])} / kas: ${rupiah(item['cash_refund'])}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    if (batchIssues > 0)
                                      Text('$batchIssues item memiliki alokasi batch yang tidak cocok.',
                                        style: const TextStyle(fontSize: 11, color: Colors.orange)),
                                  ]),
                                );
                              }),
                              if (issues.length > 5)
                                Text('${issues.length - 5} retur lainnya perlu diperiksa.',
                                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                  Builder(builder: (context) {
                    final issues = (_summary['sale_return_cost_audit_issues'] as List?) ?? [];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(issues.isEmpty ? Icons.verified_outlined : Icons.warning_amber_rounded,
                                  color: issues.isEmpty ? Colors.green : Colors.orange),
                                const SizedBox(width: 8),
                                const Expanded(child: Text('Audit HPP retur penjualan',
                                  style: TextStyle(fontWeight: FontWeight.w600))),
                                Text('${issues.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (issues.isEmpty)
                              const Text('Snapshot biaya retur sesuai dengan nota asal dan jumlah alokasi batch yang dipulihkan.',
                                style: TextStyle(fontSize: 12, color: Colors.grey))
                            else ...[
                              const Text('Retur berikut memiliki selisih snapshot HPP atau jumlah batch yang dipulihkan:',
                                style: TextStyle(fontSize: 12)),
                              const SizedBox(height: 6),
                              ...issues.take(5).map((row) {
                                final item = row as Map<String, Object?>;
                                final costIssues = (item['cost_issue_count'] as num?)?.toInt() ?? 0;
                                final batchIssues = (item['batch_quantity_issue_count'] as num?)?.toInt() ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('${item['return_number'] ?? '-'} • Nota ${item['invoice_number'] ?? '-'}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    if (costIssues > 0)
                                      Text('$costIssues item memiliki biaya retur berbeda dari snapshot nota.',
                                        style: const TextStyle(fontSize: 11, color: Colors.orange)),
                                    if (batchIssues > 0)
                                      Text('$batchIssues item memiliki jumlah alokasi batch yang tidak cocok.',
                                        style: const TextStyle(fontSize: 11, color: Colors.orange)),
                                  ]),
                                );
                              }),
                              if (issues.length > 5)
                                Text('${issues.length - 5} retur lainnya perlu diperiksa.',
                                  style: const TextStyle(fontSize: 11, color: Colors.orange)),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
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
                      'Arus kas menunjukkan uang yang benar-benar masuk dan keluar, bukan laba. Pendapatan servis dihitung dari nota selesai/diambil berdasarkan tanggal selesai. Laba kotor servis mengurangi biaya modal sparepart dan biaya langsung lain yang diinput manual. Sisa setelah beban tercatat mengurangi total laba kotor dengan pengeluaran manual dari Buku Kas; pembayaran pembelian pemasok tidak dikurangkan lagi karena HPP barang sudah dihitung saat penjualan. Ini belum merupakan laba bersih final: pajak, penyusutan, biaya yang belum dicatat, dan beban lain mungkin belum tercakup. Jangan masukkan biaya yang sama sekaligus sebagai biaya langsung servis dan pengeluaran manual Buku Kas agar tidak terhitung dua kali. DP/pelunasan hanya dihitung pada arus kas. Deposit pelanggan tetap terlihat pada arus kas karena merupakan titipan yang benar-benar diterima, tetapi bukan omzet (lihat metrik saldo deposit). Uang tip tidak dimasukkan ke Buku Kas maupun arus kas dan hanya ditampilkan pada Laporan Uang Tip. Saldo piutang dan utang pemasok adalah posisi berjalan saat ini, tidak dibatasi periode laporan.',
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
