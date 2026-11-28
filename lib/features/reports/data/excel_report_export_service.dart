import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';
import 'report_repository.dart';

/// Membuat workbook XLSX offline dari XML Spreadsheet dan ZIP yang sudah dipakai aplikasi.
class ExcelReportExportService {
  Future<void> exportAndShare({required DateTime start, required DateTime end}) async {
    AuthSession.instance.requireCashierOrAdmin('Ekspor laporan hanya dapat diakses Admin dan Kasir.');
    final db = await AppDatabase.instance.database;
    final sheets = <String, List<List<Object?>>>{};
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    void add(String name, List<String> headers, List<Map<String,Object?>> rows, List<String> fields) {
      sheets[name] = <List<Object?>>[headers, ...rows.map((row) => fields.map((field) => row[field]).toList())];
    }
    final summary = await ReportRepository().getSummary(start: start, end: end);
    sheets['Ringkasan'] = <List<Object?>>[
      ['LAPORAN BENGKELKU POS'],
      ['Periode', _date(start) + ' s.d. ' + _date(end.subtract(const Duration(days:1)))],
      ['Keterangan', 'Nilai'],
      ...<List<Object?>>[
        ['Dana masuk',summary['income']], ['Dana keluar',summary['expense']], ['Arus dana bersih',summary['net_cash_flow']],
        ['Penjualan bersih',summary['net_sales_amount']], ['Retur penjualan',summary['sales_return_amount']],
        ['HPP bersih barang',summary['net_cogs_amount']], ['Laba kotor barang',summary['gross_profit_amount']],
        ['Pendapatan servis selesai',summary['service_revenue']], ['Biaya langsung servis',summary['service_direct_cost_amount']],
        ['Laba kotor servis',summary['service_gross_profit_amount']], ['Total laba kotor',summary['combined_gross_profit_amount']],
        ['Pengeluaran operasional',summary['manual_operating_expense_amount']],
        ['Sisa setelah beban tercatat',summary['profit_after_recorded_operating_expense']],
        ['Piutang pelanggan saat ini',summary['customer_receivable_amount']], ['Utang saat ini',summary['supplier_payable_amount']],
        ['Saldo deposit pelanggan',summary['customer_wallet_balance']], ['Produk stok menipis',summary['low_stock']],
      ],
    ];
    add('Penjualan', ['No Nota','Tanggal','Pelanggan','Subtotal','Diskon','Pajak','Total','Dibayar','Kembalian','Metode','Status'], await db.rawQuery('''
      SELECT invoice_number,transaction_date,COALESCE(customer_name,'Pembeli Umum') customer_name,subtotal,discount,tax,total,paid,change_amount,payment_method,payment_status FROM sales
      WHERE datetime(transaction_date)>=datetime(?) AND datetime(transaction_date)<datetime(?) ORDER BY transaction_date,id
    ''',[from,until]), ['invoice_number','transaction_date','customer_name','subtotal','discount','tax','total','paid','change_amount','payment_method','payment_status']);
    add('Pembelian', ['No Nota','Tanggal','Jenis','Toko/Pemasok','Subtotal','Diskon','Total','Dibayar','Kredit Retur','Sisa','Status'], await db.rawQuery('''
      SELECT p.invoice_number,p.purchase_date,CASE WHEN p.purchase_type='online' THEN 'Online' ELSE 'Langsung' END kind,
      CASE WHEN p.purchase_type='online' THEN COALESCE(p.marketplace,'Toko Online') ELSE COALESCE(s.name,'-') END counterparty,
      p.subtotal,p.discount,p.total,p.paid,COALESCE(p.return_credit,0) return_credit,MAX(0,p.total-p.paid-COALESCE(p.return_credit,0)) remaining,p.payment_status
      FROM purchases p LEFT JOIN suppliers s ON s.id=p.supplier_id WHERE datetime(p.purchase_date)>=datetime(?) AND datetime(p.purchase_date)<datetime(?) ORDER BY p.purchase_date,p.id
    ''',[from,until]), ['invoice_number','purchase_date','kind','counterparty','subtotal','discount','total','paid','return_credit','remaining','payment_status']);
    add('Servis', ['No Servis','Diterima','Selesai','Pelanggan','Telepon','Sepeda','Mekanik','Status','Total','DP','Sisa'], await db.rawQuery('''
      SELECT order_number,received_at,completed_at,COALESCE(customer_name,(SELECT name FROM customers c WHERE c.id=service_orders.customer_id),'Pelanggan Umum') customer,customer_phone,
      TRIM(COALESCE(bicycle_brand,'')||' '||COALESCE(bicycle_model,'')) bicycle,mechanic_name,service_status,total_cost,down_payment,remaining_payment FROM service_orders
      WHERE datetime(received_at)>=datetime(?) AND datetime(received_at)<datetime(?) ORDER BY received_at,id
    ''',[from,until]), ['order_number','received_at','completed_at','customer','customer_phone','bicycle','mechanic_name','service_status','total_cost','down_payment','remaining_payment']);
    add('Buku Kas', ['Tanggal','Jenis','Kategori','Keterangan','Nominal','Metode'], await db.rawQuery('''
      SELECT transaction_date,transaction_type,category,description,amount,payment_method FROM cash_transactions WHERE COALESCE(reference_type,'') NOT IN ('tip','tip_handover')
      AND datetime(transaction_date)>=datetime(?) AND datetime(transaction_date)<datetime(?) ORDER BY transaction_date,id
    ''',[from,until]), ['transaction_date','transaction_type','category','description','amount','payment_method']);
    add('Persediaan', ['SKU','Nama Barang','Kategori','Satuan','Stok','Nilai Modal','Nilai Jual'], await ReportRepository().getCurrentStockValuationItems(), ['sku','product_name','category','unit','stock','cost_value','selling_value']);
    add('Piutang', ['Jenis','No Nota','Tanggal','Pelanggan','Tagihan','Dibayar','Sisa'], await db.rawQuery('''
      SELECT 'Penjualan' kind,s.invoice_number invoice,s.transaction_date date,COALESCE(s.customer_name,'Pembeli Umum') customer,MAX(0,s.total-COALESCE(r.returned,0)) billed,
      MAX(0,s.paid-COALESCE(r.refunded,0)) paid,MAX(0,s.total-COALESCE(r.returned,0)-s.paid+COALESCE(r.refunded,0)) remaining FROM sales s
      LEFT JOIN (SELECT sale_id,SUM(total_amount) returned,SUM(refunded_amount) refunded FROM sale_returns GROUP BY sale_id) r ON r.sale_id=s.id
      WHERE COALESCE(s.payment_status,'paid')!='cancelled' AND s.total-COALESCE(r.returned,0)-s.paid+COALESCE(r.refunded,0)>0
      UNION ALL SELECT 'Servis',order_number,received_at,COALESCE(customer_name,'Pelanggan Umum'),total_cost,down_payment,remaining_payment FROM service_orders WHERE remaining_payment>0 AND service_status!='cancelled' ORDER BY date DESC
    '''), ['kind','invoice','date','customer','billed','paid','remaining']);
    add('Utang', ['Jenis','No Nota','Tanggal','Pemasok/Toko Online','Total','Dibayar','Kredit Retur','Sisa'], await db.rawQuery('''
      SELECT CASE WHEN p.purchase_type='online' THEN 'Online' ELSE 'Pemasok' END kind,p.invoice_number,p.purchase_date,CASE WHEN p.purchase_type='online' THEN COALESCE(p.marketplace,'Toko Online') ELSE COALESCE(s.name,'-') END counterparty,
      p.total,p.paid,COALESCE(p.return_credit,0) return_credit,MAX(0,p.total-p.paid-COALESCE(p.return_credit,0)) remaining FROM purchases p LEFT JOIN suppliers s ON s.id=p.supplier_id
      WHERE p.status='active' AND p.total>p.paid+COALESCE(p.return_credit,0) ORDER BY p.purchase_date DESC
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
      SELECT received_at,source_type,source_id,recipient_name,amount,payment_method,status,handed_over_at FROM tip_transactions WHERE datetime(received_at)>=datetime(?) AND datetime(received_at)<datetime(?) ORDER BY received_at,id
    ''',[from,until]), ['received_at','source_type','source_id','recipient_name','amount','payment_method','status','handed_over_at']);
    final archive = Archive();
    archive.addFile(ArchiveFile('[Content_Types].xml', 0, utf8.encode(_contentTypes(sheets.length))));
    archive.addFile(ArchiveFile('_rels/.rels', 0, utf8.encode(_rootRels)));
    archive.addFile(ArchiveFile('xl/workbook.xml', 0, utf8.encode(_workbook(sheets.keys.toList()))));
    archive.addFile(ArchiveFile('xl/_rels/workbook.xml.rels', 0, utf8.encode(_workbookRels(sheets.length))));
    var index = 1;
    for (final entry in sheets.entries) { archive.addFile(ArchiveFile('xl/worksheets/sheet'+index.toString()+'.xml', 0, utf8.encode(_worksheet(entry.value)))); index++; }
    final bytes = ZipEncoder().encode(archive);
    if (bytes.isEmpty) throw StateError('Workbook Excel gagal dibuat.');
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().replaceAll(':','-').replaceAll('.','-');
    final file = File(p.join(dir.path,'Laporan_BengkelKu_'+stamp+'.xlsx'));
    await file.writeAsBytes(bytes,flush:true);
    await SharePlus.instance.share(ShareParams(title:'Laporan BengkelKu POS',text:'Laporan Excel BengkelKu POS.',files:[XFile(file.path)]));
  }
  String _contentTypes(int count) {
    final overrides = List.generate(count,(i) => '<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'+overrides+'</Types>';
  }
  String get _rootRels => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>';
  String _workbook(List<String> names) {
    final sheets = List.generate(names.length,(i) => '<sheet name="${_xml(names[i])}" sheetId="${i+1}" r:id="rId${i+1}"/>').join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'+sheets+'</sheets></workbook>';
  }
  String _workbookRels(int count) {
    final rels = List.generate(count,(i) => '<Relationship Id="rId${i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i+1}.xml"/>').join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'+rels+'</Relationships>';
  }
  String _worksheet(List<List<Object?>> rows) {
    final out = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
    for (var r=0;r<rows.length;r++) {
      out.write('<row r="${r+1}">');
      for (var c=0;c<rows[r].length;c++) {
        final value = rows[r][c]; final ref = _column(c+1)+(r+1).toString();
        if (value == null) { out.write('<c r="$ref"/>'); }
        else if (value is bool) { out.write('<c r="$ref" t="b"><v>${value ? 1 : 0}</v></c>'); }
        else if (value is num) { out.write('<c r="$ref"><v>${value}</v></c>'); }
        else { out.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xml(value.toString())}</t></is></c>'); }
      }
      out.write('</row>');
    }
    out.write('</sheetData></worksheet>'); return out.toString();
  }
  String _column(int n) { var out=''; while(n>0){ final rem=(n-1)%26; out=String.fromCharCode(65+rem)+out; n=(n-1)~/26; } return out; }
  String _xml(String value) => value.replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&apos;');
  String _date(DateTime d) => d.year.toString().padLeft(4,'0')+'-'+d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
}