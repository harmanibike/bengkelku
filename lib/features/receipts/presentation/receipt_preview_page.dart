import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart';
import 'package:cross_file/cross_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

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

  Future<void> _selectFormat(String format) async {
    setState(() => _format = format);
    if (format != 'foto' || _imageBytes != null || _loadingImage) return;
    setState(() => _loadingImage = true);
    try {
      final raster = await Printing.raster(widget.pdfBytes, pages: const [0], dpi: 180).first;
      final bytes = await raster.toPng();
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
    try {
      await Printing.layoutPdf(
        name: widget.fileName,
        onLayout: (_) async => widget.pdfBytes,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka layanan cetak: $error')),
      );
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
                      onPressed: _print,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Cetak'),
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
