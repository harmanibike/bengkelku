import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:material_ui/material_ui.dart';
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
  Uint8List? _imageBytes;
  bool _loadingImage = false;
  bool _sharing = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _preparePhoto();
    });
  }

  Future<void> _preparePhoto() async {
    if (_imageBytes != null || _loadingImage) return;
    setState(() => _loadingImage = true);
    try {
      // Render the complete receipt as one image for WhatsApp sharing.
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
      const extension = 'png';
      final baseName = widget.fileName.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
      final file = File('${directory.path}/$baseName.$extension');
      final bytes = _imageBytes;
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

      // Nota hanya dicetak melalui printer thermal yang sudah dikonfigurasi.
      // Jangan membuka dialog cetak PDF sebagai jalur pengganti.
      if (savedPrinter == null) {
        throw StateError('Printer thermal belum diatur. Hubungkan printer melalui Pengaturan Printer.');
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

      // Semua jenis nota dicetak dari dokumen PDF yang sama dengan
      // pratinjau dan file WhatsApp. Dengan demikian logo, ukuran huruf,
      // jarak, garis, dan tata letak konsisten untuk seluruh dokumen.
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

        final pageTicket = await Ticket.create(paperSize);
        pageTicket.imageRaster(
          receiptImage,
          align: PrintAlign.center,
          maxWidth: maxWidth,
        );
        pageTicket.cut();
        await manager.printTicket(pageTicket);
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
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Nota dibagikan sebagai foto dan dicetak menggunakan printer thermal.'),
            ),
          ),
          Expanded(
            child: Center(
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
                      onPressed: _sharing || _loadingImage || _imageBytes == null ? null : _share,
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
