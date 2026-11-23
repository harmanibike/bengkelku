import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../settings/data/receipt_settings_repository.dart';

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
    final settings = await ReceiptSettingsRepository().getReceiptSettings();
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
      pageFormat: PdfPageFormat(settings.paperWidthPoints, height, marginAll: settings.marginPoints),
      build: (context) => pw.Container(
        color: PdfColors.white,
        child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(profile, logo, settings),
          _center('NOTA PENJUALAN', bold: true, size: 12, settings: settings),
          pw.SizedBox(height: 5),
          _line('No. Nota', _text(sale['invoice_number']), settings: settings),
          _line('Tanggal', dateLabel(sale['transaction_date']), settings: settings),
          if (settings.showCustomerDetails && _text(sale['customer_name']).isNotEmpty) _line('Pelanggan', _text(sale['customer_name']), settings: settings),
          if (settings.showCustomerDetails && _text(sale['customer_phone']).isNotEmpty) _line('Telepon', _text(sale['customer_phone']), settings: settings),
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
          _line('Subtotal', rupiah(sale['subtotal']), settings: settings),
          _line('Diskon', rupiah(sale['discount']), settings: settings),
          _line('Total', rupiah(total), bold: true, settings: settings),
          _line('Sudah dibayar', rupiah(paid), settings: settings),
          if (returned > 0) _line('Total retur', rupiah(returned), settings: settings),
          if (refunded > 0) _line('Uang dikembalikan', rupiah(refunded), settings: settings),
          _line('Sisa tagihan', rupiah(remaining), bold: true, settings: settings),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text('RIWAYAT PEMBAYARAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ...payments.map((payment) => _line(
              dateLabel(payment['transaction_date']),
              rupiah(payment['amount']),
              settings: settings,
            )),
          ],
          if (settings.showTransactionNotes && _text(sale['notes']).isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Catatan: ${_text(sale['notes'])}', style: const pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 12),
          if (settings.showFooter) _center(_text(profile['business_footer_note']).isEmpty ? 'Terima kasih atas kunjungan Anda.' : _text(profile['business_footer_note']), size: 8, settings: settings),
        ],
      )),
    ));
    return doc.save();
  }

  static Future<Uint8List> buildServiceReceipt({
    required Map<String, Object?> service,
    required List<Map<String, Object?>> payments,
    required Map<String, String> profile,
  }) async {
    final settings = await ReceiptSettingsRepository().getReceiptSettings();
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
      pageFormat: PdfPageFormat(settings.paperWidthPoints, height, marginAll: settings.marginPoints),
      build: (context) => pw.Container(
        color: PdfColors.white,
        child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(profile, logo, settings),
          _center('NOTA SERVIS', bold: true, size: 12, settings: settings),
          pw.SizedBox(height: 5),
          _line('No. Nota', _text(service['order_number']), settings: settings),
          _line('Tanggal masuk', dateLabel(service['received_at']), settings: settings),
          if (settings.showCustomerDetails) _line('Pelanggan', _text(service['customer_name']), settings: settings),
          if (settings.showCustomerDetails && _text(service['customer_phone']).isNotEmpty) _line('Telepon', _text(service['customer_phone']), settings: settings),
          if (bicycle.isNotEmpty) _line('Sepeda', bicycle, settings: settings),
          if (_text(service['bicycle_serial_number']).isNotEmpty) _line('No. rangka', _text(service['bicycle_serial_number']), settings: settings),
          pw.Divider(),
          _line('Keluhan', _text(service['complaint']), settings: settings),
          if (_text(service['diagnosis']).isNotEmpty) _line('Diagnosis', _text(service['diagnosis']), settings: settings),
          if (_text(service['mechanic_name']).isNotEmpty) _line('Mekanik', _text(service['mechanic_name']), settings: settings),
          pw.Divider(),
          _line('Jasa servis', rupiah(service['labor_cost']), settings: settings),
          _line('Sparepart', rupiah(service['parts_cost']), settings: settings),
          _line('Diskon', rupiah(service['discount']), settings: settings),
          _line('Total biaya', rupiah(total), bold: true, settings: settings),
          _line('Sudah dibayar', rupiah(paid), settings: settings),
          _line('Sisa tagihan', rupiah(remaining), bold: true, settings: settings),
          _line('Status', _text(service['service_status']), settings: settings),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text('RIWAYAT PEMBAYARAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ...payments.map((payment) => _line(
              dateLabel(payment['transaction_date']),
              rupiah(payment['amount']),
              settings: settings,
            )),
          ],
          if (settings.showTransactionNotes && _text(service['notes']).isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Catatan: ${_text(service['notes'])}', style: const pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 12),
          if (settings.showFooter) _center(_text(profile['business_footer_note']).isEmpty ? 'Terima kasih telah mempercayakan sepeda Anda.' : _text(profile['business_footer_note']), size: 8, settings: settings),
        ],
      )),
    ));
    return doc.save();
  }


  static Future<Uint8List> buildServiceIntakeReceipt({
    required Map<String, Object?> service,
    required Map<String, String> profile,
  }) async {
    final settings = await ReceiptSettingsRepository().getReceiptSettings();
    final logo = await _logo(profile);
    final doc = pw.Document();
    final bicycle = [
      _text(service['bicycle_brand']),
      _text(service['bicycle_model']),
      _text(service['bicycle_type']),
    ].where((part) => part.isNotEmpty).join(' ');
    final height = 440.0 + (_text(service['notes']).isNotEmpty ? 35 : 0);
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(settings.paperWidthPoints, height, marginAll: settings.marginPoints),
      build: (context) => pw.Container(
        color: PdfColors.white,
        child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(profile, logo, settings),
          _center('BUKTI PENERIMAAN SEPEDA', bold: true, size: 11, settings: settings),
          _center('DOKUMEN SAAT SEPEDA MASUK BENGKEL', size: 7, settings: settings),
          pw.SizedBox(height: 7),
          _line('No. Dokumen', '${_text(service['order_number'])}-TERIMA', settings: settings),
          _line('No. Servis', _text(service['order_number']), settings: settings),
          _line('Tanggal diterima', dateLabel(service['received_at']), settings: settings),
          pw.Divider(),
          _center('DATA PELANGGAN', bold: true, settings: settings),
          if (settings.showCustomerDetails) _line('Nama', _text(service['customer_name']), settings: settings),
          if (settings.showCustomerDetails) _line('Telepon', _text(service['customer_phone']), settings: settings),
          if (settings.showCustomerDetails) _line('Alamat', _text(service['customer_address']), settings: settings),
          pw.Divider(),
          _center('IDENTITAS SEPEDA', bold: true, settings: settings),
          _line('Sepeda', bicycle, settings: settings),
          _line('Warna', _text(service['bicycle_color']), settings: settings),
          _line('Ukuran frame', _text(service['bicycle_frame_size']), settings: settings),
          _line('Nomor rangka', _text(service['bicycle_serial_number']), settings: settings),
          pw.Divider(),
          _center('KONDISI / KELUHAN SAAT DITERIMA', bold: true, settings: settings),
          _line('Keluhan', _text(service['complaint']), settings: settings),
          if (_text(service['diagnosis']).isNotEmpty)
            _line('Pemeriksaan awal', _text(service['diagnosis']), settings: settings),
          if (_text(service['before_photo_path']).isNotEmpty)
            _line('Dokumentasi foto', 'Foto kondisi awal tersimpan di aplikasi', settings: settings),
          if (_text(service['mechanic_name']).isNotEmpty)
            _line('Mekanik', _text(service['mechanic_name']), settings: settings),
          if (settings.showTransactionNotes && _text(service['notes']).isNotEmpty)
            _line('Catatan', _text(service['notes']), settings: settings),
          pw.Divider(),
          _line('Estimasi biaya', rupiah(service['estimated_cost']), settings: settings),
          _line('Status servis', _text(service['service_status']), settings: settings),
          pw.SizedBox(height: 12),
          _center('Dokumen ini merupakan bukti penerimaan sepeda, bukan bukti pelunasan.', size: 7, settings: settings),
          pw.SizedBox(height: 10),
          if (settings.showFooter) _center(_text(profile['business_footer_note']).isEmpty
              ? 'Simpan dokumen ini untuk pengambilan sepeda.'
              : _text(profile['business_footer_note']), size: 8, settings: settings),
        ],
      )),
    ));
    return doc.save();
  }

  static Future<Uint8List> buildServiceFinalPaymentReceipt({
    required Map<String, Object?> service,
    required List<Map<String, Object?>> payments,
    required Map<String, String> profile,
  }) async {
    final settings = await ReceiptSettingsRepository().getReceiptSettings();
    final logo = await _logo(profile);
    final doc = pw.Document();
    final height = 390.0 + payments.length * 25.0;
    final total = _int(service['total_cost']);
    final remaining = _int(service['remaining_payment']);
    final paid = (total - remaining).clamp(0, 1 << 62).toInt();
    final bicycle = [
      _text(service['bicycle_brand']),
      _text(service['bicycle_model']),
    ].where((part) => part.isNotEmpty).join(' ');
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(settings.paperWidthPoints, height, marginAll: settings.marginPoints),
      build: (context) => pw.Container(
        color: PdfColors.white,
        child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _header(profile, logo, settings),
          _center('BUKTI PELUNASAN SERVIS', bold: true, size: 12, settings: settings),
          _center('PEMBAYARAN TELAH LUNAS', bold: true, size: 8, settings: settings),
          pw.SizedBox(height: 7),
          _line('No. Dokumen', '${_text(service['order_number'])}-LUNAS', settings: settings),
          _line('No. Servis', _text(service['order_number']), settings: settings),
          _line('Tanggal masuk', dateLabel(service['received_at']), settings: settings),
          if (settings.showCustomerDetails) _line('Pelanggan', _text(service['customer_name']), settings: settings),
          if (settings.showCustomerDetails && _text(service['customer_phone']).isNotEmpty)
            _line('Telepon', _text(service['customer_phone']), settings: settings),
          if (bicycle.isNotEmpty) _line('Sepeda', bicycle, settings: settings),
          pw.Divider(),
          _line('Total biaya servis', rupiah(total), settings: settings),
          _line('Total pembayaran diterima', rupiah(paid), bold: true, settings: settings),
          _line('Sisa tagihan', rupiah(remaining), bold: true, settings: settings),
          if (payments.isNotEmpty) ...[
            pw.SizedBox(height: 7),
            pw.Text('RIWAYAT PEMBAYARAN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            ...payments.map((payment) => _line(
              dateLabel(payment['transaction_date']),
              rupiah(payment['amount']),
              settings: settings,
            )),
          ],
          pw.Divider(),
          _center('LUNAS - TIDAK ADA SISA TAGIHAN', bold: true, size: 9, settings: settings),
          _center('Terima kasih atas kepercayaan Anda.', size: 8, settings: settings),
          pw.SizedBox(height: 10),
          if (settings.showFooter) _center(_text(profile['business_footer_note']), size: 8, settings: settings),
        ],
      )),
    ));
    return doc.save();
  }

  static pw.Widget _header(Map<String, String> profile, pw.MemoryImage? logo, ReceiptPrintSettings settings) {
    final details = [
      if (settings.showBusinessAddress) _text(profile['business_address']),
      if (settings.showBusinessContact) _text(profile['business_phone']),
      if (settings.showBusinessContact) _text(profile['business_whatsapp']),
      if (settings.showBusinessContact) _text(profile['business_email']),
    ].where((item) => item.isNotEmpty).toList();
    return pw.Column(children: [
      if (settings.showLogo && logo != null) pw.Container(height: 32, alignment: pw.Alignment.center, child: pw.Image(logo, fit: pw.BoxFit.contain)),
      if (settings.showBusinessName && _text(profile['business_name']).isNotEmpty)
        _center(_text(profile['business_name']), bold: true, size: 11, settings: settings),
      ...details.map((detail) => _center(detail, size: 7, settings: settings)),
      pw.SizedBox(height: 5),
    ]);
  }

  static pw.Widget _center(String text, {bool bold = false, double size = 8, ReceiptPrintSettings? settings}) {
    return pw.Text(text, textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: size * (settings?.fontScale ?? 1), fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));
  }

  static pw.Widget _line(String label, String value, {bool bold = false, ReceiptPrintSettings? settings}) {
    final weight = bold ? pw.FontWeight.bold : pw.FontWeight.normal;
    final isLongValue = value.length > 20;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 1 * (settings?.spacing ?? 1)),
      child: isLongValue
          ? pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(label, style: pw.TextStyle(fontSize: 8 * (settings?.fontScale ?? 1), fontWeight: weight)),
                pw.Text(
                  value,
                  textAlign: pw.TextAlign.left,
                  style: pw.TextStyle(fontSize: 7 * (settings?.fontScale ?? 1), fontWeight: weight),
                ),
              ],
            )
          : pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(label, style: pw.TextStyle(fontSize: 8 * (settings?.fontScale ?? 1), fontWeight: weight)),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  flex: 6,
                  child: pw.Text(
                    value,
                    textAlign: pw.TextAlign.right,
                    style: pw.TextStyle(fontSize: 8, fontWeight: weight),
                  ),
                ),
              ],
            ),
    );
  }
}
