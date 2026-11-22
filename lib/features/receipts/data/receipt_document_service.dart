import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class ReceiptDocumentService {
  static int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  static String rupiah(Object? value) {
    final digits = _int(value).toString();
    final out = StringBuffer('Rp');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static String dateLabel(Object? value) {
    final parsed = DateTime.tryParse(_text(value))?.toLocal();
    if (parsed == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  static Future<pw.MemoryImage?> _logo(Map<String, String> profile) async {
    final path = _text(profile['business_logo_path']);
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return pw.MemoryImage(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> buildSaleReceipt({
    required Map<String, Object?> sale,
    required List<Map<String, Object?>> payments,
    required Map<String, Object?> returnSummary,
    required Map<String, String> profile,
  }) async {
    final items = List<Map<String, Object?>>.from(sale['items'] as List? ?? const []);
    final logo = await _logo(profile);
    final doc = pw.Document();
    final height = 360.0 + items.length * 34.0 + payments.length * 25.0;
    final total = _int(sale['total']);
    final paid = _int(sale['paid']);
    final returned = _int(returnSummary['returned_amount']);
    final refunded = _int(returnSummary['refunded_amount']);
    final remaining = (total - paid - returned + refunded).clamp(0, 1 << 62).toInt();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(226.77, height, marginAll: 12),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(profile, logo),
          _center('NOTA PENJUALAN', bold: true, size: 12),
          pw.SizedBox(height: 5),
          _line('No. Nota', _text(sale['invoice_number'])),
          _line('Tanggal', dateLabel(sale['transaction_date'])),
          if (_text(sale['customer_name']).isNotEmpty) _line('Pelanggan', _text(sale['customer_name'])),
          if (_text(sale['customer_phone']).isNotEmpty) _line('Telepon', _text(sale['customer_phone'])),
          pw.Divider(),
          ...items.map((item) {
            final qty = _int(item['quantity']);
            final price = _int(item['unit_price']);
            final subtotal = _int(item['subtotal']);
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(_text(item['product_name']), style: const pw.TextStyle(fontSize: 9)),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('$qty x ${rupiah(price)}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(rupiah(subtotal), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                ]),
              ]),
            );
          }),
          pw.Divider(),
          _line('Subtotal', rupiah(sale['subtotal'])),
          _line('Diskon', rupiah(sale['discount'])),
          _line('Total', rupiah(total), bold: true),
          _line('Sudah dibayar', rupiah(paid)),
          if (returned > 0) _line('Total retur', rupiah(returned)),
          if (refunded > 0) _line('Uang dikembalikan', rupiah(refunded)),
          _line('Sisa tagihan', rupiah(remaining), bold: true),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text('RIWAYAT PEMBAYARAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ...payments.map((payment) => _line(
              dateLabel(payment['transaction_date']),
              rupiah(payment['amount']),
            )),
          ],
          if (_text(sale['notes']).isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Catatan: ${_text(sale['notes'])}', style: const pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 12),
          _center(_text(profile['business_footer_note']).isEmpty ? 'Terima kasih atas kunjungan Anda.' : _text(profile['business_footer_note']), size: 8),
        ],
      ),
    ));
    return doc.save();
  }

  static Future<Uint8List> buildServiceReceipt({
    required Map<String, Object?> service,
    required List<Map<String, Object?>> payments,
    required Map<String, String> profile,
  }) async {
    final logo = await _logo(profile);
    final doc = pw.Document();
    final height = 470.0 + payments.length * 25.0;
    final paid = _int(service['down_payment']);
    final total = _int(service['total_cost']);
    final remaining = _int(service['remaining_payment']);
    final bicycle = [
      _text(service['bicycle_brand']),
      _text(service['bicycle_model']),
    ].where((part) => part.isNotEmpty).join(' ');

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(226.77, height, marginAll: 12),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(profile, logo),
          _center('NOTA SERVIS', bold: true, size: 12),
          pw.SizedBox(height: 5),
          _line('No. Nota', _text(service['order_number'])),
          _line('Tanggal masuk', dateLabel(service['received_at'])),
          _line('Pelanggan', _text(service['customer_name'])),
          if (_text(service['customer_phone']).isNotEmpty) _line('Telepon', _text(service['customer_phone'])),
          if (bicycle.isNotEmpty) _line('Sepeda', bicycle),
          if (_text(service['bicycle_serial_number']).isNotEmpty) _line('No. rangka', _text(service['bicycle_serial_number'])),
          pw.Divider(),
          _line('Keluhan', _text(service['complaint'])),
          if (_text(service['diagnosis']).isNotEmpty) _line('Diagnosis', _text(service['diagnosis'])),
          if (_text(service['mechanic_name']).isNotEmpty) _line('Mekanik', _text(service['mechanic_name'])),
          pw.Divider(),
          _line('Jasa servis', rupiah(service['labor_cost'])),
          _line('Sparepart', rupiah(service['parts_cost'])),
          _line('Diskon', rupiah(service['discount'])),
          _line('Total biaya', rupiah(total), bold: true),
          _line('Sudah dibayar', rupiah(paid)),
          _line('Sisa tagihan', rupiah(remaining), bold: true),
          _line('Status', _text(service['service_status'])),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text('RIWAYAT PEMBAYARAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ...payments.map((payment) => _line(
              dateLabel(payment['transaction_date']),
              rupiah(payment['amount']),
            )),
          ],
          if (_text(service['notes']).isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Catatan: ${_text(service['notes'])}', style: const pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 12),
          _center(_text(profile['business_footer_note']).isEmpty ? 'Terima kasih telah mempercayakan sepeda Anda.' : _text(profile['business_footer_note']), size: 8),
        ],
      ),
    ));
    return doc.save();
  }

  static pw.Widget _header(Map<String, String> profile, pw.MemoryImage? logo) {
    final details = [
      _text(profile['business_address']),
      _text(profile['business_phone']),
      _text(profile['business_whatsapp']),
      _text(profile['business_email']),
    ].where((item) => item.isNotEmpty).toList();
    return pw.Column(children: [
      if (logo != null) pw.Container(height: 42, alignment: pw.Alignment.center, child: pw.Image(logo, fit: pw.BoxFit.contain)),
      if (_text(profile['business_name']).isNotEmpty)
        _center(_text(profile['business_name']), bold: true, size: 11),
      ...details.map((detail) => _center(detail, size: 7)),
      pw.SizedBox(height: 5),
    ]);
  }

  static pw.Widget _center(String text, {bool bold = false, double size = 8}) {
    return pw.Text(text, textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));
  }

  static pw.Widget _line(String label, String value, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(flex: 5, child: pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
        pw.SizedBox(width: 4),
        pw.Expanded(flex: 6, child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
      ]),
    );
  }
}
