import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../settings/data/receipt_settings_repository.dart';
import 'receipt_layout.dart';

class ReceiptPreviewPage extends StatefulWidget {
  const ReceiptPreviewPage({
    super.key,
    this.pdfBytes,
    required this.fileName,
    required this.shareText,
    required this.title,
    this.receiptType,
    this.receiptPayload,
  });

  final Uint8List? pdfBytes;
  final String fileName;
  final String shareText;
  final String title;
  final String? receiptType;
  final Map<String, Object?>? receiptPayload;

  @override
  State<ReceiptPreviewPage> createState() => _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends State<ReceiptPreviewPage> {
  final GlobalKey _receiptKey = GlobalKey();
  Uint8List? _imageBytes;
  ReceiptPrintSettings _settings = const ReceiptPrintSettings();
  bool _loading = true;
  bool _sharing = false;
  bool _printing = false;

  bool get _nativeReceipt => const {'sale', 'service', 'service_final_payment', 'service_intake'}.contains(widget.receiptType);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareOutput());
  }

  Future<void> _prepareOutput() async {
    try {
      _settings = await ReceiptSettingsRepository().getReceiptSettings();
      if (_nativeReceipt) {
        if (mounted) setState(() {});
        await WidgetsBinding.instance.endOfFrame;
        final object = _receiptKey.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          throw StateError('Layout nota belum siap.');
        }
        final image = await object.toImage(pixelRatio: 1.2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) throw StateError('Gagal mengambil gambar nota.');
        _imageBytes = data.buffer.asUint8List();
      } else {
        final pdf = widget.pdfBytes;
        if (pdf == null) throw StateError('Dokumen PDF tidak tersedia.');
        final pages = <img.Image>[];
        await for (final page in Printing.raster(pdf, dpi: 180)) {
          final decoded = img.decodeImage(await page.toPng());
          if (decoded != null) pages.add(decoded);
        }
        if (pages.isEmpty) throw StateError('Dokumen PDF tidak memiliki halaman.');
        final width = pages.fold<int>(0, (v, p) => p.width > v ? p.width : v);
        final height = pages.fold<int>(0, (v, p) => v + p.height);
        final combined = img.Image(width: width, height: height);
        img.fill(combined, color: img.ColorRgb8(255, 255, 255));
        var top = 0;
        for (final page in pages) {
          img.compositeImage(combined, page, dstX: (width - page.width) ~/ 2, dstY: top);
          top += page.height;
        }
        _imageBytes = Uint8List.fromList(img.encodePng(combined));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyiapkan dokumen: $error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final isPdf = !_nativeReceipt;
      final bytes = isPdf ? widget.pdfBytes : _imageBytes;
      if (bytes == null) throw StateError('Berkas belum siap.');
      final directory = await getTemporaryDirectory();
      final base = widget.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final file = File(directory.path + '/' + base + (isPdf ? '.pdf' : '.png'));
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(title: widget.title, text: widget.shareText, files: [XFile(file.path)]));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membagikan dokumen: $error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _receiptText(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text == 'null' ? '' : text;
  }

  int _receiptInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  String _receiptMoney(Object? value) {
    final digits = _receiptInt(value).toString();
    final out = StringBuffer('Rp.');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return out.toString();
  }

  String _receiptDate(Object? value) {
    final parsed = DateTime.tryParse(_receiptText(value))?.toLocal();
    if (parsed == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  void _ticketText(Ticket ticket, String value, {bool bold = false, PrintAlign align = PrintAlign.left, int linesAfter = 0}) {
    if (value.trim().isEmpty) return;
    ticket.text(value, align: align,
      style: PrintTextStyle(bold: bold, fontType: FontType.fontA),
      maxCharsPerLine: 32, linesAfter: linesAfter);
  }

  String _fitReceiptLine(String left, String right, {int width = 32}) {
    final safeLeft = left.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ').trim();
    final safeRight = right.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ').trim();
    if (safeLeft.isEmpty) return safeRight.length > width ? safeRight.substring(0, width) : safeRight;
    if (safeRight.isEmpty) return safeLeft.length > width ? safeLeft.substring(0, width) : safeLeft;
    final available = width - safeLeft.length - safeRight.length;
    if (available >= 1) return '$safeLeft${' ' * available}$safeRight';
    final labelWidth = (width - safeRight.length - 1).clamp(1, width);
    return '${safeLeft.substring(0, safeLeft.length.clamp(0, labelWidth))} $safeRight';
  }

  void _ticketLabel(Ticket ticket, String label, String value, {bool bold = false}) {
    if (value.trim().isEmpty) return;
    // Use one complete ASCII line. PrintColumn uses positioned mid-line
    // writes which can be duplicated/wrapped by some 58 mm ESC/POS clones.
    _ticketText(ticket, _fitReceiptLine(label, value), bold: bold);
  }

  void _ticketItemAmount(Ticket ticket, int quantity, Object? unitPrice, Object? subtotal) {
    final left = '$quantity x ${_receiptMoney(unitPrice)}';
    final right = _receiptMoney(subtotal);
    _ticketText(ticket, _fitReceiptLine(left, right));
  }

  String _paymentMethod(Map<String, Object?> payment) {
    final raw = _receiptText(payment['payment_method'] ?? payment['method'] ?? payment['payment_method_name']);
    final key = raw.toLowerCase().replaceAll('-', '_');
    const labels = {'cash':'TUNAI','tunai':'TUNAI','bank_transfer':'TRANSFER','transfer':'TRANSFER','transfer bank':'TRANSFER','qris':'QRIS','debit_card':'KARTU DEBIT','credit_card':'KARTU KREDIT','e_wallet':'E-WALLET','customer_wallet':'SALDO PELANGGAN'};
    return labels[key] ?? raw.toUpperCase();
  }

  Future<Ticket> _buildRawReceiptTicket(ReceiptPrintSettings settings) async {
    final type = widget.receiptType!;
    final isSale = type == 'sale';
    final isFinalPayment = type == 'service_final_payment';
    final isIntake = type == 'service_intake';
    final source = Map<String, Object?>.from(widget.receiptPayload![isSale ? 'sale' : 'service'] as Map);
    final profile = Map<String, String>.from(widget.receiptPayload!['profile'] as Map);
    final payments = List<Map<String, Object?>>.from((widget.receiptPayload!['payments'] as List? ?? const []).map((item) => Map<String, Object?>.from(item as Map)));
    final items = List<Map<String, Object?>>.from((source['items'] as List? ?? const []).map((item) => Map<String, Object?>.from(item as Map)));
    final total = _receiptInt(isSale ? source['total'] : source['total_cost']);
    final paid = isFinalPayment ? (total - _receiptInt(source['remaining_payment'])).clamp(0, 1 << 62).toInt() : _receiptInt(isSale ? source['paid'] : source['down_payment']);
    final returns = Map<String, Object?>.from(widget.receiptPayload!['return_summary'] as Map? ?? const {});
    final remaining = isSale ? (total - paid - _receiptInt(returns['returned_amount']) + _receiptInt(returns['refunded_amount'])).clamp(0, 1 << 62).toInt() : _receiptInt(source['remaining_payment']);

    final ticket = await Ticket.create(settings.paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58);
    final logoPath = _receiptText(profile['business_logo_path']);
    if (settings.showLogo && logoPath.isNotEmpty) {
      final file = File(logoPath);
      if (await file.exists()) {
        try {
          final decoded = img.decodeImage(await file.readAsBytes());
          if (decoded != null) {
            final maxWidth = settings.paperWidthMm == 80 ? 320 : 240;
            final logo = decoded.width > maxWidth ? img.copyResize(decoded, width: maxWidth) : decoded;
            ticket.imageRaster(logo, align: PrintAlign.center, maxWidth: maxWidth);
          }
        } catch (_) {}
      }
    }
    if (settings.showBusinessName) {
      final name = _receiptText(profile['business_name']);
      if (name.isNotEmpty) _ticketText(ticket, name.toUpperCase(), bold: true, align: PrintAlign.center);
    }
    if (settings.showBusinessAddress) _ticketText(ticket, _receiptText(profile['business_address']), align: PrintAlign.center);
    if (settings.showBusinessContact) {
      final phone = _receiptText(profile['business_phone']);
      final wa = _receiptText(profile['business_whatsapp']);
      if (phone.isNotEmpty) _ticketText(ticket, 'Telp. $phone', align: PrintAlign.center);
      if (wa.isNotEmpty && wa != phone) _ticketText(ticket, 'WA. $wa', align: PrintAlign.center);
    }

    ticket.separator();
    _ticketText(ticket, isSale ? 'NOTA PENJUALAN' : isFinalPayment ? 'BUKTI PELUNASAN SERVIS' : isIntake ? 'BUKTI PENERIMAAN SEPEDA' : 'NOTA SERVIS', bold: true, align: PrintAlign.center);
    ticket.separator();
    _ticketLabel(ticket, 'No. Nota', _receiptText(isSale ? source['invoice_number'] : source['order_number']));
    _ticketLabel(ticket, 'Tanggal', _receiptDate(isSale ? source['transaction_date'] : source['received_at']));
    if (settings.showCustomerDetails) {
      final customer = _receiptText(source['customer_name']);
      _ticketLabel(ticket, 'Pelanggan', customer.isEmpty ? 'Pembeli Umum' : customer);
      final phone = _receiptText(source['customer_phone']);
      if (phone.isNotEmpty) _ticketLabel(ticket, 'No. Telp', phone);
    }

    if (isSale) {
      ticket.separator();
      _ticketText(ticket, 'BARANG', bold: true);
      for (final item in items) {
        final name = _receiptText(item['product_name']);
        if (name.isNotEmpty) _ticketText(ticket, name);
        _ticketItemAmount(ticket, _receiptInt(item['quantity']), item['unit_price'], item['subtotal']);
      }
      ticket.separator();
      _ticketLabel(ticket, 'Subtotal', _receiptMoney(source['subtotal']));
      _ticketLabel(ticket, 'Diskon', _receiptMoney(source['discount']));
      _ticketLabel(ticket, 'TOTAL', _receiptMoney(total), bold: true);
      _ticketLabel(ticket, 'Sudah dibayar', _receiptMoney(paid));
      _ticketLabel(ticket, 'Sisa tagihan', _receiptMoney(remaining), bold: true);
    } else if (isIntake) {
      final bicycle = [
        _receiptText(source['bicycle_brand']),
        _receiptText(source['bicycle_model']),
        _receiptText(source['bicycle_type']),
      ].where((part) => part.isNotEmpty).join(' ');
      if (bicycle.isNotEmpty) _ticketLabel(ticket, 'Sepeda', bicycle);
      _ticketLabel(ticket, 'Warna', _receiptText(source['bicycle_color']));
      _ticketLabel(ticket, 'Ukuran frame', _receiptText(source['bicycle_frame_size']));
      _ticketLabel(ticket, 'No. rangka', _receiptText(source['bicycle_serial_number']));
      final complaint = _receiptText(source['complaint']);
      if (complaint.isNotEmpty) {
        _ticketText(ticket, 'Keluhan:', bold: true);
        _ticketText(ticket, complaint);
      }
      final diagnosis = _receiptText(source['diagnosis']);
      if (diagnosis.isNotEmpty) {
        _ticketText(ticket, 'Pemeriksaan awal:', bold: true);
        _ticketText(ticket, diagnosis);
      }
      _ticketLabel(ticket, 'Estimasi biaya', _receiptMoney(source['estimated_cost']), bold: true);
      _ticketLabel(ticket, 'Status servis', _receiptText(source['service_status']));
    } else {
      final bicycle = [_receiptText(source['bicycle_brand']), _receiptText(source['bicycle_model'])].where((part) => part.isNotEmpty).join(' ');
      if (bicycle.isNotEmpty) _ticketLabel(ticket, 'Sepeda', bicycle);
      final complaint = _receiptText(source['complaint']);
      if (complaint.isNotEmpty) { _ticketText(ticket, 'Keluhan:', bold: true); _ticketText(ticket, complaint); }
      if (!isFinalPayment) {
        final diagnosis = _receiptText(source['diagnosis']);
        if (diagnosis.isNotEmpty) { _ticketText(ticket, 'Diagnosis:', bold: true); _ticketText(ticket, diagnosis); }
        final mechanic = _receiptText(source['mechanic_name']);
        if (mechanic.isNotEmpty) _ticketLabel(ticket, 'Mekanik', mechanic);
        ticket.separator();
        _ticketLabel(ticket, 'Jasa servis', _receiptMoney(source['labor_cost']));
        for (final item in items) {
          final name = _receiptText(item['item_name']);
          if (name.isNotEmpty) _ticketText(ticket, name);
          _ticketItemAmount(ticket, _receiptInt(item['quantity']), item['unit_price'], item['subtotal']);
        }
        ticket.separator();
        _ticketLabel(ticket, 'Total sparepart', _receiptMoney(source['parts_cost']));
        _ticketLabel(ticket, 'Diskon', _receiptMoney(source['discount']));
        _ticketLabel(ticket, 'TOTAL BIAYA', _receiptMoney(total), bold: true);
        _ticketLabel(ticket, 'Sudah dibayar', _receiptMoney(paid));
        _ticketLabel(ticket, 'Sisa tagihan', _receiptMoney(remaining), bold: true);
        final status = _receiptText(source['service_status']);
        if (status.isNotEmpty) _ticketLabel(ticket, 'Status', status);
      } else {
        ticket.separator();
        _ticketLabel(ticket, 'Total biaya servis', _receiptMoney(total));
        _ticketLabel(ticket, 'Total pembayaran', _receiptMoney(paid), bold: true);
        _ticketLabel(ticket, 'Sisa tagihan', _receiptMoney(remaining), bold: true);
        _ticketText(ticket, 'LUNAS - TIDAK ADA SISA TAGIHAN', bold: true, align: PrintAlign.center);
      }
    }

    if (payments.isNotEmpty) {
      ticket.separator();
      _ticketText(ticket, 'RIWAYAT PEMBAYARAN', bold: true, align: PrintAlign.center);
      for (final payment in payments) {
        final parsed = DateTime.tryParse(_receiptText(payment['transaction_date']))?.toLocal();
        String two(int n) => n.toString().padLeft(2, '0');
        final dateText = parsed == null ? '-' : '${two(parsed.day)}/${two(parsed.month)} ${two(parsed.hour)}:${two(parsed.minute)}';
        final method = _paymentMethod(payment);
        _ticketText(ticket, '$dateText ${method.isEmpty ? '' : '- $method'}');
        _ticketText(ticket, _receiptMoney(payment['amount']), bold: true, align: PrintAlign.right);
      }
    }
    if (settings.showTransactionNotes && _receiptText(source['notes']).isNotEmpty) {
      ticket.separator();
      _ticketText(ticket, 'Catatan:', bold: true);
      _ticketText(ticket, _receiptText(source['notes']));
    }
    ticket.separator();
    if (settings.showFooter) {
      final footer = settings.footerNote.trim().isEmpty ? 'Terima kasih atas kunjungan Anda.' : settings.footerNote.trim();
      _ticketText(ticket, footer, align: PrintAlign.center, linesAfter: 2);
    } else {
      ticket.emptyLines(2);
    }
    ticket.cut();
    return ticket;
  }

  Future<void> _print() async {
    if (!_nativeReceipt || _printing) return;
    setState(() => _printing = true);
    PrinterManager? manager;
    try {
      final settings = await ReceiptSettingsRepository().getReceiptSettings();
      final saved = await ReceiptSettingsRepository().getSavedPrinter();
      if (saved == null) throw StateError('Printer thermal belum diatur. Hubungkan printer melalui Pengaturan Printer.');
      final imageBytes = _imageBytes;
      if (imageBytes == null) {
        throw StateError('Gambar nota belum siap. Silakan tunggu pratinjau selesai dimuat.');
      }
      final receiptImage = img.decodeImage(imageBytes);
      if (receiptImage == null) {
        throw StateError('Gambar nota tidak dapat dibaca untuk dicetak.');
      }

      // Cetak raster dari sumber gambar yang sama dengan file PNG WhatsApp.
      // Dengan begitu susunan, garis, logo, dan ukuran teks pada keduanya identik.
      final ticket = await Ticket.create(
        settings.paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58,
      );
      final maxWidth = settings.paperWidthMm == 80 ? 576 : 384;
      ticket.imageRaster(receiptImage, align: PrintAlign.center, maxWidth: maxWidth);
      ticket.emptyLines(2);
      ticket.cut();

      manager = PrinterManager(bluetoothConnector: BluetoothConnector(
        chunkSize: 128,
        interChunkDelay: const Duration(milliseconds: 20),
        drainBytesPerSecond: 6 * 1024,
        maxDrainWait: const Duration(seconds: 10),
      ));
      await manager.connect(BluetoothPrinterDevice(name: saved['name']!, address: saved['address']!));
      await manager.printTicket(ticket);
      await manager.waitWriteComplete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nota ESC/POS dikirim ke printer ${saved['name']!}.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mencetak nota: $error')));
    } finally {
      if (manager != null) { try { await manager.dispose(); } catch (_) {} }
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('Nota dibagikan sebagai foto dan dicetak menggunakan printer thermal.')),
        ),
        Expanded(child: Center(
          child: _nativeReceipt
              ? SingleChildScrollView(child: InteractiveViewer(
                  child: RepaintBoundary(key: _receiptKey, child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(1.0),
                    ),
                    child: ReceiptLayout(
                      receiptType: widget.receiptType!,
                      payload: widget.receiptPayload!,
                      settings: _settings,
                    ),
                  )),
                ))
              : _loading
                  ? const CircularProgressIndicator()
                  : _imageBytes == null
                      ? const Text('Pratinjau dokumen tidak tersedia.')
                      : InteractiveViewer(child: Image.memory(_imageBytes!, fit: BoxFit.contain)),
        )),
        SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            if (_nativeReceipt) Expanded(child: OutlinedButton.icon(
              onPressed: _loading || _printing ? null : _print,
              icon: _printing ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.print_outlined),
              label: Text(_printing ? 'Mengirim...' : 'Cetak'),
            )),
            if (_nativeReceipt) const SizedBox(width: 8),
            Expanded(child: FilledButton.icon(
              onPressed: _loading || _sharing ? null : _share,
              icon: _sharing ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.share_outlined),
              label: const Text('Bagikan'),
            )),
          ]),
        )),
      ]),
    );
  }
}
