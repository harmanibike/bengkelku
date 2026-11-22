import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class SaleRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getSellableProducts({String keyword = ''}) async {
    final db = await _db;
    final term = keyword.trim();
    return db.query(
      'products',
      where: term.isEmpty
          ? 'is_active = 1'
          : 'is_active = 1 AND (name LIKE ? OR sku LIKE ? OR barcode LIKE ?)',
      whereArgs: term.isEmpty ? null : ['%$term%', '%$term%', '%$term%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<int> checkout({
    required List<Map<String, Object?>> items,
    required int paid,
    String? paymentMethod,
    int? customerId,
    String? notes,
  }) async {
    if (items.isEmpty) throw ArgumentError('Keranjang masih kosong.');
    if (paid < 0) throw ArgumentError('Pembayaran tidak valid.');

    final db = await _db;
    return db.transaction((txn) async {
      var subtotal = 0;
      final checkedItems = <Map<String, Object?>>[];

      for (final item in items) {
        final productId = item['product_id'] as int;
        final quantity = item['quantity'] as int;
        if (quantity <= 0) throw ArgumentError('Jumlah barang harus lebih dari nol.');

        final rows = await txn.query(
          'products',
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Produk tidak ditemukan atau nonaktif.');
        final product = rows.first;
        final tracksStock = (product['track_stock'] as int? ?? 1) == 1;
        final stockBefore = product['stock'] as int? ?? 0;
        if (tracksStock && stockBefore < quantity) {
          throw StateError('Stok ${product['name']} tidak cukup. Tersedia: $stockBefore.');
        }
        final unitPrice = item['unit_price'] as int;
        if (unitPrice < 0) throw ArgumentError('Harga jual tidak valid.');
        final lineTotal = unitPrice * quantity;
        subtotal += lineTotal;
        checkedItems.add({
          'product': product,
          'quantity': quantity,
          'unit_price': unitPrice,
          'subtotal': lineTotal,
          'stock_before': stockBefore,
          'tracks_stock': tracksStock,
        });
      }

      if (paid < subtotal) throw ArgumentError('Pembayaran kurang dari total belanja.');
      final change = paid - subtotal;
      final now = DateTime.now();
      final invoice = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.microsecondsSinceEpoch}';

      if (customerId != null) {
        final customer = await txn.query('customers', columns: ['id'], where: 'id = ?', whereArgs: [customerId], limit: 1);
        if (customer.isEmpty) throw StateError('Pelanggan tidak ditemukan.');
      }

      final saleId = await txn.insert('sales', {
        'invoice_number': invoice,
        'customer_id': customerId,
        'subtotal': subtotal,
        'discount': 0,
        'tax': 0,
        'total': subtotal,
        'paid': paid,
        'change_amount': change,
        'payment_method': paymentMethod ?? 'cash',
        'payment_status': 'paid',
        'transaction_date': now.toIso8601String(),
        'notes': notes,
      });

      for (final item in checkedItems) {
        final product = item['product'] as Map<String, Object?>;
        final quantity = item['quantity'] as int;
        final unitPrice = item['unit_price'] as int;
        final lineTotal = item['subtotal'] as int;
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': product['id'],
          'product_name': product['name'],
          'quantity': quantity,
          'unit_price': unitPrice,
          'purchase_price': product['purchase_price'] ?? 0,
          'discount': 0,
          'subtotal': lineTotal,
        });

        if (item['tracks_stock'] == true) {
          final before = item['stock_before'] as int;
          final after = before - quantity;
          await txn.update('products', {
            'stock': after,
            'updated_at': now.toIso8601String(),
          }, where: 'id = ?', whereArgs: [product['id']]);
          await txn.insert('stock_movements', {
            'product_id': product['id'],
            'movement_type': 'out',
            'quantity': quantity,
            'stock_before': before,
            'stock_after': after,
            'reference_type': 'sale',
            'reference_id': saleId,
            'notes': 'Penjualan $invoice',
            'created_at': now.toIso8601String(),
          });
        }
      }

      await txn.insert('cash_transactions', {
        'transaction_type': 'income',
        'category': 'Penjualan',
        'description': 'Penjualan $invoice',
        'amount': subtotal,
        'reference_type': 'sale',
        'reference_id': saleId,
        'transaction_date': now.toIso8601String(),
      });
      return saleId;
    });
  }

  Future<Map<String, Object?>?> getSaleById(int id) async {
    final db = await _db;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final items = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id ASC');
    return {...rows.first, 'items': items};
  }
}
