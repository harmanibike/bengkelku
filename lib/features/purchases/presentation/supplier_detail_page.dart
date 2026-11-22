import 'package:material_ui/material_ui.dart';

import '../data/supplier_repository.dart';

class SupplierDetailPage extends StatefulWidget {
  const SupplierDetailPage({super.key, required this.supplier});

  final Map<String, Object?> supplier;

  @override
  State<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends State<SupplierDetailPage> {
  final _repository = SupplierRepository();
  late Future<Map<String, Object?>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, Object?>> _load() async {
    final id = widget.supplier['id'] as int;
    final summary = await _repository.getSupplierSummary(id);
    final purchases = await _repository.getPurchaseHistory(id);
    final payments = await _repository.getSupplierPayments(id);
    final creditApplications = await _repository.getSupplierCreditApplications(id);
    return {'summary': summary, 'purchases': purchases, 'payments': payments, 'credit_applications': creditApplications};
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() => _future = next);
    await next;
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
    if (value == null) return '-';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }


  Future<void> _showPurchaseLedgerDetail(int purchaseId) async {
    try {
      final data = await _repository.getPurchaseLedgerDetail(purchaseId);
      if (!mounted) return;
      final invoice = data['invoice'] as Map<String, Object?>;
      final items = data['items'] as List<Map<String, Object?>>;
      final payments = data['payments'] as List<Map<String, Object?>>;
      final returns = data['returns'] as List<Map<String, Object?>>;
      final credits = data['credit_applications'] as List<Map<String, Object?>>;
      final total = (invoice['total'] as num? ?? 0).toInt();
      final paid = (invoice['paid'] as num? ?? 0).toInt();
      final credit = (invoice['return_credit'] as num? ?? 0).toInt();
      final cancelled = invoice['status']?.toString() == 'cancelled';
      final remaining = cancelled ? 0 : (total - paid - credit).clamp(0, 1 << 62).toInt();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Faktur ${invoice['invoice_number'] ?? '-'}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Pemasok: ${invoice['supplier_name'] ?? '-'}'),
                  Text('Tanggal: ${_date(invoice['purchase_date'])}'),
                  if (cancelled)
                    const Text('STATUS: DIBATALKAN', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  const Divider(),
                  _ledgerAmount('Subtotal', invoice['subtotal']),
                  _ledgerAmount('Diskon', invoice['discount']),
                  _ledgerAmount('Total faktur', total, bold: true),
                  _ledgerAmount('Pembayaran tercatat', paid),
                  _ledgerAmount('Kredit retur diterapkan', credit),
                  _ledgerAmount('Sisa utang', remaining, bold: true),
                  const Divider(),
                  const Text('Rincian barang', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (items.isEmpty) const Text('Tidak ada rincian barang.'),
                  ...items.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text('${item['product_name']}\n${item['quantity']} × ${_money(item['unit_cost'])}', style: const TextStyle(fontSize: 12))),
                        Text(_money(item['subtotal']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
                  const Divider(),
                  const Text('Riwayat pembayaran', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (payments.isEmpty) const Text('Belum ada pembayaran tercatat.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ...payments.map((payment) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text('${_date(payment['payment_date'])} • ${payment['payment_method'] ?? 'Metode tidak dicatat'}', style: const TextStyle(fontSize: 11))),
                        Text(_money(payment['amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
                  const Divider(),
                  const Text('Riwayat retur', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (returns.isEmpty) const Text('Belum ada retur.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ...returns.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${entry['return_number'] ?? 'Retur'} • ${_date(entry['return_date'])}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('Nilai ${_money(entry['total_amount'])} • Kredit ${_money(entry['credit_applied'])} • Uang kembali ${_money(entry['refund_received'])}${entry['status'] == 'cancelled' ? ' • Dibatalkan' : ''}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  )),
                  const Divider(),
                  const Text('Kredit retur yang diterapkan', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (credits.isEmpty) const Text('Belum ada kredit retur yang diterapkan ke faktur ini.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ...credits.map((entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(child: Text('${entry['return_number']} • ${_date(entry['created_at'])}', style: const TextStyle(fontSize: 11))),
                        Text(_money(entry['amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat rincian faktur: $error')),
        );
      }
    }
  }

  Widget _ledgerAmount(String label, Object? value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
        Text(_money(value), style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      ],
    ),
  );

  Widget _metric(String label, Object? value, {bool emphasize = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: emphasize ? const Color(0xFFFFF3E0) : const Color(0xFFF3F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(_money(value), style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold,
              color: emphasize ? const Color(0xFFE65100) : null,
            )),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 14, 2, 7),
    child: Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
        Text('$count data', style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    final phone = supplier['phone'] as String? ?? '';
    final address = supplier['address'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Pemasok'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<Map<String, Object?>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('Gagal memuat data: ${snapshot.error}'));
          final data = snapshot.data ?? {};
          final summary = data['summary'] as Map<String, Object?>? ?? {};
          final purchases = data['purchases'] as List<Map<String, Object?>>? ?? [];
          final payments = data['payments'] as List<Map<String, Object?>>? ?? [];
          final creditApplications = data['credit_applications'] as List<Map<String, Object?>>? ?? [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
              children: [
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const CircleAvatar(radius: 23, child: Icon(Icons.local_shipping_outlined)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(supplier['name'] as String? ?? '-', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              if (phone.isNotEmpty) Text(phone, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              if (address.isNotEmpty) Text(address, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    _metric('Total pembelian', summary['total_amount']),
                    const SizedBox(width: 7),
                    _metric('Sudah dibayar', summary['paid_amount']),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    _metric('Sisa utang', summary['remaining_amount'], emphasize: true),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFF3F5F9), borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Jumlah faktur', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Text('${summary['invoice_count'] ?? 0}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                _sectionTitle('Riwayat Pembelian', purchases.length),
                if (purchases.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada pembelian dari pemasok ini.', style: TextStyle(fontSize: 12))))
                else
                  ...purchases.map((row) {
                    final remaining = (row['remaining_amount'] as num? ?? 0).toInt();
                    final status = row['payment_status'] as String? ?? 'unpaid';
                    final cancelled = row['status']?.toString() == 'cancelled';
                    final returned = (row['returned_amount'] as num? ?? 0).toInt();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        onTap: () => _showPurchaseLedgerDetail(row['id'] as int),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
                        leading: const Icon(Icons.receipt_long_outlined, size: 21),
                        title: Text(row['invoice_number'] as String? ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        subtitle: Text('${_date(row['purchase_date'])} • ${row['item_count'] ?? 0} jenis barang • Dibayar ${_money(row['paid'])} • Retur ${_money(returned)}',
                          style: const TextStyle(fontSize: 10)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_money(row['total']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(cancelled ? 'Dibatalkan' : remaining == 0 ? 'Lunas' : 'Sisa ${_money(remaining)}',
                              style: TextStyle(fontSize: 10, color: cancelled ? Colors.grey : remaining == 0 ? Colors.green : Colors.deepOrange)),
                            Text(cancelled ? 'Tidak dihitung sebagai utang' : status == 'partial' ? 'Sebagian' : status == 'unpaid' ? 'Belum lunas' : '',
                              style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  }),
                Row(
                  children: [
                    _metric('Saldo kredit retur', summary['available_return_credit']),
                    const SizedBox(width: 7),
                    _metric('Kredit sudah dipakai', summary['return_credit']),
                  ],
                ),
                _sectionTitle('Pemakaian Kredit Retur', creditApplications.length),
                if (creditApplications.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada kredit retur yang digunakan pada faktur lain.', style: TextStyle(fontSize: 12))))
                else
                  ...creditApplications.map((application) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
                      leading: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.teal),
                      title: Text(_money(application['amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      subtitle: Text('Retur ${application['return_number']} → Faktur ${application['target_invoice']}',
                        style: const TextStyle(fontSize: 10)),
                      trailing: Text(_date(application['created_at']), style: const TextStyle(fontSize: 9, color: Colors.grey)),
                    ),
                  )),
                _sectionTitle('Riwayat Pembayaran', payments.length),
                if (payments.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Belum ada pembayaran ke pemasok.', style: TextStyle(fontSize: 12))))
                else
                  ...payments.map((payment) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 1),
                      leading: const Icon(Icons.payments_outlined, size: 20, color: Colors.green),
                      title: Text(_money(payment['amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      subtitle: Text('${payment['invoice_number'] ?? 'Tanpa faktur'} • ${payment['payment_method'] ?? 'Metode tidak dicatat'}',
                        style: const TextStyle(fontSize: 10)),
                      trailing: Text(_date(payment['payment_date']), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                  )),
              ],
            ),
          );
        },
      ),
    );
  }
}
