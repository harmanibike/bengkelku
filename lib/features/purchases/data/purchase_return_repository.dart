import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class PurchaseReturnRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getPurchases() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT p.id, p.invoice_number, p.purchase_date, s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE EXISTS (SELECT 1 FROM purchase_items pi WHERE pi.purchase_id = p.id)
      ORDER BY p.purchase_date DESC, p.id DESC
    ''');
  }

  Future<List<Map<String, Object?>>> getReturnableItems(int purchaseId) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT pi.id AS purchase_item_id, pi.product_id, pi.product_name,
        pi.quantity AS purchased_quantity, pi.unit_cost,
        COALESCE((SELECT SUM(pri.quantity)
          FROM purchase_return_items pri
          JOIN purchase_returns pr ON pr.id = pri.purchase_return_id
          WHERE pri.purchase_item_id = pi.id), 0) AS returned_quantity
      FROM purchase_items pi
      WHERE pi.purchase_id = ?
      ORDER BY pi.id
    ''', [purchaseId]);
  }

  Future<List<Map<String, Object?>>> getReturns() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT pr.*, p.invoice_number, s.name AS supplier_name
      FROM purchase_returns pr
      JOIN purchases p ON p.id = pr.purchase_id
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      ORDER BY pr.return_date DESC, pr.id DESC
    ''');
  }

  Future<List<Map<String, Object?>>> getAvailableReturnCredits() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT pr.id AS return_id, pr.return_number, pr.total_amount,
        pr.credit_applied, pr.refund_received,
        (pr.total_amount - pr.credit_applied - pr.refund_received) AS available_credit,
        p.supplier_id, p.invoice_number AS source_invoice, s.name AS supplier_name
      FROM purchase_returns pr
      JOIN purchases p ON p.id = pr.purchase_id
      JOIN suppliers s ON s.id = p.supplier_id
      WHERE pr.total_amount > pr.credit_applied + pr.refund_received
      ORDER BY pr.return_date ASC, pr.id ASC
    ''');
  }

  Future<List<Map<String, Object?>>> getCreditTargetInvoices(int returnId) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT p.id, p.invoice_number, p.purchase_date, p.total, p.paid,
        p.return_credit,
        MAX(p.total - p.paid - p.return_credit, 0) AS remaining_amount
      FROM purchases p
      WHERE p.supplier_id = (
        SELECT source.supplier_id
        FROM purchase_returns source_return
        JOIN purchases source ON source.id = source_return.purchase_id
        WHERE source_return.id = ?
      )
        AND p.total > p.paid + p.return_credit
      ORDER BY p.purchase_date ASC, p.id ASC
    ''', [returnId]);
  }

  Future<List<Map<String, Object?>>> getCreditApplications(int returnId) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT a.*, p.invoice_number
      FROM supplier_return_credit_applications a
      JOIN purchases p ON p.id = a.purchase_id
      WHERE a.return_id = ?
      ORDER BY a.created_at DESC, a.id DESC
    ''', [returnId]);
  }

  Future<void> applyReturnCredit({
    required int returnId,
    required int purchaseId,
    required int amount,
  }) async {
    if (amount <= 0) throw ArgumentError('Jumlah kredit harus lebih dari nol.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT pr.id AS return_id, pr.return_number, pr.total_amount,
          pr.credit_applied, pr.refund_received,
          source.supplier_id,
          target.id AS target_id, target.invoice_number, target.supplier_id AS target_supplier_id,
          target.total, target.paid, target.return_credit
        FROM purchase_returns pr
        JOIN purchases source ON source.id = pr.purchase_id
        JOIN purchases target ON target.id = ?
        WHERE pr.id = ?
        LIMIT 1
      ''', [purchaseId, returnId]);
      if (rows.isEmpty) throw StateError('Retur atau faktur tujuan tidak ditemukan.');
      final row = rows.first;
      final supplierId = (row['supplier_id'] as num?)?.toInt();
      final targetSupplierId = (row['target_supplier_id'] as num?)?.toInt();
      if (supplierId == null || supplierId != targetSupplierId) {
        throw StateError('Kredit hanya dapat digunakan pada faktur dari pemasok yang sama.');
      }
      final totalReturn = (row['total_amount'] as num?)?.toInt() ?? 0;
      final alreadyApplied = (row['credit_applied'] as num?)?.toInt() ?? 0;
      final refunded = (row['refund_received'] as num?)?.toInt() ?? 0;
      final availableCredit = totalReturn - alreadyApplied - refunded;
      if (amount > availableCredit) {
        throw StateError('Saldo kredit retur hanya tersisa Rp${availableCredit < 0 ? 0 : availableCredit}.');
      }
      final invoiceTotal = (row['total'] as num?)?.toInt() ?? 0;
      final paid = (row['paid'] as num?)?.toInt() ?? 0;
      final appliedToInvoice = (row['return_credit'] as num?)?.toInt() ?? 0;
      final remaining = invoiceTotal - paid - appliedToInvoice;
      if (amount > remaining) {
        throw StateError('Sisa utang faktur tujuan hanya Rp${remaining < 0 ? 0 : remaining}.');
      }
      final nextCredit = appliedToInvoice + amount;
      await txn.update('purchases', {
        'return_credit': nextCredit,
        'payment_status': paid + nextCredit >= invoiceTotal
            ? 'paid'
            : paid == 0 && nextCredit == 0 ? 'unpaid' : 'partial',
      }, where: 'id = ?', whereArgs: [purchaseId]);
      await txn.update('purchase_returns', {
        'credit_applied': alreadyApplied + amount,
      }, where: 'id = ?', whereArgs: [returnId]);
      await txn.insert('supplier_return_credit_applications', {
        'return_id': returnId,
        'purchase_id': purchaseId,
        'supplier_id': supplierId,
        'amount': amount,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<void> settleReturn({
    required int returnId,
    required int creditApplied,
    required int refundReceived,
  }) async {
    if (creditApplied < 0 || refundReceived < 0) {
      throw ArgumentError('Nilai penyelesaian tidak boleh negatif.');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT pr.id, pr.return_number, pr.purchase_id, pr.total_amount,
          pr.credit_applied, pr.refund_received,
          p.supplier_id, p.invoice_number, p.total, p.paid, p.return_credit
        FROM purchase_returns pr
        JOIN purchases p ON p.id = pr.purchase_id
        WHERE pr.id = ?
        LIMIT 1
      ''', [returnId]);
      if (rows.isEmpty) throw StateError('Data retur tidak ditemukan.');
      final row = rows.first;
      final alreadyCredit = (row['credit_applied'] as num?)?.toInt() ?? 0;
      final alreadyRefund = (row['refund_received'] as num?)?.toInt() ?? 0;
      final total = (row['total_amount'] as num?)?.toInt() ?? 0;
      if (alreadyCredit + alreadyRefund + creditApplied + refundReceived > total) {
        throw StateError('Kredit dan uang kembali tidak boleh melebihi nilai retur Rp$total.');
      }
      final purchaseTotal = (row['total'] as num?)?.toInt() ?? 0;
      final paid = (row['paid'] as num?)?.toInt() ?? 0;
      final priorCredit = (row['return_credit'] as num?)?.toInt() ?? 0;
      final outstanding = purchaseTotal - paid - priorCredit;
      if (creditApplied > (outstanding < 0 ? 0 : outstanding)) {
        throw StateError('Kredit retur melebihi sisa utang faktur Rp${outstanding < 0 ? 0 : outstanding}.');
      }
      final now = DateTime.now().toIso8601String();
      await txn.update('purchase_returns', {
        'credit_applied': alreadyCredit + creditApplied,
        'refund_received': alreadyRefund + refundReceived,
      }, where: 'id = ?', whereArgs: [returnId]);
      if (creditApplied > 0) {
        final supplierId = (row['supplier_id'] as num?)?.toInt();
        if (supplierId == null) {
          throw StateError('Faktur retur tidak memiliki data pemasok untuk mencatat kredit.');
        }
        final nextCredit = priorCredit + creditApplied;
        final nextOutstanding = purchaseTotal - paid - nextCredit;
        await txn.update('purchases', {
          'return_credit': nextCredit,
          'payment_status': nextOutstanding <= 0 ? 'paid' : paid == 0 ? 'unpaid' : 'partial',
        }, where: 'id = ?', whereArgs: [row['purchase_id']]);
        await txn.insert('supplier_return_credit_applications', {
          'return_id': returnId,
          'purchase_id': row['purchase_id'],
          'supplier_id': supplierId,
          'amount': creditApplied,
          'created_at': now,
        });
      }
      if (refundReceived > 0) {
        await txn.insert('cash_transactions', {
          'transaction_type': 'income',
          'category': 'Pengembalian retur pembelian',
          'description': 'Pengembalian uang retur ${row['return_number']} dari faktur ${row['invoice_number']}',
          'amount': refundReceived,
          'reference_type': 'purchase_return_refund',
          'reference_id': returnId,
          'transaction_date': now,
        });
      }
    });
  }

  Future<int> createReturn({
    required int purchaseId,
    required String returnNumber,
    required Map<int, int> quantities,
    String? notes,
  }) async {
    if (quantities.isEmpty || quantities.values.every((q) => q <= 0)) {
      throw ArgumentError('Pilih minimal satu barang dan jumlah retur.');
    }
    final number = returnNumber.trim();
    if (number.isEmpty) throw ArgumentError('Nomor retur wajib diisi.');

    final db = await _db;
    return db.transaction((txn) async {
      final purchase = await txn.query('purchases',
        columns: ['id', 'invoice_number'], where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (purchase.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');

      var total = 0;
      final selected = <Map<String, Object?>>[];
      for (final entry in quantities.entries) {
        final quantity = entry.value;
        if (quantity <= 0) continue;
        final itemRows = await txn.query('purchase_items',
          where: 'id = ? AND purchase_id = ?', whereArgs: [entry.key, purchaseId], limit: 1);
        if (itemRows.isEmpty) throw StateError('Barang tidak sesuai dengan faktur pembelian.');
        final item = itemRows.first;
        final purchased = item['quantity'] as int? ?? 0;
        final returnedRows = await txn.rawQuery('''
          SELECT COALESCE(SUM(pri.quantity), 0) AS total
          FROM purchase_return_items pri
          JOIN purchase_returns pr ON pr.id = pri.purchase_return_id
          WHERE pri.purchase_item_id = ?
        ''', [entry.key]);
        final alreadyReturned = returnedRows.first['total'] as int? ?? 0;
        final available = purchased - alreadyReturned;
        if (quantity > available) {
          throw StateError('Retur ${item['product_name']} melebihi sisa yang dapat diretur ($available).');
        }
        final unitCost = item['unit_cost'] as int? ?? 0;
        final productId = item['product_id'] as int?;
        total += quantity * unitCost;
        selected.add({
          'purchase_item_id': entry.key,
          'product_id': productId,
          'product_name': item['product_name'],
          'quantity': quantity,
          'unit_cost': unitCost,
          'subtotal': quantity * unitCost,
        });
      }
      if (selected.isEmpty) throw ArgumentError('Jumlah retur harus lebih dari nol.');

      final returnId = await txn.insert('purchase_returns', {
        'purchase_id': purchaseId,
        'return_number': number,
        'total_amount': total,
        'notes': _nullable(notes),
        'return_date': DateTime.now().toIso8601String(),
      });

      for (final item in selected) {
        await txn.insert('purchase_return_items', {
          ...item,
          'purchase_return_id': returnId,
        });
        final productId = item['product_id'] as int?;
        if (productId == null) continue;
        final products = await txn.query('products',
          columns: ['stock', 'track_stock'],
          where: 'id = ?', whereArgs: [productId], limit: 1);
        if (products.isEmpty || (products.first['track_stock'] as int? ?? 1) != 1) continue;
        final before = products.first['stock'] as int? ?? 0;
        final quantity = item['quantity'] as int;
        if (before < quantity) {
          throw StateError('Stok ${item['product_name']} tidak cukup untuk retur. Stok tersedia: $before.');
        }
        final after = before - quantity;
        var batchRemaining = quantity;
        final batches = await txn.query(
          'inventory_cost_batches',
          where: 'product_id = ? AND quantity_remaining > 0',
          whereArgs: [productId],
          orderBy: 'received_at ASC, id ASC',
        );
        for (final batch in batches) {
          if (batchRemaining <= 0) break;
          final availableBatch = batch['quantity_remaining'] as int? ?? 0;
          final take = availableBatch < batchRemaining ? availableBatch : batchRemaining;
          if (take <= 0) continue;
          await txn.update('inventory_cost_batches', {
            'quantity_remaining': availableBatch - take,
          }, where: 'id = ?', whereArgs: [batch['id']]);
          batchRemaining -= take;
        }
        if (batchRemaining > 0) {
          throw StateError('Saldo batch produk tidak cukup untuk retur. Kekurangan: $batchRemaining.');
        }
        await txn.update('products', {
          'stock': after,
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [productId]);
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'out',
          'quantity': quantity,
          'stock_before': before,
          'stock_after': after,
          'reference_type': 'purchase_return',
          'reference_id': returnId,
          'notes': 'Retur ${number} dari faktur ${purchase.first['invoice_number']}',
        });
      }
      return returnId;
    });
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
