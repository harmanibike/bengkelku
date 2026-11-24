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

  bool get _nativeReceipt => const {'sale', 'service', 'service_final_payment'}.contains(widget.receiptType);

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

  Future<void> _print() async {
    if (!_nativeReceipt || _printing) return;
    setState(() => _printing = true);
    PrinterManager? manager;
    try {
      final settings = await ReceiptSettingsRepository().getReceiptSettings();
      final saved = await ReceiptSettingsRepository().getSavedPrinter();
      if (saved == null) throw StateError('Printer thermal belum diatur. Hubungkan printer melalui Pengaturan Printer.');
      final bytes = _imageBytes;
      if (bytes == null) throw StateError('Gambar nota belum siap.');
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw StateError('Gambar nota tidak dapat dibaca.');
      final width = settings.thermalDots;
      final resized = decoded.width == width
          ? decoded
          : img.copyResize(decoded, width: width, interpolation: img.Interpolation.nearest);
      final receipt = img.grayscale(resized);
      for (final pixel in receipt) {
        final value = pixel.luminance < 180 ? 0 : 255;
        pixel..r = value..g = value..b = value;
      }
      manager = PrinterManager(bluetoothConnector: BluetoothConnector(
        chunkSize: 128,
        interChunkDelay: const Duration(milliseconds: 20),
        drainBytesPerSecond: 6 * 1024,
        maxDrainWait: const Duration(seconds: 10),
      ));
      await manager.connect(BluetoothPrinterDevice(name: saved['name']!, address: saved['address']!));
      final ticket = await Ticket.create(settings.paperWidthMm == 80 ? PaperSize.mm80 : PaperSize.mm58);
      ticket.imageRaster(receipt, align: PrintAlign.center, maxWidth: width);
      ticket.cut();
      await manager.printTicket(ticket);
      await manager.waitWriteComplete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nota dikirim ke printer ' + saved['name']! + '.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal mencetak nota: $error')));
    } finally {
      if (manager != null) {
        try { await manager.dispose(); } catch (_) {}
      }
      if (mounted) setState(() {
        _printing = false;
      });
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
