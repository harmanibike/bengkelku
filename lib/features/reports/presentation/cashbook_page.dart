import 'package:material_ui/material_ui.dart';

import '../data/cashbook_repository.dart';

class CashbookPage extends StatefulWidget {
  const CashbookPage({super.key});

  @override
  State<CashbookPage> createState() => _CashbookPageState();
}

class _CashbookPageState extends State<CashbookPage> {
  final _repo = CashbookRepository();
  String _period = 'today';
  String _type = 'all';
  late Future<Map<String,Object?>> _future;

  @override
  void initState() { super.initState(); _future = _load(); }

  (DateTime,DateTime) _range() {
    final now=DateTime.now();
    if(_period=='today') {
      final start=DateTime(now.year,now.month,now.day);
      return (start,start.add(const Duration(days:1)));
    }
    if(_period=='month') {
      return (DateTime(now.year,now.month),DateTime(now.year,now.month+1));
    }
    return (DateTime(2000),now.add(const Duration(days:1)));
  }

  Future<Map<String,Object?>> _load() async {
    final range = _range();
    final ledger = await _repo.getLedger(start: range.$1, end: range.$2, type: _type);
    final issues = await _repo.getReconciliationIssues(start: range.$1, end: range.$2);
    final supplierMismatches = await _repo.getSupplierPaymentMismatches(start: range.$1, end: range.$2);
    final customerMismatches = await _repo.getCustomerPaymentMismatches(start: range.$1, end: range.$2);
    return {...ledger, 'audit_issues': issues, 'supplier_mismatches': supplierMismatches, 'customer_mismatches': customerMismatches};
  }

  void _refresh() => setState(()=>_future=_load());

