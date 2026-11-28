import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';
import 'report_repository.dart';

class ExcelReportExportService {
  Future<void> exportAndShare({required DateTime start, required DateTime end}) async {
    AuthSession.instance.requireCashierOrAdmin('Ekspor laporan hanya dapat diakses Admin dan Kasir.');
    final db = await AppDatabase.instance.database;
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Ringkasan');
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    void add(String name, List<String> headers, List<Map<String,Object?>> rows, List<String> fields) {
      final sheet = excel[name];
      sheet.appendRow(headers.map((v) => TextCellValue(v)).toList());
      for (final row in rows) { sheet.appendRow(fields.map((f) => _cell(row[f])).toList()); }
    }
    final summary = await ReportRepository().getSummary(start: start, end: end);
    final overview = excel['Ringkasan'];
    overview.appendRow([TextCellValue('LAPORAN BENGKELKU POS')]);
    overview.appendRow([TextCellValue('Periode'), TextCellValue(_date(start) + ' s.d. ' + _date(end.subtract(const Duration(days:1))))]);
    overview.appendRow([TextCellValue('Keterangan'), TextCellValue('Nilai')]);
    const metrics = <List<String>>[
      ['Dana masuk','income'], ['Dana keluar','expense'], ['Arus dana bersih','net_cash_flow'],
      ['Penjualan bersih','net_sales_amount'], ['Retur penjualan','sales_return_amount'],
      ['HPP bersih barang','net_cogs_amount'], ['Laba kotor barang','gross_profit_amount'],
      ['Pendapatan servis selesai','service_revenue'], ['Biaya langsung servis','service_direct_cost_amount'],
      ['Laba kotor servis','service_gross_profit_amount'], ['Total laba kotor','combined_gross_profit_amount'],
      ['Pengeluaran operasional','manual_operating_expense_amount'],
      ['Sisa setelah beban tercatat','profit_after_recorded_operating_expense'],
      ['Piutang pelanggan saat ini','customer_receivable_amount'], ['Utang saat ini','supplier_payable_amount'],
      ['Saldo deposit pelanggan','customer_wallet_balance'], ['Produk stok menipis','low_stock'],
    ];
    for (final metric in metrics) { overview.appendRow([TextCellValue(metric[0]), _cell(summary[metric[1]])]); }
    add('Penjualan', ['No Nota','Tanggal','Pelanggan','Subtotal','Diskon','Pajak','Total','Dibayar','Kembalian','Metode','Status'], await db.rawQuery('''
      SELECT invoice_number, transaction_date, COALESCE(customer_name,'Pembeli Umum') customer_name, subtotal, discount, tax, total, paid, change_amount, payment_method, payment_status
      FROM sales WHERE datetime(transaction_date)>=datetime(?) AND datetime(transaction_date)<datetime(?) ORDER BY transaction_date,id
    ''',[from,until]), ['invoice_number','transaction_date','customer_name','subtotal','discount','tax','total','paid','change_amount','payment_method','payment_status']);
    add('Pembelian', ['No Nota','Tanggal','Jenis','Toko/Pemasok','Subtotal','Diskon','Total','Dibayar','Kredit Retur','Sisa','Status'], await db.rawQuery('''
      SELECT p.invoice_number,p.purchase_date,CASE WHEN p.purchase_type='online' THEN 'Online' ELSE 'Langsung' END kind,
      CASE WHEN p.purchase_type='online' THEN COALESCE(p.marketplace,'Toko Online') ELSE COALESCE(s.name,'-') END counterparty,
      p.subtotal,p.discount,p.total,p.paid,COALESCE(p.return_credit,0) return_credit,MAX(0,p.total-p.paid-COALESCE(p.return_credit,0)) remaining,p.payment_status
      FROM purchases p LEFT JOIN suppliers s ON s.id=p.supplier_id
      WHERE datetime(p.purchase_date)>=datetime(?) AND datetime(p.purchase_date)<datetime(?) ORDER BY p.purchase_date,p.id
    ''',[from,until]), ['invoice_number','purchase_date','kind','counterparty','subtotal','discount','total','paid','return_credit','remaining','payment_status']);
    add('Servis', ['No Servis','Diterima','Selesai','Pelanggan','Telepon','Sepeda','Mekanik','Status','Total','DP','Sisa'], await db.rawQuery('''
      SELECT order_number,received_at,completed_at,COALESCE(customer_name,(SELECT name FROM customers c WHERE c.id=service_orders.customer_id),'Pelanggan Umum') customer,customer_phone,
      TRIM(COALESCE(bicycle_brand,'')||' '||COALESCE(bicycle_model,'')) bicycle,mechanic_name,service_status,total_cost,down_payment,remaining_payment
      FROM service_orders WHERE datetime(received_at)>=datetime(?) AND datetime(received_at)<datetime(?) ORDER BY received_at,id
    ''',[from,until]), ['order_number','received_at','completed_at','customer','customer_phone','bicycle','mechanic_name','service_status','total_cost','down_payment','remaining_payment']);
    add('Buku Kas', ['Tanggal','Jenis','Kategori','Keterangan','Nominal','Metode'], await db.rawQuery('''
      SELECT transaction_date,transaction_type,category,description,amount,payment_method FROM cash_transactions
      WHERE COALESCE(reference_type,'') NOT IN ('tip','tip_handover') AND datetime(transaction_date)>=datetime(?) AND datetime(transaction_date)<datetime(?) ORDER BY transaction_date,id
    ''',[from,until]), ['transaction_date','transaction_type','category','description','amount','payment_method']);
    add('Persediaan', ['SKU','Nama Barang','Kategori','Satuan','Stok','Nilai Modal','Nilai Jual'], await ReportRepository().getCurrentStockValuationItems(), ['sku','product_name','category','unit','stock','cost_value','selling_value']);
    add('Piutang', ['Jenis','No Nota','Tanggal','Pelanggan','Tagihan','Dibayar','Sisa'], await db.rawQuery('''
      SELECT 'Penjualan' kind,s.invoice_number invoice,s.transaction_date date,COALESCE(s.customer_name,'Pembeli Umum') customer,
      MAX(0,s.total-COALESCE(r.returned,0)) billed,MAX(0,s.paid-COALESCE(r.refunded,0)) paid,
      MAX(0,s.total-COALESCE(r.returned,0)-s.paid+COALESCE(r.refunded,0)) remaining FROM sales s
      LEFT JOIN (SELECT sale_id,SUM(total_amount) returned,SUM(refunded_amount) refunded FROM sale_returns GROUP BY sale_id) r ON r.sale_id=s.id
      WHERE COALESCE(s.payment_status,'paid')!='cancelled' AND s.total-COALESCE(r.returned,0)-s.paid+COALESCE(r.refunded,0)>0
      UNION ALL SELECT 'Servis',order_number,received_at,COALESCE(customer_name,'Pelanggan Umum'),total_cost,down_payment,remaining_payment FROM service_orders WHERE remaining_payment>0 AND service_status!='cancelled' ORDER BY date DESC
    '''), ['kind','invoice','date','customer','billed','paid','remaining']);
    add('Utang', ['Jenis','No Nota','Tanggal','Pemasok/Toko Online','Total','Dibayar','Kredit Retur','Sisa'], await db.rawQuery('''
      SELECT CASE WHEN p.purchase_type='online' THEN 'Online' ELSE 'Pemasok' END kind,p.invoice_number,p.purchase_date,
      CASE WHEN p.purchase_type='online' THEN COALESCE(p.marketplace,'Toko Online') ELSE COALESCE(s.name,'-') END counterparty,
      p.total,p.paid,COALESCE(p.return_credit,0) return_credit,MAX(0,p.total-p.paid-COALESCE(p.return_credit,0)) remaining
      FROM purchases p LEFT JOIN suppliers s ON s.id=p.supplier_id WHERE p.status='active' AND p.total>p.paid+COALESCE(p.return_credit,0) ORDER BY p.purchase_date DESC
    '''), ['kind','invoice_number','purchase_date','counterparty','total','paid','return_credit','remaining']);
    add('Retur Penjualan', ['No Retur','Nota Asal','Tanggal','Nilai Retur','Refund','Catatan'], await db.rawQuery('''
      SELECT r.return_number,s.invoice_number,r.return_date,r.total_amount,r.refunded_amount,r.notes FROM sale_returns r JOIN sales s ON s.id=r.sale_id
      WHERE datetime(r.return_date)>=datetime(?) AND datetime(r.return_date)<datetime(?) ORDER BY r.return_date,r.id
    ''',[from,until]), ['return_number','invoice_number','return_date','total_amount','refunded_amount','notes']);
    add('Retur Pembelian', ['No Retur','Nota Asal','Tanggal','Nilai Retur','Kredit','Refund','Catatan'], await db.rawQuery('''
      SELECT r.return_number,p.invoice_number,r.return_date,r.total_amount,r.credit_applied,r.refund_received,r.notes FROM purchase_returns r JOIN purchases p ON p.id=r.purchase_id
      WHERE r.status='active' AND datetime(r.return_date)>=datetime(?) AND datetime(r.return_date)<datetime(?) ORDER BY r.return_date,r.id
    ''',[from,until]), ['return_number','invoice_number','return_date','total_amount','credit_applied','refund_received','notes']);
    add('Uang Tip', ['Tanggal Terima','Sumber','ID Sumber','Penerima','Nominal','Metode','Status','Tanggal Serah'], await db.rawQuery('''
      SELECT received_at,source_type,source_id,recipient_name,amount,payment_method,status,handed_over_at FROM tip_transactions
      WHERE datetime(received_at)>=datetime(?) AND datetime(received_at)<datetime(?) ORDER BY received_at,id
    ''',[from,until]), ['received_at','source_type','source_id','recipient_name','amount','payment_method','status','handed_over_at']);
    final bytes = excel.encode();
    if (bytes == null || bytes.isEmpty) throw StateError('Workbook Excel gagal dibuat.');
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':','-').replaceAll('.','-');
    final file = File(p.join(dir.path,'Laporan_BengkelKu_'+stamp+'.xlsx'));
    await file.writeAsBytes(bytes,flush:true);
    await SharePlus.instance.share(ShareParams(title:'Laporan BengkelKu POS',text:'Laporan Excel BengkelKu POS.',files:[XFile(file.path)]));
  }
  CellValue _cell(Object? value) {
    if (value == null) return TextCellValue('');
    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    return TextCellValue(value.toString());
  }
  String _date(DateTime d) => d.year.toString().padLeft(4,'0')+'-'+d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
}