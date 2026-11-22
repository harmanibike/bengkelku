import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class SaleReturnRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getReturnableItems(int saleId) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT
        si.id AS sale_item_id,
        si.product_id,
        si.product_name,
        si.quantity AS sold_quantity,
        si.unit_price,
        si.purchase_price,
        COALESCE((
          SELECT SUM(sri.quantity)
          FROM sale_return_items sri
          JOIN sale_returns sr ON sr.id = sri.sale_return_id
          WHERE sri.sale_item_id = si.id
        ), 0) AS returned_quantity,
        si.quantity - COALESCE((
          SELECT SUM(sri.quantity)
          FROM sale_return_items sri
          JOIN sale_returns sr ON sr.id = sri.sale_return_id
          WHERE sri.sale_item_id = si.id
        ), 0) AS returnable_quantity
      FROM sale_items si
      WHERE si.sale_id = ?
      ORDER BY si.id ASC
    ''', [saleId]);
  }

  Future<List<Map<String, Object?>>> getReturns({String keyword = ''}) async {
    final db = await _db;
    final term = keyword.trim();
    return db.rawQuery('''
      SELECT sr.*, s.invoice_number
      FROM sale_returns sr
      JOIN sales s ON s.id = sr.sale_id
      WHERE (? = '' OR sr.return_number LIKE ? OR s.invoice_number LIKE ?)
      ORDER BY sr.return_date DESC, sr.id DESC
      LIMIT 200
    ''', [term, '%$term%', '%$term%']);
  }

  Future<Map<String, Object?>?> getReturnById(int id) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT sr.*, s.invoice_number
      FROM sale_returns sr
      JOIN sales s ON s.id = sr.sale_id
      WHERE sr.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    final items = await db.query(
      'sale_return_items',
      where: 'sale_return_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    return {...rows.first, 'items': items};
  }

  Future<int> createReturn({
    required int saleId,
    required List<Map<String, Object?>> items,
    required int refundAmount,
    String? notes,
  }) async {
    if (items.isEmpty) throw ArgumentError('Pilih minimal satu barang untuk diretur.');
    if (refundAmount < 0) throw ArgumentError('Jumlah pengembalian uang tidak valid.');

    final requested = <int, int>{};
    for (final item in items) {
      final saleItemId = item['sale_item_id'] as int;
      final quantity = item['quantity'] as int;
      if (quantity <= 0) throw ArgumentError('Jumlah retur harus lebih dari nol.');
      requested[saleItemId] = (requested[saleItemId] ?? 0) + quantity;
    }

    final db = await _db;
    return db.transaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (saleRows.isEmpty) throw StateError('Nota penjualan tidak ditemukan.');
      final sale = saleRows.first;
      if (sale['payment_status'] == 'cancelled') {
        throw StateError('Nota yang sudah dibatalkan tidak dapat diretur.');
      }

      final previousReturns = await txn.rawQuery('''
        SELECT COALESCE(SUM(total_amount), 0) AS total_returned,
               COALESCE(SUM(refunded_amount), 0) AS total_refunded
        FROM sale_returns
        WHERE sale_id = ?
      ''', [saleId]);
      final totalPreviouslyReturned = previousReturns.first['total_returned'] as int? ?? 0;
      final totalPreviouslyRefunded = previousReturns.first['total_refunded'] as int? ?? 0;

      final checked = <Map<String, Object?>>[];
      var returnTotal = 0;
      for (final entry in requested.entries) {
        final rows = await txn.query(
          'sale_items',
          where: 'id = ? AND sale_id = ?',
          whereArgs: [entry.key, saleId],
          limit: 1,
        );
        if (rows.isEmpty) throw StateError('Barang tidak termasuk dalam nota ini.');
        final saleItem = rows.first;
        final sold = saleItem['quantity'] as int? ?? 0;
        final returnedRows = await txn.rawQuery('''
          SELECT COALESCE(SUM(sri.quantity), 0) AS quantity
          FROM sale_return_items sri
          JOIN sale_returns sr ON sr.id = sri.sale_return_id
          WHERE sri.sale_item_id = ?
        ''', [entry.key]);
        final alreadyReturned = returnedRows.first['quantity'] as int? ?? 0;
        final available = sold - alreadyReturned;
        if (entry.value > available) {
          throw StateError('Jumlah retur ${saleItem['product_name']} melebihi sisa yang dapat diretur ($available).');
        }
        final unitPrice = saleItem['unit_price'] as int? ?? 0;
        final subtotal = unitPrice * entry.value;
        returnTotal += subtotal;
        checked.add({
          'sale_item': saleItem,
          'quantity': entry.value,
          'unit_price': unitPrice,
          'subtotal': subtotal,
        });
      }

      if (returnTotal <= 0) throw StateError('Nilai retur harus lebih dari nol.');
      final paid = sale['paid'] as int? ?? 0;
      final total = sale['total'] as int? ?? 0;
      final outstandingBefore = total - paid - totalPreviouslyReturned + totalPreviouslyRefunded;
      final minimumRefund = (returnTotal - (outstandingBefore > 0 ? outstandingBefore : 0))
          .clamp(0, 1 << 62).toInt();
      final availableRefund = (paid - totalPreviouslyRefunded).clamp(0, 1 << 62).toInt();
      if (minimumRefund > availableRefund) {
        throw StateError('Saldo pembayaran yang tersedia tidak cukup untuk menyelesaikan retur ini.');
      }
      if (refundAmount != minimumRefund) {
        throw ArgumentError('Jumlah pengembalian uang harus tepat $minimumRefund agar piutang dan kas tetap seimbang.');
      }

      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final returnNumber = 'RET-$stamp-${now.microsecondsSinceEpoch}';
      final cleanNotes = notes?.trim();
      final returnId = await txn.insert('sale_returns', {
        'sale_id': saleId,
        'return_number': returnNumber,
        'total_amount': returnTotal,
        'refunded_amount': refundAmount,
        'notes': cleanNotes == null || cleanNotes.isEmpty ? null : cleanNotes,
        'return_date': now.toIso8601String(),
        'created_at': now.toIso8601String(),
      });

      for (final entry in checked) {
        final saleItem = entry['sale_item'] as Map<String, Object?>;
        final quantity = entry['quantity'] as int;
        final saleItemId = saleItem['id'] as int;
        final productId = saleItem['product_id'] as int?;
        final unitPrice = entry['unit_price'] as int;
        final subtotal = entry['subtotal'] as int;
        final defaultUnitCost = saleItem['purchase_price'] as int? ?? 0;
        final returnItemId = await txn.insert('sale_return_items', {
          'sale_return_id': returnId,
          'sale_item_id': saleItemId,
          'product_id': productId,
          'product_name': saleItem['product_name'],
          'quantity': quantity,
          'unit_price': unitPrice,
          'unit_cost': defaultUnitCost,
          'subtotal': subtotal,
        });

        if (productId == null) continue;
        final productRows = await txn.query(
          'products',
          columns: ['id', 'stock', 'track_stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw StateError('Produk untuk ${saleItem['product_name']} tidak ditemukan; retur dihentikan agar stok tidak salah.');
        }
        final product = productRows.first;
        final originalStockMovements = await txn.query(
          'stock_movements',
          columns: ['id'],
          where: "reference_type = 'sale' AND reference_id = ? AND product_id = ? AND movement_type = 'out'",
          whereArgs: [saleId, productId],
          limit: 1,
        );
        // Gunakan jejak saat transaksi dibuat, bukan pengaturan stok produk saat ini.
        // Ini tetap mengembalikan stok jika pelacakan stok produk diubah setelah penjualan.
        if (originalStockMovements.isEmpty) continue;

        final originalAllocations = await txn.query(
          'sale_batch_allocations',
          where: 'sale_item_id = ?',
          whereArgs: [saleItemId],
          orderBy: 'id ASC',
        );
        var remaining = quantity;
        var restoredCost = 0;

        if (originalAllocations.isNotEmpty) {
          final returnedByBatchRows = await txn.rawQuery('''
            SELECT srb.batch_id, COALESCE(SUM(srb.quantity), 0) AS quantity
            FROM sale_return_batch_allocations srb
            JOIN sale_return_items sri ON sri.id = srb.sale_return_item_id
            WHERE sri.sale_item_id = ?
            GROUP BY srb.batch_id
          ''', [saleItemId]);
          final returnedByBatch = <int, int>{
            for (final row in returnedByBatchRows)
              row['batch_id'] as int: row['quantity'] as int? ?? 0,
          };

          for (final allocation in originalAllocations) {
            if (remaining <= 0) break;
            final batchId = allocation['batch_id'] as int;
            final originalQuantity = allocation['quantity'] as int? ?? 0;
            final alreadyReturned = returnedByBatch[batchId] ?? 0;
            final available = originalQuantity - alreadyReturned;
            if (available <= 0) continue;
            final take = available < remaining ? available : remaining;
            final unitCost = allocation['unit_cost'] as int? ?? defaultUnitCost;
            final updated = await txn.rawUpdate(
              'UPDATE inventory_cost_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?',
              [take, batchId],
            );
            if (updated != 1) {
              throw StateError('Batch biaya asal tidak ditemukan untuk barang ${saleItem['product_name']}.');
            }
            await txn.insert('sale_return_batch_allocations', {
              'sale_return_item_id': returnItemId,
              'batch_id': batchId,
              'quantity': take,
              'unit_cost': unitCost,
              'created_at': now.toIso8601String(),
            });
            restoredCost += take * unitCost;
            remaining -= take;
          }
          if (remaining > 0) {
            throw StateError('Alokasi batch asal tidak cukup untuk retur ${saleItem['product_name']}.');
          }
        } else {
          await txn.insert('inventory_cost_batches', {
            'product_id': productId,
            'batch_code': 'RETURN-$returnId-$saleItemId',
            'quantity_received': quantity,
            'quantity_remaining': quantity,
            'unit_cost': defaultUnitCost,
            'received_at': now.toIso8601String(),
            'notes': 'Stok kembali dari retur penjualan $returnNumber (nota ${sale['invoice_number']})',
          });
          restoredCost = quantity * defaultUnitCost;
        }

        final before = product['stock'] as int? ?? 0;
        final after = before + quantity;
        await txn.update('products', {
          'stock': after,
          'updated_at': now.toIso8601String(),
        }, where: 'id = ?', whereArgs: [productId]);
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'in',
          'quantity': quantity,
          'stock_before': before,
          'stock_after': after,
          'reference_type': 'sale_return',
          'reference_id': returnId,
          'notes': 'Retur penjualan $returnNumber',
          'created_at': now.toIso8601String(),
        });

        final averageCost = (restoredCost / quantity).round();
        await txn.update('sale_return_items', {'unit_cost': averageCost},
          where: 'id = ?', whereArgs: [returnItemId]);
      }

      if (refundAmount > 0) {
        await txn.insert('cash_transactions', {
          'transaction_type': 'expense',
          'category': 'Pengembalian Retur Penjualan',
          'description': 'Pengembalian uang retur $returnNumber untuk nota ${sale['invoice_number']}',
          'amount': refundAmount,
          'reference_type': 'sale_return',
          'reference_id': returnId,
          'transaction_date': now.toIso8601String(),
          'created_at': now.toIso8601String(),
        });
      }

      final effectiveTotal = total - totalPreviouslyReturned - returnTotal
          + totalPreviouslyRefunded + refundAmount;
      final nextPaymentStatus = paid >= effectiveTotal
          ? 'paid'
          : (paid > 0 ? 'partial' : 'unpaid');
      await txn.update('sales', {
        'payment_status': nextPaymentStatus,
      }, where: 'id = ?', whereArgs: [saleId]);

      return returnId;
    });
  }

  Future<Map<String, Object?>> getSaleReturnSummary(int saleId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(total_amount), 0) AS returned_amount,
             COALESCE(SUM(refunded_amount), 0) AS refunded_amount
      FROM sale_returns
      WHERE sale_id = ?
    ''', [saleId]);
    return rows.first;
  }
}
