import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/activity_log_repository.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class ProductImportPreview {
  const ProductImportPreview(this.rows, this.errors);
  final List<Map<String, Object?>> rows;
  final List<String> errors;
}

class ProductImportReport {
  const ProductImportReport(this.imported, this.skipped, this.errors);
  final int imported;
  final int skipped;
  final List<String> errors;
}

class ProductImportService {
  static List<List<String>> decode(Uint8List bytes, String extension) {
    if (extension.toLowerCase() == 'csv') return _csv(utf8.decode(bytes, allowMalformed: true).replaceFirst('\uFEFF', ''));
    if (extension.toLowerCase() != 'xlsx') throw const FormatException('Gunakan file .xlsx atau .csv.');
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) throw const FormatException('Lembar Excel tidak ditemukan.');
    final sheet = book.tables.values.first;
    return sheet.rows.map((row) => row.map((cell) => cell?.value?.toString() ?? '').toList()).toList();
  }

  static List<List<String>> _csv(String source) {
    final first = source.split(RegExp(r'\r?\n')).first;
    final delimiter = ';'.allMatches(first).length > ','.allMatches(first).length ? ';' : ',';
    final result = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < source.length; i++) {
      final ch = source[i];
      if (ch == '"') {
        if (quoted && i + 1 < source.length && source[i + 1] == '"') { field.write('"'); i++; }
        else { quoted = !quoted; }
      } else if (!quoted && ch == delimiter) {
        row.add(field.toString()); field.clear();
      } else if (!quoted && (ch == '\n' || ch == '\r')) {
        if (ch == '\r' && i + 1 < source.length && source[i + 1] == '\n') i++;
        row.add(field.toString()); field.clear();
        if (row.any((v) => v.trim().isNotEmpty)) result.add(row);
        row = <String>[];
      } else { field.write(ch); }
    }
    row.add(field.toString());
    if (row.any((v) => v.trim().isNotEmpty)) result.add(row);
    if (quoted) throw const FormatException('Tanda kutip CSV tidak berpasangan.');
    return result;
  }

  ProductImportPreview prepare(List<List<String>> input) {
    if (input.length < 2) throw const FormatException('File harus berisi header dan minimal satu produk.');
    final headers = input.first.map(_header).toList();
    if (!headers.contains('name')) throw const FormatException('Kolom name/nama_produk wajib ada.');
    final rows = <Map<String, Object?>>[];
    final errors = <String>[];
    final skus = <String>{}, barcodes = <String>{};
    for (var i = 1; i < input.length; i++) {
      final cells = input[i];
      if (cells.every((v) => v.trim().isEmpty)) continue;
      final values = <String, String>{};
      for (var c = 0; c < headers.length; c++) { values[headers[c]] = c < cells.length ? cells[c].trim() : ''; }
      final name = values['name'] ?? '';
      if (name.isEmpty) { errors.add('Baris ${i + 1}: nama produk kosong.'); continue; }
      final sku = _clean(values['sku']), barcode = _clean(values['barcode']);
      if (sku != null && !skus.add(sku.toLowerCase())) { errors.add('Baris ${i + 1}: SKU duplikat di file.'); continue; }
      if (barcode != null && !barcodes.add(barcode.toLowerCase())) { errors.add('Baris ${i + 1}: barcode duplikat di file.'); continue; }
      final purchase = _number(values['purchase_price']), selling = _number(values['selling_price']);
      final wholesale = _number(values['wholesale_price']), stock = _number(values['stock']);
      final minimum = _number(values['minimum_stock']);
      if ([purchase, selling, wholesale, stock, minimum].any((v) => v < 0)) {
        errors.add('Baris ${i + 1}: harga/stok tidak valid.'); continue;
      }
      rows.add({
        'row': i + 1, 'sku': sku, 'barcode': barcode, 'name': name,
        'category': _clean(values['category']), 'brand': _clean(values['brand']),
        'unit': _clean(values['unit']) ?? 'pcs', 'purchase': purchase,
        'selling': selling, 'wholesale': wholesale, 'stock': stock,
        'minimum': minimum, 'track': values['track_stock'] == '0' ? 0 : 1,
        'description': _clean(values['description']),
      });
    }
    if (rows.isEmpty && errors.isEmpty) throw const FormatException('Tidak ada produk pada file.');
    return ProductImportPreview(rows, errors);
  }

  Future<ProductImportReport> import(ProductImportPreview preview) async {
    AuthSession.instance.requireAdmin('Impor produk hanya dapat dilakukan Admin.');
    final db = await AppDatabase.instance.database;
    final errors = List<String>.from(preview.errors);
    var imported = 0;
    await db.transaction((txn) async {
      final seenSku = <String>{}, seenBarcode = <String>{};
      final now = DateTime.now().toIso8601String();
      for (final row in preview.rows) {
        final sku = row['sku'] as String?, barcode = row['barcode'] as String?;
        var duplicate = false;
        if (sku != null) {
          final p = await txn.query('products', columns: ['id'], where: 'LOWER(sku)=?', whereArgs: [sku.toLowerCase()], limit: 1);
          final v = await txn.query('product_variants', columns: ['id'], where: 'LOWER(sku)=?', whereArgs: [sku.toLowerCase()], limit: 1);
          if (p.isNotEmpty || v.isNotEmpty || !seenSku.add(sku.toLowerCase())) {
            errors.add('Baris ${row['row']}: SKU "$sku" sudah digunakan; dilewati.'); duplicate = true;
          }
        }
        if (barcode != null) {
          final p = await txn.query('products', columns: ['id'], where: 'LOWER(barcode)=?', whereArgs: [barcode.toLowerCase()], limit: 1);
          final v = await txn.query('product_variants', columns: ['id'], where: 'LOWER(barcode)=?', whereArgs: [barcode.toLowerCase()], limit: 1);
          if (p.isNotEmpty || v.isNotEmpty || !seenBarcode.add(barcode.toLowerCase())) {
            errors.add('Baris ${row['row']}: barcode "$barcode" sudah digunakan; dilewati.'); duplicate = true;
          }
        }
        if (duplicate) continue;
        final category = row['category'] as String?;
        if (category != null) {
          await txn.insert('product_categories', {'name': category}, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        final track = row['track'] == 1, stock = row['stock'] as int;
        final id = await txn.insert('products', {
          'sku': sku, 'barcode': barcode, 'name': row['name'], 'category': category,
          'brand': row['brand'], 'unit': row['unit'], 'purchase_price': row['purchase'],
          'selling_price': row['selling'], 'wholesale_price': row['wholesale'],
          'stock': track ? stock : 0, 'minimum_stock': row['minimum'],
          'track_stock': track ? 1 : 0, 'description': row['description'],
          'is_active': 1, 'created_at': now,
        });
        if (track && stock > 0) {
          await txn.insert('inventory_cost_batches', {
            'product_id': id, 'batch_code': 'IMPORT-$id',
            'quantity_received': stock, 'quantity_remaining': stock,
            'unit_cost': row['purchase'], 'received_at': now,
            'notes': 'Stok awal dari impor produk',
          });
          await txn.insert('stock_movements', {
            'product_id': id, 'movement_type': 'in', 'quantity': stock,
            'stock_before': 0, 'stock_after': stock,
            'reference_type': 'initial_stock_import', 'reference_id': id,
            'notes': 'Stok awal dari impor produk',
          });
        }
        imported++;
      }
      if (imported > 0) {
        await ActivityLogRepository.record(txn, action: 'products_imported',
          description: 'Mengimpor $imported produk. Baris dilewati: ${preview.rows.length - imported}.',
          entityType: 'product');
      }
    });
    return ProductImportReport(imported, preview.rows.length - imported, errors);
  }

  static String _header(String value) {
    final key = value.trim().toLowerCase().replaceAll(RegExp(r'[\s\-/]+'), '_');
    const aliases = {
      'nama': 'name', 'nama_produk': 'name', 'kode_sku': 'sku', 'kode_produk': 'sku',
      'kode_barcode': 'barcode', 'kategori_produk': 'category', 'merek': 'brand',
      'satuan': 'unit', 'harga_beli': 'purchase_price', 'harga_jual': 'selling_price',
      'harga_grosir': 'wholesale_price', 'stok_awal': 'stock', 'stok': 'stock',
      'stok_minimum': 'minimum_stock', 'batas_minimum_stok': 'minimum_stock',
      'pantau_stok': 'track_stock', 'keterangan': 'description',
    };
    return aliases[key] ?? key;
  }

  static int _number(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9-]'), '')) ?? -1;
  }
  static String? _clean(String? value) {
    final text = value?.trim(); return text == null || text.isEmpty ? null : text;
  }
}
