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
  });

  final Uint8List pdfBytes;
  final String fileName;
  final String shareText;
  final String title;

  @override
  State<ReceiptPreviewPage> createState() => _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends State<ReceiptPreviewPage> {
  String _format = 'pdf';
  Uint8List? _imageBytes;
  bool _loadingImage = false;
  bool _sharing = false;
  bool _printing = false;

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

      manager = PrinterManager();
      await manager.connect(BluetoothPrinterDevice(
        name: savedPrinter['name']!,
        address: savedPrinter['address']!,
      ));

      final paperSize = settings.paperWidthMm == 80
          ? PaperSize.mm80
          : PaperSize.mm58;
      final maxWidth = settings.paperWidthMm == 80 ? 576 : 384;
      var printedPages = 0;

      // Render per halaman agar nota panjang tidak perlu digabung menjadi
      // satu bitmap besar di memori.
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
          await manager.disconnect();
        } catch (_) {
          // Abaikan kegagalan pemutusan setelah pekerjaan cetak selesai/gagal.
        }
        await manager.dispose();
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
