import 'package:material_ui/material_ui.dart';

import '../data/supplier_repository.dart';
import 'supplier_detail_page.dart';

class SupplierDebtsPage extends StatefulWidget {
  const SupplierDebtsPage({super.key});

  @override
  State<SupplierDebtsPage> createState() => _SupplierDebtsPageState();
}

class _SupplierDebtsPageState extends State<SupplierDebtsPage> {
  final _repository = SupplierRepository();
  late Future<List<Map<String, Object?>>> _future;
  late Future<List<Map<String, Object?>>> _onlineFuture;

  @override
  void initState() {
    super.initState();
    _future = _repository.getSuppliersWithDebt();
    _onlineFuture = _repository.getOnlinePurchaseDebts();
  }

  Future<void> _refresh() async {
    final next = _repository.getSuppliersWithDebt();
    final onlineNext = _repository.getOnlinePurchaseDebts();
    setState(() { _future = next; _onlineFuture = onlineNext; });
    await Future.wait([next, onlineNext]);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Utang Pemasok'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return Center(child: Text('Gagal memuat utang: ${snapshot.error}'));
          final rows = snapshot.data ?? [];
          final totalDebt = rows.fold<int>(0, (sum, row) => sum + ((row['remaining_amount'] as num?)?.toInt() ?? 0));
          final totalInvoices = rows.fold<int>(0, (sum, row) => sum + ((row['invoice_count'] as num?)?.toInt() ?? 0));
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
                        const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFFE65100), size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Total utang pemasok', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 3),
                              Text(_money(totalDebt), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                              Text('${rows.length} pemasok • $totalInvoices faktur belum lunas', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(2, 14, 2, 7),
                  child: Text('Daftar Utang per Pemasok', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                if (rows.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Tidak ada utang pemasok. Semua faktur pemasok sudah lunas.', style: TextStyle(fontSize: 12))))
                else
                  ...rows.map((row) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => SupplierDetailPage(supplier: {
                          'id': row['supplier_id'],
                          'name': row['supplier_name'],
                          'phone': row['phone'],
                        }),
                      )),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      leading: const CircleAvatar(radius: 18, child: Icon(Icons.local_shipping_outlined, size: 19)),
                      title: Text(row['supplier_name'] as String? ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${row['invoice_count']} faktur • Sudah dibayar ${_money(row['paid_amount'])}',
                        style: const TextStyle(fontSize: 10)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_money(row['remaining_amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                          const Text('Sisa utang', style: TextStyle(fontSize: 9, color: Colors.grey)),
                        ],
                      ),
                    ),
                  )),
                const Padding(
                  padding: EdgeInsets.fromLTRB(2, 16, 2, 7),
                  child: Text('Tagihan Toko Online', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                FutureBuilder<List<Map<String, Object?>>>(
                  future: _onlineFuture,
                  builder: (context, onlineSnapshot) {
                    if (onlineSnapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                    }
                    if (onlineSnapshot.hasError) {
                      return Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Gagal memuat tagihan toko online: ${onlineSnapshot.error}', style: const TextStyle(fontSize: 11))));
                    }
                    final onlineRows = onlineSnapshot.data ?? [];
                    if (onlineRows.isEmpty) {
                      return const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Tidak ada tagihan pembelian online yang belum lunas.', style: TextStyle(fontSize: 12))));
                    }
                    final onlineTotal = onlineRows.fold<int>(0, (sum, row) => sum + ((row['remaining_amount'] as num?)?.toInt() ?? 0));
                    return Column(
                      children: [
                        Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(11),
                            child: Row(children: [
                              const Expanded(child: Text('Total tagihan toko online', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                              Text(_money(onlineTotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                            ]),
                          ),
                        ),
                        ...onlineRows.map((row) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                            leading: const CircleAvatar(radius: 18, child: Icon(Icons.storefront_outlined, size: 19)),
                            title: Text(row['store_name']?.toString() ?? 'Toko online', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text('${row['invoice_count']} faktur • Dibayar ${_money(row['paid_amount'])}', style: const TextStyle(fontSize: 10)),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(_money(row['remaining_amount']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
                                const Text('Sisa tagihan', style: TextStyle(fontSize: 9, color: Colors.grey)),
                              ],
                            ),
                          ),
                        )),
                      ],
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