  String _money(Object? value) {
    final amount=(value as num?)?.toInt() ?? 0;
    final digits=amount.abs().toString();
    final buffer=StringBuffer();
    for(var i=0;i<digits.length;i++) {
      if(i>0 && (digits.length-i)%3==0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${amount<0?'-':''}Rp$buffer';
  }

  String _sourceLabel(Map<String, Object?> row) {
    final type = row['reference_type']?.toString();
    final id = row['reference_id']?.toString();
    final source = switch (type) {
      'sale' => 'Penjualan',
      'sale_payment' => 'Pelunasan piutang penjualan',
      'sale_return' => 'Retur penjualan',
      'sale_cancel' => 'Pembatalan penjualan',
      'service_order' => 'Pembayaran servis',
      'service_order_cancellation' => 'Pengembalian pembayaran servis batal',
      'purchase' => 'Pembelian pemasok',
      'purchase_payment' => 'Pembayaran pembelian pemasok',
      'purchase_cancel' => 'Pembatalan pembelian pemasok',
      'supplier_payment' => 'Pembayaran utang pemasok',
      'purchase_return' => 'Retur pembelian',
      'purchase_return_refund' => 'Refund retur pembelian',
      'purchase_return_cancel' => 'Pembatalan retur pembelian',
      'manual_cash' => 'Input manual',
      'customer_deposit' => 'Deposit pelanggan',
      'customer_wallet_withdrawal' => 'Penarikan saldo pelanggan',
      'tip' => 'Tip mekanik',
      'tip_handover' => 'Penyerahan tip',
      null || '' => 'Sumber tidak tercatat',
      _ => type,
    };
    return id == null || id.isEmpty ? 'Sumber: $source' : 'Sumber: $source • ID $id';
  }


  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Buku Kas')),
    body:FutureBuilder<Map<String,Object?>>(
      future:_future,
      builder:(context,snapshot) {
        if(snapshot.connectionState==ConnectionState.waiting) return const Center(child:CircularProgressIndicator());
        if(snapshot.hasError) return Center(child:Text('Gagal memuat buku kas: ${snapshot.error}'));
        final data=snapshot.data ?? {};
        final entries=(data['entries'] as List?) ?? [];
        final auditIssues=(data['audit_issues'] as List?) ?? [];
        final supplierMismatches=(data['supplier_mismatches'] as List?) ?? [];
        final customerMismatches=(data['customer_mismatches'] as List?) ?? [];
        final income=(data['income'] as num?)?.toInt() ?? 0;
        final expense=(data['expense'] as num?)?.toInt() ?? 0;
        return RefreshIndicator(onRefresh:() async=>_refresh(),child:ListView(
          padding:const EdgeInsets.fromLTRB(12,8,12,88),
          children:[
            Row(children:[
              Expanded(child:DropdownButtonFormField<String>(
                initialValue:_period,
                decoration:const InputDecoration(labelText:'Periode',isDense:true),
                items:const [
                  DropdownMenuItem(value:'today',child:Text('Hari ini')),
                  DropdownMenuItem(value:'month',child:Text('Bulan ini')),
                  DropdownMenuItem(value:'all',child:Text('Semua waktu')),
                ],
                onChanged:(v){if(v!=null)setState(()=>_period=v);_refresh();},
              )),
              const SizedBox(width:8),
              Expanded(child:DropdownButtonFormField<String>(
                initialValue:_type,
                decoration:const InputDecoration(labelText:'Jenis',isDense:true),
                items:const [
                  DropdownMenuItem(value:'all',child:Text('Semua')),
                  DropdownMenuItem(value:'income',child:Text('Kas masuk')),
                  DropdownMenuItem(value:'expense',child:Text('Kas keluar')),
                ],
                onChanged:(v){setState(()=>_type=v ?? 'all');_refresh();},
              )),
            ]),
            const SizedBox(height:10),
            Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(children:[
              _balanceLine('Saldo dana awal',data['opening_balance']),
              const Divider(height:14),
              _balanceLine('Dana masuk',income,color:Colors.green),
              _balanceLine('Dana keluar',expense,color:Colors.red),
              const Divider(height:14),
              _balanceLine('Saldo dana akhir',data['closing_balance'],bold:true),
            ]))),
            const SizedBox(height:8),
            Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Text('Ringkasan Kas Tunai',style:TextStyle(fontWeight:FontWeight.bold)),
                _balanceLine('Saldo awal',data['cash_opening_balance']),
                _balanceLine('Penerimaan tunai',data['cash_income'],color:Colors.green),
                _balanceLine('Pengeluaran tunai',data['cash_expense'],color:Colors.red),
                const Divider(height:14),
                _balanceLine('Saldo kas tunai',data['cash_closing_balance'],bold:true),
              ],
            ))),
            Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                const Text('Ringkasan Kas Nontunai',style:TextStyle(fontWeight:FontWeight.bold)),
                _balanceLine('Saldo awal',data['non_cash_opening_balance']),
                _balanceLine('Penerimaan nontunai',data['non_cash_income'],color:Colors.green),
                _balanceLine('Pengeluaran nontunai',data['non_cash_expense'],color:Colors.red),
                const Divider(height:14),
                _balanceLine('Saldo kas nontunai',data['non_cash_closing_balance'],bold:true),
                const Divider(height:14),
                const Text('Rincian metode nontunai',style:TextStyle(fontWeight:FontWeight.w600,fontSize:12)),
                ...((data['payment_method_totals'] as Map<String,int>? ?? {}).entries
                  .where((entry)=>!['cash','tunai'].contains(entry.key))
                  .map((entry)=>_balanceLine(switch(entry.key){'bank_transfer'=>'Transfer Bank','qris'=>'QRIS',_=>entry.key},entry.value))),
              ],
            ))),
            const SizedBox(height:8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.fact_check_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Pemeriksaan referensi kas', style: TextStyle(fontWeight: FontWeight.w600))),
                      Text('${auditIssues.length}', style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: auditIssues.isEmpty ? Colors.green : Colors.deepOrange,
                      )),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      auditIssues.isEmpty
                        ? 'Tidak ditemukan referensi kas bermasalah pada periode ini.'
                        : 'Ada transaksi yang perlu diperiksa. Data tidak diubah otomatis.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (auditIssues.isNotEmpty) ...[
                      const Divider(height: 12),
                      ...auditIssues.take(8).map((raw) {
                        final issue = raw as Map<String, Object?>;
                        final amount = (issue['amount'] as num?)?.toInt() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            'ID ${issue['id']} • ${issue['audit_issue']} • ${_money(amount)}',
                            style: const TextStyle(fontSize: 11, color: Colors.deepOrange),
                          ),
                        );
                      }),
                      if (auditIssues.length > 8)
                        Text('Dan ${auditIssues.length - 8} transaksi lainnya.', style: const TextStyle(fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height:8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.compare_arrows, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Cocokkan pembayaran pemasok', style: TextStyle(fontWeight: FontWeight.w600))),
                      Text('${supplierMismatches.length}', style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: supplierMismatches.isEmpty ? Colors.green : Colors.deepOrange,
                      )),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      supplierMismatches.isEmpty
                        ? 'Riwayat pembayaran pemasok sesuai dengan kas keluar pada periode ini.'
                        : 'Ada perbedaan antara riwayat pembayaran faktur dan kas keluar. Periksa sebelum melakukan koreksi.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (supplierMismatches.isNotEmpty) ...[
                      const Divider(height: 12),
                      ...supplierMismatches.take(8).map((raw) {
                        final item = raw as Map<String, Object?>;
                        final storedPaid = (item['stored_paid_total'] as num?)?.toInt() ?? 0;
                        final history = (item['payment_history_total'] as num?)?.toInt() ?? 0;
                        final cash = (item['cash_out_total'] as num?)?.toInt() ?? 0;
                        final difference = (item['difference'] as num?)?.toInt() ?? 0;
                        final storedDifference = (item['stored_paid_difference'] as num?)?.toInt() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item['invoice_number'] ?? 'Faktur'} • ${item['supplier_name'] ?? 'Pemasok'}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              Text('Faktur: ${_money(storedPaid)}  |  Riwayat: ${_money(history)}',
                                style: const TextStyle(fontSize: 10)),
                              Text('Kas keluar: ${_money(cash)}  |  Selisih faktur-riwayat: ${_money(storedDifference)}',
                                style: const TextStyle(fontSize: 10)),
                              Text('Selisih riwayat-kas: ${_money(difference)}',
                                style: const TextStyle(fontSize: 10, color: Colors.deepOrange)),
                            ],
                          ),
                        );
                      }),
                      if (supplierMismatches.length > 8)
                        Text('Dan ${supplierMismatches.length - 8} faktur lainnya.', style: const TextStyle(fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height:8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.people_alt_outlined, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Cocokkan pembayaran pelanggan', style: TextStyle(fontWeight: FontWeight.w600))),
                      Text('${customerMismatches.length}', style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: customerMismatches.isEmpty ? Colors.green : Colors.deepOrange,
                      )),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      customerMismatches.isEmpty
                        ? 'Nilai pembayaran penjualan dan servis sesuai dengan riwayat kas masuk.'
                        : 'Ada perbedaan nilai pembayaran pada nota pelanggan. Data tidak dikoreksi otomatis.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    if (customerMismatches.isNotEmpty) ...[
                      const Divider(height: 12),
                      ...customerMismatches.take(8).map((raw) {
                        final item = raw as Map<String, Object?>;
                        final stored = (item['stored_paid_total'] as num?)?.toInt() ?? 0;
                        final history = (item['payment_history_total'] as num?)?.toInt() ?? 0;
                        final difference = (item['difference'] as num?)?.toInt() ?? 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item['document_type']} ${item['document_number'] ?? '-'} • ${item['customer_name'] ?? '-'}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              Text('Nilai tersimpan: ${_money(stored)}  |  Riwayat kas: ${_money(history)}',
                                style: const TextStyle(fontSize: 10)),
                              Text('Selisih: ${_money(difference)}',
                                style: const TextStyle(fontSize: 10, color: Colors.deepOrange)),
                            ],
                          ),
                        );
                      }),
                      if (customerMismatches.length > 8)
                        Text('Dan ${customerMismatches.length - 8} nota lainnya.', style: const TextStyle(fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height:8),
            Text('Riwayat Transaksi (${data['count'] ?? 0})',style:Theme.of(context).textTheme.titleMedium),
            if(entries.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('Belum ada transaksi pada periode ini.')))
            else ...entries.map((raw) {
              final row=raw as Map<String,Object?>;
              final incomeRow=row['transaction_type']=='income';
              final amount=(row['amount'] as num?)?.toInt() ?? 0;
              final balance=(row['running_balance'] as num?)?.toInt() ?? 0;
              return Card(child:ListTile(
                dense:true,
                leading:Icon(incomeRow?Icons.south_west:Icons.north_east,color:incomeRow?Colors.green:Colors.red),
                title:Text(row['description']?.toString() ?? row['category']?.toString() ?? 'Transaksi'),
                subtitle:Text('${row['category'] ?? '-'} • ${row['transaction_date'] ?? ''}\n${_sourceLabel(row)}'),
                trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[
                  Text('${incomeRow?'+':'-'}${_money(amount)}',style:TextStyle(fontWeight:FontWeight.w600,color:incomeRow?Colors.green:Colors.red,fontSize:12)),
                  Text('Saldo ${_money(balance)}',style:const TextStyle(fontSize:10,color:Colors.grey)),
                ]),
              ));
            }),
          ],
        ));
      },
    ),
  );

  Widget _balanceLine(String label,Object? amount,{Color? color,bool bold=false}) => Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Text(label,style:TextStyle(fontSize:12,fontWeight:bold?FontWeight.bold:FontWeight.normal)),
      Text(_money(amount),style:TextStyle(fontSize:bold?16:13,fontWeight:bold?FontWeight.bold:FontWeight.w600,color:color)),
    ]),
  );
}
