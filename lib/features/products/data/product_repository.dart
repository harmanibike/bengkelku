import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class ProductRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getProducts({
    String keyword = '',
    bool includeInactive = false,
  }) async {
    final db = await _db;
    final query = keyword.trim();
    final where = <String>[];
    final args = <Object?>[];
    if (!includeInactive) {
      where.add('is_active = 1');
    }
    if (query.isNotEmpty) {
      where.add('(name LIKE ? OR sku LIKE ? OR barcode LIKE ? OR category LIKE ? OR brand LIKE ?)');
      final term = '%$query%';
      args.addAll([term, term, term, term, term]);
    }
    return db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<int> addProduct({
    String? sku,
    String? barcode,
    required String name,
    String? category,
    String? brand,
    String unit = 'pcs',
    int purchasePrice = 0,
    int sellingPrice = 0,
    int wholesalePrice = 0,
    int initialStock = 0,
    int minimumStock = 0,
    bool trackStock = true,
    String? description,
    String? imagePath,
  }) async {
    final db = await _db;
    return db.transaction((txn) async {
      final id = await txn.insert('products', {
        'sku': _nullable(sku),
        'barcode': _nullable(barcode),
        'name': name.trim(),
        'category': _nullable(category),
        'brand': _nullable(brand),
        'unit': unit.trim().isEmpty ? 'pcs' : unit.trim(),
        'purchase_price': purchasePrice,
        'selling_price': sellingPrice,
        'wholesale_price': wholesalePrice,
        'stock': trackStock ? initialStock : 0,
        'minimum_stock': minimumStock,
        'track_stock': trackStock ? 1 : 0,
        'description': _nullable(description),
        'image_path': _nullable(imagePath),
        'is_active': 1,
      });
      if (trackStock && initialStock > 0) {
        await txn.insert('inventory_cost_batches', {
          'product_id': id,
          'batch_code': 'OPENING-$id',
          'quantity_received': initialStock,
          'quantity_remaining': initialStock,
          'unit_cost': purchasePrice,
          'received_at': DateTime.now().toIso8601String(),
          'notes': 'Stok awal produk',
        });
        await txn.insert('stock_movements', {
          'product_id': id,
          'movement_type': 'in',
          'quantity': initialStock,
          'stock_before': 0,
          'stock_after': initialStock,
          'reference_type': 'initial_stock',
          'reference_id': id,
          'notes': 'Stok awal produk',
        });
      }
      return id;
    });
  }

  Future<int> updateProduct({
    required int id,
    String? sku,
    String? barcode,
    required String name,
    String? category,
    String? brand,
    String unit = 'pcs',
    int purchasePrice = 0,
    int sellingPrice = 0,
    int wholesalePrice = 0,
    int minimumStock = 0,
    bool trackStock = true,
    String? description,
    String? imagePath,
  }) async {
    final db = await _db;
    return db.update('products', {
      'sku': _nullable(sku),
      'barcode': _nullable(barcode),
      'name': name.trim(),
      'category': _nullable(category),
      'brand': _nullable(brand),
      'unit': unit.trim().isEmpty ? 'pcs' : unit.trim(),
      'purchase_price': purchasePrice,
      'selling_price': sellingPrice,
      'wholesale_price': wholesalePrice,
      'minimum_stock': minimumStock,
      'track_stock': trackStock ? 1 : 0,
      'description': _nullable(description),
      'image_path': _nullable(imagePath),
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock({
    required int productId,
    required int quantity,
    required bool isStockIn,
    String? notes,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Jumlah stok harus lebih dari nol.');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['stock', 'track_stock', 'name', 'purchase_price'],
        where: 'id = ? AND is_active = 1',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Produk tidak ditemukan atau sudah dinonaktifkan.');
      }
      if ((rows.first['track_stock'] as int? ?? 1) != 1) {
        throw StateError('Pelacakan stok produk ini sedang dinonaktifkan.');
      }
      final before = rows.first['stock'] as int? ?? 0;
      final after = isStockIn ? before + quantity : before - quantity;
      if (after < 0) {
        throw StateError('Stok tidak mencukupi. Stok saat ini: $before.');
      }
      final now = DateTime.now().toIso8601String();
      if (isStockIn) {
        final unitCost = rows.first['purchase_price'] as int? ?? 0;
        await txn.insert('inventory_cost_batches', {
          'product_id': productId,
          'batch_code': 'ADJ-$productId-${DateTime.now().microsecondsSinceEpoch}',
          'quantity_received': quantity,
          'quantity_remaining': quantity,
          'unit_cost': unitCost,
          'received_at': now,
          'notes': 'Penambahan stok manual',
        });
      } else {
        var remaining = quantity;
        final batches = await txn.query(
          'inventory_cost_batches',
          where: 'product_id = ? AND quantity_remaining > 0',
          whereArgs: [productId],
          orderBy: 'received_at ASC, id ASC',
        );
        for (final batch in batches) {
          if (remaining <= 0) break;
          final available = batch['quantity_remaining'] as int? ?? 0;
          final take = available < remaining ? available : remaining;
          if (take <= 0) continue;
          await txn.update('inventory_cost_batches', {
            'quantity_remaining': available - take,
          }, where: 'id = ?', whereArgs: [batch['id']]);
          remaining -= take;
        }
        if (remaining > 0) {
          throw StateError('Saldo batch biaya tidak cukup untuk mengurangi stok. Kekurangan: $remaining.');
        }
      }
      await txn.update('products', {
        'stock': after,
        'updated_at': now,
      }, where: 'id = ?', whereArgs: [productId]);
      await txn.insert('stock_movements', {
        'product_id': productId,
        'movement_type': isStockIn ? 'in' : 'out',
        'quantity': quantity,
        'stock_before': before,
        'stock_after': after,
        'reference_type': 'manual_adjustment',
        'reference_id': productId,
        'notes': _nullable(notes),
      });
    });
  }

  Future<int> deactivateProduct(int id) async {
    final db = await _db;
    return db.update('products', {
      'is_active': 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> getStockHistory(int productId) async {
    final db = await _db;
    return db.query(
      'stock_movements',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'id DESC',
    );
  }

  Future<int> countLowStock() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM products WHERE is_active = 1 AND track_stock = 1 AND stock <= minimum_stock',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
