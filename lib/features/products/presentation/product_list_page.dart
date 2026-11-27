import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';

import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:unified_esc_pos_printer/unified_esc_pos_printer.dart';

import '../../../core/formatters/currency_input_formatter.dart';
import '../../../core/widgets/app_photo_preview.dart';
import '../data/product_repository.dart';
import '../data/product_import_service.dart';
import '../../purchases/presentation/purchase_cost_settings_page.dart';
import 'product_category_page.dart';
import '../../sales/presentation/barcode_scanner_page.dart';
import 'stock_movement_page.dart';
import 'stock_opname_page.dart';

class ProductListPage extends StatefulWidget {
  const ProductListPage({super.key});

  @override
  State<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends State<ProductListPage> {
  final ProductRepository _repository = ProductRepository();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<Map<String, Object?>>> _productsFuture;
  bool _showInactive = false;
  static const int _pageSize = 50;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadProducts() {
    _productsFuture = _repository.getProducts(
      keyword: _searchController.text,
      includeInactive: _showInactive,
      limit: _pageSize,
      offset: _page * _pageSize,
    );
  }

  void _refresh() => setState(() { _page = 0; _loadProducts(); });


  Future<void> _importProducts() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty || !mounted) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw StateError('File tidak dapat dibaca. Coba pilih ulang.');
      final service = ProductImportService();
      final sourceRows = ProductImportService.decode(bytes, p.extension(file.name).replaceFirst('.', ''));
      final preview = await service.prepare(sourceRows);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Periksa Impor Produk'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('File: ${file.name}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('Produk siap diimpor: ${preview.rows.length}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                  Text('Baris bermasalah: ${preview.errors.length}'),
                  const SizedBox(height: 10),
                  const Text('Produk yang sudah memiliki SKU/barcode akan dilewati. Kategori baru dibuat otomatis. Stok awal akan dicatat ke riwayat stok dan batch modal.'),
                  if (preview.errors.isNotEmpty) ...[
                    const Divider(),
                    const Text('Peringatan:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...preview.errors.take(8).map((error) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $error', style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
                    )),
                    if (preview.errors.length > 8)
                      Text('Dan ${preview.errors.length - 8} peringatan lainnya.', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
            FilledButton(
              onPressed: preview.rows.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              child: const Text('Impor Sekarang'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final report = await service.import(preview);
      if (!mounted) return;
      _refresh();
      final detail = report.errors.take(4).join('\n');
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Impor Selesai'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Berhasil diimpor: ${report.imported}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                Text('Dilewati: ${report.skipped}'),
                if (report.errors.isNotEmpty) ...[
                  const Divider(),
                  const Text('Catatan:', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(detail, style: const TextStyle(fontSize: 12)),
                  if (report.errors.length > 4)
                    Text('Dan ${report.errors.length - 4} catatan lainnya.', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Selesai'))],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengimpor produk: $error')),
      );
    }
  }

  void _openStockMovements() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const StockMovementPage()));
  }

  void _openStockOpname() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const StockOpnamePage()));
  }

  void _openPurchaseCostSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseCostSettingsPage()),
    );
  }

  String _rupiah(Object? value) {
    final amount = value is num ? value.toInt() : 0;
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return 'Rp$buffer';
  }

  int _number(TextEditingController controller) =>
      int.tryParse(controller.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;

  Future<void> _scanProductBarcode(TextEditingController controller) async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    controller.text = scanned.trim();
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
  }

  Future<void> _printProductBarcode({
    required String productName,
    required String barcode,
    String sku = '',
  }) async {
    final code = barcode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Isi atau generate barcode terlebih dahulu.')),
      );
      return;
    }

    final quantityController = TextEditingController(text: '1');
    final quantity = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Jumlah label barcode'),
        content: TextField(
          controller: quantityController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Jumlah cetak',
            helperText: 'Cetak pada gulungan kertas 58 mm.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(quantityController.text) ?? 0;
              if (value < 1 || value > 100) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Cetak'),
          ),
        ],
      ),
    );
    quantityController.dispose();
    if (quantity == null || !mounted) return;

    final settings = ReceiptSettingsRepository();
    final savedPrinter = await settings.getSavedPrinter();
    if (savedPrinter == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printer utama belum diatur. Hubungkan EPOS RPP02N melalui Pengaturan Printer.')),
      );
      return;
    }

    final manager = PrinterManager();
    try {
      await manager.connect(BluetoothPrinterDevice(
        name: savedPrinter['name']!,
        address: savedPrinter['address']!,
      ));
      for (var i = 0; i < quantity; i++) {
        final ticket = await Ticket.create(PaperSize.mm58);
        ticket.text(
          productName.trim().isEmpty ? 'PRODUK' : productName.trim(),
          align: PrintAlign.center,
          style: const PrintTextStyle(bold: true),
        );
        ticket.barcode(
          code,
          type: BarcodeType.code128,
          width: 2,
          height: 80,
          textPosition: BarcodeTextPosition.below,
          align: PrintAlign.center,
        );
        if (sku.trim().isNotEmpty) {
          ticket.text('SKU: ${sku.trim()}', align: PrintAlign.center);
        }
        ticket.feed(3);
        await manager.printTicket(ticket);
      }
      await manager.waitWriteComplete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$quantity label barcode dikirim ke ${savedPrinter['name']}. Sobek label pada garis potong kertas.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mencetak barcode: $error')),
      );
    } finally {
      await manager.dispose();
    }
  }

  Future<void> _showProductForm({Map<String, Object?>? product}) async {
    final categories = await _repository.getCategories();
    if (!mounted) return;
    final editing = product != null;
    final sku = TextEditingController(text: product?['sku']?.toString() ?? '');
    final barcode = TextEditingController(text: product?['barcode']?.toString() ?? '');
    final name = TextEditingController(text: product?['name']?.toString() ?? '');
    final category = TextEditingController(text: product?['category']?.toString() ?? '');
    final brand = TextEditingController(text: product?['brand']?.toString() ?? '');
    final unit = TextEditingController(text: product?['unit']?.toString() ?? 'pcs');
    final purchase = TextEditingController(text: formatCurrencyInput(product?['purchase_price'] ?? 0));
    final selling = TextEditingController(text: formatCurrencyInput(product?['selling_price'] ?? 0));
    final wholesale = TextEditingController(text: formatCurrencyInput(product?['wholesale_price'] ?? 0));
    final stock = TextEditingController(text: '0');
    final minimum = TextEditingController(text: product?['minimum_stock']?.toString() ?? '0');
    final description = TextEditingController(text: product?['description']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    bool trackStock = (product?['track_stock'] as int? ?? 1) == 1;
    String? imagePath = product?['image_path']?.toString();
    bool removeImage = false;
    bool printingBarcode = false;

    Future<void> chooseImage(ImageSource source, StateSetter setDialogState) async {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 72,
        maxWidth: 1000,
        maxHeight: 1000,
      );
      if (picked == null) return;
      final appDirectory = await getApplicationDocumentsDirectory();
      final imageDirectory = Directory(p.join(appDirectory.path, 'product_images'));
      await imageDirectory.create(recursive: true);
      final extension = p.extension(picked.path).isEmpty ? '.jpg' : p.extension(picked.path);
      final savedPath = p.join(
        imageDirectory.path,
        'product_${DateTime.now().microsecondsSinceEpoch}$extension',
      );
      await File(picked.path).copy(savedPath);
      setDialogState(() {
        imagePath = savedPath;
        removeImage = false;
      });
    }

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(editing ? 'Edit Produk' : 'Tambah Produk'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            AppPhotoPreview(
                              path: removeImage ? null : imagePath,
                              width: 116,
                              height: 96,
                              placeholderIcon: Icons.add_a_photo_outlined,
                              placeholderLabel: 'Foto produk',
                              borderRadius: BorderRadius.circular(10),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => chooseImage(ImageSource.camera, setDialogState),
                                  icon: const Icon(Icons.camera_alt_outlined),
                                  label: const Text('Kamera'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => chooseImage(ImageSource.gallery, setDialogState),
                                  icon: const Icon(Icons.photo_library_outlined),
                                  label: const Text('Galeri'),
                                ),
                                if (imagePath != null && !removeImage)
                                  TextButton.icon(
                                    onPressed: () => setDialogState(() => removeImage = true),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Hapus foto'),
                                  ),
                                if (removeImage)
                                  TextButton(
                                    onPressed: () => setDialogState(() {
                                      imagePath = product?['image_path']?.toString();
                                      removeImage = false;
                                    }),
                                    child: const Text('Batalkan hapus'),
                                  ),
                              ],
                            ),
                            const Text('Foto disimpan di perangkat ini.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nama produk *', border: OutlineInputBorder()), validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null),
                      const SizedBox(height: 10),
                      TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU / Kode produk', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: barcode,
                        keyboardType: TextInputType.text,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Barcode',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Scan barcode',
                            onPressed: () async {
                              await _scanProductBarcode(barcode);
                              if (context.mounted) setDialogState(() {});
                            },
                            icon: const Icon(Icons.qr_code_scanner),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              final generated = 'BK${DateTime.now().microsecondsSinceEpoch}';
                              barcode.text = generated;
                              barcode.selection = TextSelection.collapsed(offset: generated.length);
                              setDialogState(() {});
                            },
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Generate barcode'),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Format Code 128',
                              textAlign: TextAlign.end,
                              style: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                      if (barcode.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: BarcodeWidget(
                            barcode: Barcode.code128(),
                            data: barcode.text.trim(),
                            height: 64,
                            drawText: true,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: categories.any((item) => item['name']?.toString() == category.text)
                            ? category.text
                            : '',
                        decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder()),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem(value: '', child: Text('Tanpa kategori')),
                          ...categories.map((item) => DropdownMenuItem<String>(
                            value: item['name']?.toString() ?? '',
                            child: Text(item['name']?.toString() ?? ''),
                          )),
                        ],
                        onChanged: (value) => category.text = value ?? '',
                      ),
                      const SizedBox(height: 10),
                      TextFormField(controller: brand, decoration: const InputDecoration(labelText: 'Merek', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: unit, decoration: const InputDecoration(labelText: 'Satuan (pcs, set, botol...)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: purchase, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga beli (Rp)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: selling, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga jual (Rp)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: wholesale, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga grosir (Rp)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      if (!editing) TextFormField(controller: stock, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Stok awal', border: OutlineInputBorder())),
                      if (!editing) const SizedBox(height: 10),
                      TextFormField(controller: minimum, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Batas minimum stok', border: OutlineInputBorder())),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pantau stok produk'),
                        value: trackStock,
                        onChanged: (v) => setDialogState(() => trackStock = v),
                      ),
                      TextFormField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder())),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
              OutlinedButton.icon(
                onPressed: barcode.text.trim().isEmpty || printingBarcode
                    ? null
                    : () async {
                        setDialogState(() => printingBarcode = true);
                        await _printProductBarcode(
                          productName: name.text,
                          barcode: barcode.text,
                          sku: sku.text,
                        );
                        if (context.mounted) setDialogState(() => printingBarcode = false);
                      },
                icon: printingBarcode
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined),
                label: Text(printingBarcode ? 'Mencetak...' : 'Cetak Barcode'),
              ),
              FilledButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );

      if (result != true || !mounted) return;
      final values = {
        'sku': sku.text, 'barcode': barcode.text, 'name': name.text,
        'category': category.text, 'brand': brand.text, 'unit': unit.text,
        'purchase': _number(purchase), 'selling': _number(selling),
        'wholesale': _number(wholesale), 'minimum': _number(minimum),
        'track': trackStock, 'description': description.text,
        'imagePath': removeImage ? null : imagePath,
      };
      if (editing) {
        await _repository.updateProduct(
          id: product['id'] as int,
          sku: values['sku'] as String,
          barcode: values['barcode'] as String,
          name: values['name'] as String,
          category: values['category'] as String,
          brand: values['brand'] as String,
          unit: values['unit'] as String,
          purchasePrice: values['purchase'] as int,
          sellingPrice: values['selling'] as int,
          wholesalePrice: values['wholesale'] as int,
          minimumStock: values['minimum'] as int,
          trackStock: values['track'] as bool,
          description: values['description'] as String,
          imagePath: values['imagePath'] as String?,
        );
      } else {
        await _repository.addProduct(
          sku: values['sku'] as String,
          barcode: values['barcode'] as String,
          name: values['name'] as String,
          category: values['category'] as String,
          brand: values['brand'] as String,
          unit: values['unit'] as String,
          purchasePrice: values['purchase'] as int,
          sellingPrice: values['selling'] as int,
          wholesalePrice: values['wholesale'] as int,
          initialStock: values['track'] as bool ? _number(stock) : 0,
          minimumStock: values['minimum'] as int,
          trackStock: values['track'] as bool,
          description: values['description'] as String,
          imagePath: values['imagePath'] as String?,
        );
      }
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(editing ? 'Produk diperbarui.' : 'Produk ditambahkan.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan produk: $error')));
    } finally {
      for (final controller in [sku, barcode, name, category, brand, unit, purchase, selling, wholesale, stock, minimum, description]) {
        controller.dispose();
      }
    }
  }

  Future<void> _adjustStock(Map<String, Object?> product) async {
    final quantity = TextEditingController();
    final notes = TextEditingController();
    bool isIn = true;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text('Penyesuaian Stok: ' + (product['name']?.toString() ?? 'Produk')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Stok saat ini: ' + (product['stock']?.toString() ?? '0') + ' ' + (product['unit']?.toString() ?? 'pcs')),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Stok Masuk'), icon: Icon(Icons.add)),
                    ButtonSegment(value: false, label: Text('Stok Keluar'), icon: Icon(Icons.remove)),
                  ],
                  selected: {isIn},
                  onSelectionChanged: (v) => setDialogState(() => isIn = v.first),
                ),
                const SizedBox(height: 8),
                TextField(controller: quantity, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Jumlah', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Catatan (opsional)', border: OutlineInputBorder())),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Simpan')),
            ],
          ),
        ),
      );
      if (result != true || !mounted) return;
      final qty = int.tryParse(quantity.text) ?? 0;
      await _repository.adjustStock(
        productId: product['id'] as int,
        quantity: qty,
        isStockIn: isIn,
        notes: notes.text,
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok berhasil diperbarui.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memperbarui stok: $error')));
    } finally {
      quantity.dispose();
      notes.dispose();
    }
  }

  Future<void> _showHistory(Map<String, Object?> product) async {
    final history = await _repository.getStockHistory(product['id'] as int);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Riwayat Stok - ' + (product['name']?.toString() ?? 'Produk')),
        content: SizedBox(
          width: 520,
          child: history.isEmpty
              ? const Text('Belum ada riwayat pergerakan stok.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = history[index];
                    final incoming = item['movement_type'] == 'in';
                    return ListTile(
                      dense: true,
                      leading: Icon(incoming ? Icons.arrow_downward : Icons.arrow_upward, color: incoming ? Colors.green : Colors.red),
                      title: Text((item['variant_name'] == null ? '' : '${item['variant_name']} • ') + (incoming ? '+' : '-') + (item['quantity']?.toString() ?? '0') + ' ' + (product['unit']?.toString() ?? 'pcs')),
                      subtitle: Text('Sisa: ' + (item['stock_after']?.toString() ?? '-') + (item['notes'] == null ? '' : '\n' + item['notes'].toString())),
                      trailing: Text(item['created_at']?.toString().substring(0, 10) ?? ''),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ),
    );
  }

  Future<void> _showCostBatches(Map<String, Object?> product) async {
    final batches = await _repository.getCostBatches(product['id'] as int);
    if (!mounted) return;
    final remainingQty = batches.fold<int>(
      0,
      (sum, batch) => sum + ((batch['quantity_remaining'] as num?)?.toInt() ?? 0),
    );
    final remainingValue = batches.fold<int>(
      0,
      (sum, batch) => sum +
          ((batch['quantity_remaining'] as num?)?.toInt() ?? 0) *
              ((batch['unit_cost'] as num?)?.toInt() ?? 0),
    );
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Batch biaya • ${product['name']}'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Sisa: $remainingQty unit', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                  Text(_rupiah(remainingValue), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const Divider(height: 16),
              SizedBox(
                height: 320,
                child: batches.isEmpty
                    ? const Center(child: Text('Belum ada catatan batch biaya.', style: TextStyle(fontSize: 12)))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: batches.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final batch = batches[index];
                          final date = batch['received_at']?.toString() ?? '-';
                          final qty = (batch['quantity_remaining'] as num?)?.toInt() ?? 0;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              batch['batch_code']?.toString() ??
                                  batch['invoice_number']?.toString() ?? 'Batch',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'Masuk: ${date.length >= 10 ? date.substring(0, 10) : date} • Sisa $qty unit',
                              style: const TextStyle(fontSize: 10),
                            ),
                            trailing: Text(_rupiah(batch['unit_cost']), style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Tutup')),
        ],
      ),
    );
  }

  Future<void> _editVariant({
    required int productId,
    Map<String, Object?>? variant,
  }) async {
    final editing = variant != null;
    final name = TextEditingController(text: variant?['name']?.toString() ?? '');
    final sku = TextEditingController(text: variant?['sku']?.toString() ?? '');
    final barcode = TextEditingController(text: variant?['barcode']?.toString() ?? '');
    final purchase = TextEditingController(text: formatCurrencyInput(variant?['purchase_price'] ?? 0));
    final selling = TextEditingController(text: formatCurrencyInput(variant?['selling_price'] ?? 0));
    final wholesale = TextEditingController(text: formatCurrencyInput(variant?['wholesale_price'] ?? 0));
    final minimum = TextEditingController(text: variant?['minimum_stock']?.toString() ?? '0');
    final formKey = GlobalKey<FormState>();
    bool trackStock = (variant?['track_stock'] as int? ?? 1) == 1;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(editing ? 'Edit Varian' : 'Tambah Varian'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: name,
                        decoration: const InputDecoration(labelText: 'Nama varian', border: OutlineInputBorder()),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Nama varian wajib diisi.' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU varian (opsional)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: barcode, decoration: const InputDecoration(labelText: 'Barcode varian (opsional)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: purchase, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga beli (Rp)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: selling, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga jual (Rp)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: wholesale, keyboardType: TextInputType.number, inputFormatters: const [CurrencyInputFormatter()], decoration: const InputDecoration(labelText: 'Harga grosir (Rp)', border: OutlineInputBorder())),
                      const SizedBox(height: 10),
                      TextFormField(controller: minimum, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Batas minimum stok', border: OutlineInputBorder())),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pantau stok varian'),
                        value: trackStock,
                        onChanged: (value) => setDialogState(() => trackStock = value),
                      ),
                      const Text('Stok awal varian saat ini 0. Pengisian dan pergerakan stok akan dihubungkan pada tahap integrasi transaksi.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
              FilledButton.icon(
                onPressed: () {
                  if (formKey.currentState!.validate()) Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Simpan'),
              ),
            ],
          ),
        ),
      );
      if (saved != true || !mounted) return;
      final values = {
        'name': name.text,
        'sku': sku.text,
        'barcode': barcode.text,
        'purchase': _number(purchase),
        'selling': _number(selling),
        'wholesale': _number(wholesale),
        'minimum': int.tryParse(minimum.text) ?? 0,
        'track': trackStock,
      };
      if (editing) {
        await _repository.updateProductVariant(
          id: variant['id'] as int,
          name: values['name'] as String,
          sku: values['sku'] as String,
          barcode: values['barcode'] as String,
          purchasePrice: values['purchase'] as int,
          sellingPrice: values['selling'] as int,
          wholesalePrice: values['wholesale'] as int,
          minimumStock: values['minimum'] as int,
          trackStock: values['track'] as bool,
        );
      } else {
        await _repository.addProductVariant(
          productId: productId,
          name: values['name'] as String,
          sku: values['sku'] as String,
          barcode: values['barcode'] as String,
          purchasePrice: values['purchase'] as int,
          sellingPrice: values['selling'] as int,
          wholesalePrice: values['wholesale'] as int,
          minimumStock: values['minimum'] as int,
          trackStock: values['track'] as bool,
        );
      }
    } finally {
      for (final controller in [name, sku, barcode, purchase, selling, wholesale, minimum]) {
        controller.dispose();
      }
    }
  }

  Future<void> _manageVariants(Map<String, Object?> product) async {
    final productId = product['id'] as int;
    while (mounted) {
      final variants = await _repository.getProductVariants(productId);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Varian • ${product['name']}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (variants.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Belum ada varian. Tambahkan ukuran, warna, tipe, atau pilihan lainnya.'),
                  )
                else
                  SizedBox(
                    height: 320,
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: variants.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = variants[index];
                        final active = (item['is_active'] as int? ?? 1) == 1;
                        return ListTile(
                          dense: true,
                          title: Text(item['name']?.toString() ?? '-'),
                          subtitle: Text('SKU: ${item['sku'] ?? '-'} • Barcode: ${item['barcode'] ?? '-'}\nJual: ${_rupiah(item['selling_price'])} • Stok: ${item['stock'] ?? 0}'),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              Navigator.pop(dialogContext, '$value:${item['id']}');
                            },
                            itemBuilder: (_) => [
                              if (active) const PopupMenuItem(value: 'edit', child: Text('Edit varian')),
                              if (active) const PopupMenuItem(value: 'deactivate', child: Text('Nonaktifkan')),
                            ],
                          ),
                          leading: Icon(active ? Icons.tune : Icons.block, color: active ? null : Colors.grey),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Tutup')),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, 'add'),
              icon: const Icon(Icons.add),
              label: const Text('Tambah Varian'),
            ),
          ],
        ),
      );
      if (action == 'add') {
        try {
          await _editVariant(productId: productId);
        } catch (error) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menambah varian: $error')));
        }
        continue;
      }
      if (action != null && (action.startsWith('edit:') || action.startsWith('deactivate:'))) {
        final parts = action.split(':');
        final variantId = int.tryParse(parts.last);
        final matches = variants.where((item) => item['id'] == variantId).toList();
        final selected = matches.isEmpty ? null : matches.first;
        if (selected != null) {
          try {
            if (parts.first == 'edit') {
              await _editVariant(productId: productId, variant: selected);
            } else {
              await _repository.deactivateProductVariant(variantId!);
            }
          } catch (error) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memproses varian: $error')));
          }
          continue;
        }
      }
      break;
    }
    if (mounted) _refresh();
  }

  Future<void> _copyProduct(Map<String, Object?> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Salin Produk?'),
        content: Text(
          'Produk "${product['name']}" akan disalin beserta seluruh variannya. '
          'Stok setiap salinan dibuat 0, sedangkan SKU dan barcode dikosongkan. '
          'Produk asli dan riwayat transaksinya tidak berubah.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Salin'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final newId = await _repository.copyProduct(product['id'] as int);
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Produk berhasil disalin. ID produk baru: $newId')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyalin produk: $error')));
    }
  }

  Future<void> _deactivate(Map<String, Object?> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nonaktifkan Produk?'),
        content: Text('Produk ' + (product['name']?.toString() ?? '') + ' akan disembunyikan dari daftar aktif. Riwayat stok tetap disimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Nonaktifkan')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repository.deactivateProduct(product['id'] as int);
      if (!mounted) return;
      _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menonaktifkan produk: $error')));
    }
  }

  Widget _productCard(Map<String, Object?> product) {
    final stock = product['stock'] as int? ?? 0;
    final minimum = product['minimum_stock'] as int? ?? 0;
    final tracked = (product['track_stock'] as int? ?? 1) == 1;
    final low = tracked && stock <= minimum;
    final active = (product['is_active'] as int? ?? 1) == 1;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppPhotoPreview(
                  path: product['image_path']?.toString(),
                  width: 64,
                  height: 64,
                  placeholderIcon: Icons.inventory_2_outlined,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product['name']?.toString() ?? '-',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [product['sku'], product['category']]
                          .where((v) => v != null && v.toString().trim().isNotEmpty)
                          .join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                )),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'variants') {
                      _manageVariants(product);
                    }
                    if (value == 'copy') {
                      _copyProduct(product);
                    }
                    if (value == 'edit') {
                      _showProductForm(product: product);
                    }
                    if (value == 'stock') {
                      _adjustStock(product);
                    }
                    if (value == 'history') {
                      _showHistory(product);
                    }
                    if (value == 'batches') {
                      _showCostBatches(product);
                    }
                    if (value == 'deactivate') {
                      _deactivate(product);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'variants', child: Text('Kelola varian')),
                    const PopupMenuItem(value: 'copy', child: Text('Salin produk + varian')),
                    const PopupMenuItem(value: 'edit', child: Text('Edit produk')),
                    if (tracked && active) const PopupMenuItem(value: 'stock', child: Text('Stok masuk/keluar')),
                    const PopupMenuItem(value: 'history', child: Text('Riwayat stok')),
                    if (tracked) const PopupMenuItem(value: 'batches', child: Text('Riwayat harga per batch')),
                    if (active) const PopupMenuItem(value: 'deactivate', child: Text('Nonaktifkan')),
                  ],
                ),
              ],
            ),
            const Divider(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('HARGA JUAL', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                      const SizedBox(height: 2),
                      Text(_rupiah(product['selling_price']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1558A6))),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('STOK', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                      const SizedBox(height: 2),
                      Text(tracked ? stock.toString() + ' ' + (product['unit']?.toString() ?? 'pcs') : 'Tidak dipantau', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: low ? Colors.red : null)),
                    ],
                  ),
                ),
                if (low) const Tooltip(message: 'Stok mencapai batas minimum', child: Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20)),
                if (!active) const Chip(label: Text('Nonaktif')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Produk & Stok'),
        actions: [
          IconButton(
            tooltip: 'Impor produk Excel/CSV',
            onPressed: _importProducts,
            icon: const Icon(Icons.file_upload_outlined),
          ),
          IconButton(
            tooltip: 'Kelola kategori produk',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductCategoryPage()));
              if (mounted) _refresh();
            },
            icon: const Icon(Icons.category_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Pengelolaan harga produk',
            onSelected: (value) {
              if (value == 'purchase_cost') _openPurchaseCostSettings();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'purchase_cost',
                child: Row(
                  children: [
                    Icon(Icons.price_change_outlined),
                    SizedBox(width: 10),
                    Text('Metode Harga Beli'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(onPressed: _refresh, tooltip: 'Muat ulang', icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openStockMovements,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Riwayat Stok'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openStockOpname,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Stok Opname'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _refresh(),
              decoration: InputDecoration(
                hintText: 'Cari nama, SKU, barcode, kategori...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: () { _searchController.clear(); _refresh(); }, icon: const Icon(Icons.close)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            dense: true,
            visualDensity: VisualDensity.compact,
            title: const Text('Tampilkan produk nonaktif'),
            value: _showInactive,
            onChanged: (value) => setState(() { _showInactive = value; _page = 0; _loadProducts(); }),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _productsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Gagal memuat produk:\n' + snapshot.error.toString(), textAlign: TextAlign.center)));
                final products = snapshot.data ?? [];
                if (products.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.inventory_2_outlined, size: 60),
                  SizedBox(height: 8),
                  Text('Belum ada produk', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 5),
                  Text('Tekan tombol Tambah untuk memasukkan produk dan stok awal.', textAlign: TextAlign.center),
                ])));
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: products.length,
                        itemBuilder: (context, index) => _productCard(products[index]),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _page > 0
                                ? () => setState(() { _page--; _loadProducts(); })
                                : null,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Sebelumnya'),
                          ),
                          Text('Halaman ${_page + 1}'),
                          OutlinedButton.icon(
                            onPressed: products.length == _pageSize
                                ? () => setState(() { _page++; _loadProducts(); })
                                : null,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Berikutnya'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductForm(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
    );
  }
}
