import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../settings/data/receipt_settings_repository.dart';

class ReceiptPreviewPage extends StatefulWidget {
  const ReceiptPreviewPage({
    super.key,
    required this.pdfBytes,
    required this.fileName,
    required this.shareText,
    required this.title,
    this.receiptType,
    this.receiptPayload,
  });

  final Uint8List pdfBytes;
  final String fileName;
  final String shareText;
  final String title;
  final String? receiptType;
  final Map<String, Object?>? receiptPayload;

  @override
  State<ReceiptPreviewPage> createState() => _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends State<ReceiptPreviewPage> {
  String _format = 'foto';
  Uint8List? _imageBytes;
  bool _loadingImage = false;
  bool _sharing = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _selectFormat('foto');
    });
  }

  Future<void> _selectFormat(String format) async {
    setState(() => _format = format);
    if (format != 'foto' || _imageBytes != null || _loadingImage) return;
    setState(() => _loadingImage = true);
    try {
      // Render every PDF page so the shared photo contains the complete
      // receipt, including any pages created by long service/payment details.
      final pages = <img.Image>[];
      await for (final page in Printing.raster(widget.pdfBytes, dpi: 180)) {
        final pageBytes = await page.toPng();
        final decoded = img.decodeImage(pageBytes);
        if (decoded != null) pages.add(decoded);
      }
      if (pages.isEmpty) {
        throw StateError('Dokumen nota tidak memiliki halaman yang dapat dirender.');
      }

      final width = pages.fold<int>(
        0,
        (maximum, page) => page.width > maximum ? page.width : maximum,
      );
      final height = pages.fold<int>(
        0,
        (total, page) => total + page.height,
      );
      final combined = img.Image(width: width, height: height);
      img.fill(combined, color: img.ColorRgb8(255, 255, 255));
      var top = 0;
      for (final page in pages) {
        img.compositeImage(
          combined,
          page,
          dstX: (width - page.width) ~/ 2,
          dstY: top,
        );
        top += page.height;
      }
      final bytes = Uint8List.fromList(img.encodePng(combined));
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _loadingImage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingImage = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat foto nota: $error')),
      );
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final directory = await getTemporaryDirectory();
      final extension = _format == 'foto' ? 'png' : 'pdf';
      final baseName = widget.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final file = File('${directory.path}/$baseName.$extension');
      final bytes = _format == 'foto' ? _imageBytes : widget.pdfBytes;
      if (bytes == null) throw StateError('Pratinjau foto belum siap.');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(
        title: widget.title,
        text: widget.shareText,
        files: [XFile(file.path)],
      ));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membagikan nota: $error')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _plain(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return '-';
    return text
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '-');
  }

  int _amount(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  String _rupiah(Object? value) {
    final digits = _amount(value).toString();
    final out = StringBuffer('Rp');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
      out.write(digits[i]);
    }
    return out.toString();
  }

  String _displayInvoiceNumber(Object? value) {
    final invoice = _plain(value);
    final match = RegExp(r'^INV-(\d{4})(\d{2})(\d{2})-(\d+)$').firstMatch(invoice);
    if (match == null) return invoice;
    final year = match.group(1)!.substring(2);
    final month = match.group(2)!;
    final day = match.group(3)!;
    final serial = match.group(4)!;
    final shortSerial = serial.length > 6 ? serial.substring(serial.length - 6) : serial;
    return 'INV-$year$month$day-$shortSerial';
  }

  String _fitLine(String left, String right, int width) {
    final amount = right.length > width ? right.substring(right.length - width) : right;
    final available = width - amount.length;
    final label = left.length > available
        ? left.substring(0, available)
        : left.padRight(available);
    return '$label$amount';
  }

  Future<void> _printSaleHybrid(
    Ticket ticket,
    Map<String, Object?> payload,
    int paperWidthMm,
    ReceiptPrintSettings settings,
  ) async {
    final sale = Map<String, Object?>.from(payload['sale'] as Map);
    final profile = Map<String, String>.from(payload['profile'] as Map);
    final payments = List<Map<String, Object?>>.from(
      (payload['payments'] as List? ?? const []).map(
        (item) => Map<String, Object?>.from(item as Map),
      ),
    );
    final returns = Map<String, Object?>.from(
      payload['return_summary'] as Map? ?? const <String, Object?>{},
    );
    final width = paperWidthMm == 80 ? 48 : 32;
    // Kunci font dan code page agar printer klon ESC/POS tidak bergantung
    // pada mode font/code page bawaan yang bisa berbeda antar perangkat.
    ticket.setGlobalFont(FontType.fontA);
    ticket.setGlobalCodeTable('CP437');
    final logoPath = profile['business_logo_path']?.trim() ?? '';
    if (settings.showLogo && logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        try {
          final decoded = img.decodeImage(await logoFile.readAsBytes());
          if (decoded != null) {
            final logo = img.copyResize(
              decoded,
              width: paperWidthMm == 80 ? 300 : 220,
            );
            ticket.imageRaster(
              logo,
              align: PrintAlign.center,
              maxWidth: paperWidthMm == 80 ? 300 : 220,
            );
            ticket.emptyLines();
          }
        } catch (_) {
          // Logo rusak/tidak didukung tidak boleh menggagalkan cetak teks.
        }
      }
    }

    if (settings.showBusinessName && profile['business_name']?.trim().isNotEmpty == true) {
      // Nama usaha memakai font normal agar tidak terlalu melebar pada
      // printer 58 mm dan tidak tampak renggang/terpotong.
      ticket.text(
        _plain(profile['business_name']),
        align: PrintAlign.center,
        style: const PrintTextStyle(fontType: FontType.fontA, codeTable: 'CP437'),
        maxCharsPerLine: width,
      );
    }
    for (final key in [
      if (settings.showBusinessAddress) 'business_address',
      if (settings.showBusinessContact) 'business_phone',
      if (settings.showBusinessContact) 'business_whatsapp',
    ]) {
      final value = profile[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        ticket.text(_plain(value), align: PrintAlign.center, maxCharsPerLine: width);
      }
    }
    ticket.separator();
    ticket.text(
      'NOTA PENJUALAN',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true, height: TextSize.size1, fontType: FontType.fontA, codeTable: 'CP437'),
    );
    ticket.emptyLines();

    final date = DateTime.tryParse(_plain(sale['transaction_date']))?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final dateText = date == null
        ? _plain(sale['transaction_date'])
        : '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
    // Pisahkan label dan nomor agar nomor invoice panjang tidak menyisakan
    // satu digit sendirian di baris berikutnya.
    ticket.text('No. Nota:', maxCharsPerLine: width);
    ticket.text(_plain(sale['invoice_number']), maxCharsPerLine: width);
    ticket.text('Tanggal: $dateText', maxCharsPerLine: width);
    if (settings.showCustomerDetails && (sale['customer_name']?.toString().trim().isNotEmpty ?? false)) {
      ticket.text('Pelanggan: ${_plain(sale['customer_name'])}', maxCharsPerLine: width);
    }
    if (settings.showCustomerDetails && (sale['customer_phone']?.toString().trim().isNotEmpty ?? false)) {
      ticket.text('Telepon: ${_plain(sale['customer_phone'])}', maxCharsPerLine: width);
    }
    ticket.separator();

    final items = List<Map<String, Object?>>.from(
      (sale['items'] as List? ?? const []).map(
        (item) => Map<String, Object?>.from(item as Map),
      ),
    );
    for (final item in items) {
      ticket.text(_plain(item['product_name']), maxCharsPerLine: width);
      final qty = _amount(item['quantity']);
      final unit = _rupiah(item['unit_price']);
      final subtotal = _rupiah(item['subtotal']);
      ticket.text('  $qty x $unit', maxCharsPerLine: width);
      ticket.text(_fitLine('', subtotal, width), align: PrintAlign.right, maxCharsPerLine: width);
    }
    ticket.separator();

    final total = _amount(sale['total']);
    final paid = _amount(sale['paid']);
    final returned = _amount(returns['returned_amount']);
    final refunded = _amount(returns['refunded_amount']);
    final remaining = (total - paid - returned + refunded).clamp(0, 1 << 62).toInt();
    for (final row in [
      ['Subtotal', _rupiah(sale['subtotal'])],
      ['Diskon', _rupiah(sale['discount'])],
      ['TOTAL', _rupiah(total)],
      ['Sudah dibayar', _rupiah(paid)],
      if (returned > 0) ['Total retur', _rupiah(returned)],
      if (refunded > 0) ['Uang dikembalikan', _rupiah(refunded)],
      ['Sisa tagihan', _rupiah(remaining)],
    ]) {
      ticket.text(
        _fitLine(row[0], row[1], width),
        style: row[0] == 'TOTAL' || row[0] == 'Sisa tagihan'
            ? const PrintTextStyle(fontType: FontType.fontA, codeTable: 'CP437')
            : const PrintTextStyle(fontType: FontType.fontA, codeTable: 'CP437'),
        maxCharsPerLine: width,
      );
    }

    if (payments.isNotEmpty) {
      ticket.separator();
      ticket.text('RIWAYAT PEMBAYARAN', style: const PrintTextStyle(bold: true));
      for (final payment in payments) {
        final dateValue = DateTime.tryParse(_plain(payment['transaction_date']))?.toLocal();
        final paymentDate = dateValue == null
            ? _plain(payment['transaction_date'])
            : '${two(dateValue.day)}/${two(dateValue.month)}/${dateValue.year} ${two(dateValue.hour)}:${two(dateValue.minute)}';
        ticket.text(_fitLine(paymentDate, _rupiah(payment['amount']), width), maxCharsPerLine: width);
      }
    }
    final notes = sale['notes']?.toString().trim() ?? '';
    if (settings.showTransactionNotes && notes.isNotEmpty) {
      ticket.separator();
      ticket.text('Catatan: ${_plain(notes)}', maxCharsPerLine: width);
    }
    ticket.emptyLines();
    if (settings.showFooter) {
      final footer = settings.footerNote.trim();
      if (footer.isNotEmpty) {
        ticket.text(_plain(footer), align: PrintAlign.center, maxCharsPerLine: width);
      } else {
        ticket.text('Terima kasih atas kunjungan Anda.', align: PrintAlign.center);
      }
    }
    // Pemotongan kertas sudah dilakukan setelah semua data dikirim.
    // Hindari feed tambahan agar tidak meninggalkan titik/karakter di ujung nota.

  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    PrinterManager? manager;
    try {
      final settings = await ReceiptSettingsRepository().getReceiptSettings();
      final savedPrinter = await ReceiptSettingsRepository().getSavedPrinter();

      // Jika belum ada printer Bluetooth tersimpan, tetap sediakan layanan
      // cetak Android seperti perilaku sebelumnya.
      if (savedPrinter == null) {
        await Printing.layoutPdf(
          name: widget.fileName,
          onLayout: (_) async => widget.pdfBytes,
        );
        return;
      }

      // EPOS RPP02N dan printer SPP sekelasnya dapat kehilangan karakter
      // bila data dikirim terlalu cepat. Pecah pekerjaan menjadi potongan kecil
      // dengan jeda agar buffer serial internal printer sempat mengosongkan data.
      manager = PrinterManager(
        bluetoothConnector: BluetoothConnector(
          chunkSize: 128,
          interChunkDelay: const Duration(milliseconds: 20),
          drainBytesPerSecond: 6 * 1024,
          maxDrainWait: const Duration(seconds: 10),
        ),
      );
      await manager.connect(BluetoothPrinterDevice(
        name: savedPrinter['name']!,
        address: savedPrinter['address']!,
      ));

      final paperSize = settings.paperWidthMm == 80
          ? PaperSize.mm80
          : PaperSize.mm58;
      final ticket = await Ticket.create(paperSize);

      // Nota penjualan memakai hybrid ESC/POS: logo bitmap kecil, isi teks
      // native printer agar angka dan kolom tidak terpotong oleh raster PDF.
      if (widget.receiptType == 'sale' && widget.receiptPayload != null) {
        await _printSaleHybrid(ticket, widget.receiptPayload!, settings.paperWidthMm, settings);
        ticket.cut();
        await manager.printTicket(ticket);
        await manager.waitWriteComplete();
      } else {
        // Dokumen selain nota penjualan sementara tetap memakai jalur lama.
        final maxWidth = settings.paperWidthMm == 80 ? 470 : 320;
        var printedPages = 0;
        await for (final page in Printing.raster(widget.pdfBytes, dpi: 180)) {
        final pageBytes = await page.toPng();
        final decoded = img.decodeImage(pageBytes);
        if (decoded == null) {
          throw StateError('Halaman nota tidak dapat dikonversi menjadi gambar.');
        }
        final receiptImage = decoded.width > maxWidth
            ? img.copyResize(decoded, width: maxWidth)
            : decoded;

        final ticket = await Ticket.create(paperSize);
        ticket.imageRaster(
          receiptImage,
          align: PrintAlign.center,
          maxWidth: maxWidth,
        );
        ticket.cut();
        await manager.printTicket(ticket);
        await manager.waitWriteComplete();
          printedPages++;
        }

        if (printedPages == 0) {
          throw StateError('Dokumen nota tidak memiliki halaman untuk dicetak.');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nota berhasil dikirim ke printer ${savedPrinter['name']}.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak nota: $error')),
      );
    } finally {
      if (manager != null) {
        try {
          // dispose menutup koneksi dan menunggu buffer cetak dikirim.
          await manager.dispose();
        } catch (_) {
          // Jangan menutupi hasil utama jika pelepasan koneksi gagal.
        }
      }
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'foto', label: Text('Foto')),
                ButtonSegment(value: 'pdf', label: Text('PDF')),
              ],
              selected: {_format},
              onSelectionChanged: (value) => _selectFormat(value.first),
            ),
          ),
          Expanded(
            child: _format == 'pdf'
                ? PdfPreview(
                    build: (_) async => widget.pdfBytes,
                    initialPageFormat: const PdfPageFormat(164.4, 900, marginAll: 8),
                    allowPrinting: false,
                    allowSharing: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    useActions: false,
                    padding: const EdgeInsets.all(8),
                  )
                : Center(
                    child: _loadingImage
                        ? const CircularProgressIndicator()
                        : _imageBytes == null
                            ? const Text('Pratinjau foto belum tersedia.')
                            : InteractiveViewer(
                                child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                              ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _printing ? null : _print,
                      icon: _printing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined),
                      label: Text(_printing ? 'Mengirim...' : 'Cetak'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharing || (_format == 'foto' && (_loadingImage || _imageBytes == null)) ? null : _share,
                      icon: _sharing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.share_outlined),
                      label: const Text('Bagikan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
).firstMatch(invoice);
    if (match == null) return invoice;
    final year = match.group(1)!.substring(2);
    final month = match.group(2)!;
    final day = match.group(3)!;
    final serial = match.group(4)!;
    final shortSerial = serial.length > 6 ? serial.substring(serial.length - 6) : serial;
    return 'INV-$year$month$day-$shortSerial';
  }

  String _fitLine(String left, String right, int width) {
    final amount = right.length > width ? right.substring(right.length - width) : right;
    final available = width - amount.length;
    final label = left.length > available
        ? left.substring(0, available)
        : left.padRight(available);
    return '$label$amount';
  }

  Future<void> _printSaleHybrid(
    Ticket ticket,
    Map<String, Object?> payload,
    int paperWidthMm,
    ReceiptPrintSettings settings,
  ) async {
    final sale = Map<String, Object?>.from(payload['sale'] as Map);
    final profile = Map<String, String>.from(payload['profile'] as Map);
    final payments = List<Map<String, Object?>>.from(
      (payload['payments'] as List? ?? const []).map(
        (item) => Map<String, Object?>.from(item as Map),
      ),
    );
    final returns = Map<String, Object?>.from(
      payload['return_summary'] as Map? ?? const <String, Object?>{},
    );
    final width = paperWidthMm == 80 ? 48 : 32;
    // Kunci font dan code page agar printer klon ESC/POS tidak bergantung
    // pada mode font/code page bawaan yang bisa berbeda antar perangkat.
    ticket.setGlobalFont(FontType.fontA);
    ticket.setGlobalCodeTable('CP437');
    final logoPath = profile['business_logo_path']?.trim() ?? '';
    if (logoPath.isNotEmpty) {
      final logoFile = File(logoPath);
      if (await logoFile.exists()) {
        try {
          final decoded = img.decodeImage(await logoFile.readAsBytes());
          if (decoded != null) {
            final logo = img.copyResize(
              decoded,
              width: paperWidthMm == 80 ? 300 : 220,
            );
            ticket.imageRaster(
              logo,
              align: PrintAlign.center,
              maxWidth: paperWidthMm == 80 ? 300 : 220,
            );
            ticket.emptyLines();
          }
        } catch (_) {
          // Logo rusak/tidak didukung tidak boleh menggagalkan cetak teks.
        }
      }
    }

    if (settings.showBusinessName && profile['business_name']?.trim().isNotEmpty == true) {
      // Nama usaha memakai font normal agar tidak terlalu melebar pada
      // printer 58 mm dan tidak tampak renggang/terpotong.
      ticket.text(
        _plain(profile['business_name']),
        align: PrintAlign.center,
        style: const PrintTextStyle(fontType: FontType.fontA, codeTable: 'CP437'),
        maxCharsPerLine: width,
      );
    }
    for (final key in [
      if (settings.showBusinessAddress) 'business_address',
      if (settings.showBusinessContact) 'business_phone',
      if (settings.showBusinessContact) 'business_whatsapp',
    ]) {
      final value = profile[key]?.trim() ?? '';
      if (value.isNotEmpty) {
        ticket.text(_plain(value), align: PrintAlign.center, maxCharsPerLine: width);
      }
    }
    ticket.separator();
    ticket.text(
      'NOTA PENJUALAN',
      align: PrintAlign.center,
      style: const PrintTextStyle(bold: true, height: TextSize.size1, fontType: FontType.fontA, codeTable: 'CP437'),
    );
    ticket.emptyLines();

    final date = DateTime.tryParse(_plain(sale['transaction_date']))?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final dateText = date == null
        ? _plain(sale['transaction_date'])
        : '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
    // Pisahkan label dan nomor agar nomor invoice panjang tidak menyisakan
    // satu digit sendirian di baris berikutnya.
    ticket.text('No. Nota:', maxCharsPerLine: width);
    ticket.text(_plain(sale['invoice_number']), maxCharsPerLine: width);
    ticket.text('Tanggal: $dateText', maxCharsPerLine: width);
    if (settings.showCustomerDetails && (sale['customer_name']?.toString().trim().isNotEmpty ?? false)) {
      ticket.text('Pelanggan: ${_plain(sale['customer_name'])}', maxCharsPerLine: width);
    }
    if (settings.showCustomerDetails && (sale['customer_phone']?.toString().trim().isNotEmpty ?? false)) {
      ticket.text('Telepon: ${_plain(sale['customer_phone'])}', maxCharsPerLine: width);
    }
    ticket.separator();

    final items = List<Map<String, Object?>>.from(
      (sale['items'] as List? ?? const []).map(
        (item) => Map<String, Object?>.from(item as Map),
      ),
    );
    for (final item in items) {
      ticket.text(_plain(item['product_name']), maxCharsPerLine: width);
      final qty = _amount(item['quantity']);
      final unit = _rupiah(item['unit_price']);
      final subtotal = _rupiah(item['subtotal']);
      ticket.text('  $qty x $unit', maxCharsPerLine: width);
      ticket.text(_fitLine('', subtotal, width), align: PrintAlign.right, maxCharsPerLine: width);
    }
    ticket.separator();

    final total = _amount(sale['total']);
    final paid = _amount(sale['paid']);
    final returned = _amount(returns['returned_amount']);
    final refunded = _amount(returns['refunded_amount']);
    final remaining = (total - paid - returned + refunded).clamp(0, 1 << 62).toInt();
    for (final row in [
      ['Subtotal', _rupiah(sale['subtotal'])],
      ['Diskon', _rupiah(sale['discount'])],
      ['TOTAL', _rupiah(total)],
      ['Sudah dibayar', _rupiah(paid)],
      if (returned > 0) ['Total retur', _rupiah(returned)],
      if (refunded > 0) ['Uang dikembalikan', _rupiah(refunded)],
      ['Sisa tagihan', _rupiah(remaining)],
    ]) {
      ticket.text(
        _fitLine(row[0], row[1], width),
        style: row[0] == 'TOTAL' || row[0] == 'Sisa tagihan'
            ? const PrintTextStyle(fontType: FontType.fontA, codeTable: 'CP437')
            : const PrintTextStyle(fontType: FontType.fontA, codeTable: 'CP437'),
        maxCharsPerLine: width,
      );
    }

    if (payments.isNotEmpty) {
      ticket.separator();
      ticket.text('RIWAYAT PEMBAYARAN', style: const PrintTextStyle(bold: true));
      for (final payment in payments) {
        final dateValue = DateTime.tryParse(_plain(payment['transaction_date']))?.toLocal();
        final paymentDate = dateValue == null
            ? _plain(payment['transaction_date'])
            : '${two(dateValue.day)}/${two(dateValue.month)}/${dateValue.year} ${two(dateValue.hour)}:${two(dateValue.minute)}';
        ticket.text(_fitLine(paymentDate, _rupiah(payment['amount']), width), maxCharsPerLine: width);
      }
    }
    final notes = sale['notes']?.toString().trim() ?? '';
    if (settings.showTransactionNotes && notes.isNotEmpty) {
      ticket.separator();
      ticket.text('Catatan: ${_plain(notes)}', maxCharsPerLine: width);
    }
    final footer = settings.footerNote.trim();
    ticket.emptyLines();
    if (footer.isNotEmpty) {
      ticket.text(_plain(footer), align: PrintAlign.center, maxCharsPerLine: width);
    } else {
      ticket.text('Terima kasih atas kunjungan Anda.', align: PrintAlign.center);
    }
    // Pemotongan kertas sudah dilakukan setelah semua data dikirim.
    // Hindari feed tambahan agar tidak meninggalkan titik/karakter di ujung nota.

  }

  Future<void> _print() async {
    if (_printing) return;
    setState(() => _printing = true);
    PrinterManager? manager;
    try {
      final settings = await ReceiptSettingsRepository().getReceiptSettings();
      final savedPrinter = await ReceiptSettingsRepository().getSavedPrinter();

      // Jika belum ada printer Bluetooth tersimpan, tetap sediakan layanan
      // cetak Android seperti perilaku sebelumnya.
      if (savedPrinter == null) {
        await Printing.layoutPdf(
          name: widget.fileName,
          onLayout: (_) async => widget.pdfBytes,
        );
        return;
      }

      // EPOS RPP02N dan printer SPP sekelasnya dapat kehilangan karakter
      // bila data dikirim terlalu cepat. Pecah pekerjaan menjadi potongan kecil
      // dengan jeda agar buffer serial internal printer sempat mengosongkan data.
      manager = PrinterManager(
        bluetoothConnector: BluetoothConnector(
          chunkSize: 128,
          interChunkDelay: const Duration(milliseconds: 20),
          drainBytesPerSecond: 6 * 1024,
          maxDrainWait: const Duration(seconds: 10),
        ),
      );
      await manager.connect(BluetoothPrinterDevice(
        name: savedPrinter['name']!,
        address: savedPrinter['address']!,
      ));

      final paperSize = settings.paperWidthMm == 80
          ? PaperSize.mm80
          : PaperSize.mm58;
      final ticket = await Ticket.create(paperSize);

      // Nota penjualan memakai hybrid ESC/POS: logo bitmap kecil, isi teks
      // native printer agar angka dan kolom tidak terpotong oleh raster PDF.
      if (widget.receiptType == 'sale' && widget.receiptPayload != null) {
        await _printSaleHybrid(ticket, widget.receiptPayload!, settings.paperWidthMm, settings);
        ticket.cut();
        await manager.printTicket(ticket);
        await manager.waitWriteComplete();
      } else {
        // Dokumen selain nota penjualan sementara tetap memakai jalur lama.
        final maxWidth = settings.paperWidthMm == 80 ? 470 : 320;
        var printedPages = 0;
        await for (final page in Printing.raster(widget.pdfBytes, dpi: 180)) {
        final pageBytes = await page.toPng();
        final decoded = img.decodeImage(pageBytes);
        if (decoded == null) {
          throw StateError('Halaman nota tidak dapat dikonversi menjadi gambar.');
        }
        final receiptImage = decoded.width > maxWidth
            ? img.copyResize(decoded, width: maxWidth)
            : decoded;

        final ticket = await Ticket.create(paperSize);
        ticket.imageRaster(
          receiptImage,
          align: PrintAlign.center,
          maxWidth: maxWidth,
        );
        ticket.cut();
        await manager.printTicket(ticket);
        await manager.waitWriteComplete();
          printedPages++;
        }

        if (printedPages == 0) {
          throw StateError('Dokumen nota tidak memiliki halaman untuk dicetak.');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nota berhasil dikirim ke printer ${savedPrinter['name']}.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak nota: $error')),
      );
    } finally {
      if (manager != null) {
        try {
          // dispose menutup koneksi dan menunggu buffer cetak dikirim.
          await manager.dispose();
        } catch (_) {
          // Jangan menutupi hasil utama jika pelepasan koneksi gagal.
        }
      }
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'foto', label: Text('Foto')),
                ButtonSegment(value: 'pdf', label: Text('PDF')),
              ],
              selected: {_format},
              onSelectionChanged: (value) => _selectFormat(value.first),
            ),
          ),
          Expanded(
            child: _format == 'pdf'
                ? PdfPreview(
                    build: (_) async => widget.pdfBytes,
                    initialPageFormat: const PdfPageFormat(164.4, 900, marginAll: 8),
                    allowPrinting: false,
                    allowSharing: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    useActions: false,
                    padding: const EdgeInsets.all(8),
                  )
                : Center(
                    child: _loadingImage
                        ? const CircularProgressIndicator()
                        : _imageBytes == null
                            ? const Text('Pratinjau foto belum tersedia.')
                            : InteractiveViewer(
                                child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                              ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _printing ? null : _print,
                      icon: _printing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.print_outlined),
                      label: Text(_printing ? 'Mengirim...' : 'Cetak'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _sharing || (_format == 'foto' && (_loadingImage || _imageBytes == null)) ? null : _share,
                      icon: _sharing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.share_outlined),
                      label: const Text('Bagikan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
