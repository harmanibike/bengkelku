import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/activity_log_repository.dart';
import '../../../core/auth/auth_session.dart';

class PurchaseRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getPurchases({String keyword = ''}) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final db = await _db;
    final term = keyword.trim();
    return db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
      FROM purchases p LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE ? = '' OR p.invoice_number LIKE ? OR s.name LIKE ?
      ORDER BY p.purchase_date DESC, p.id DESC
    ''', [term, '%$term%', '%$term%']);
  }

  Future<List<Map<String, Object?>>> getPurchaseItems(int purchaseId) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final db = await _db;
    return db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId], orderBy: 'id ASC');
  }

  Future<List<Map<String, Object?>>> getPurchasePayments(int purchaseId) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final db = await _db;
    return db.query(
      'supplier_payments',
      where: 'purchase_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'payment_date DESC, id DESC',
    );
  }

  Future<int> createPurchase({
    required String invoiceNumber,
    required int supplierId,
    required List<Map<String, Object?>> items,
    int discount = 0,
    int initialPayment = 0,
    String? paymentMethod,
    String? notes,
    DateTime? purchaseDate,
  }) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final invoice = invoiceNumber.trim();
    if (invoice.isEmpty) throw ArgumentError('Nomor faktur wajib diisi.');
    if (items.isEmpty) throw ArgumentError('Minimal satu barang harus ditambahkan.');
    if (discount < 0 || initialPayment < 0) throw ArgumentError('Diskon dan pembayaran tidak boleh negatif.');

    var subtotal = 0;
    final normalized = <Map<String, Object?>>[];
    for (final item in items) {
      final productId = item['product_id'] as int?;
      final name = (item['product_name'] as String? ?? '').trim();
      final quantity = item['quantity'] as int? ?? 0;
      final unitCost = item['unit_cost'] as int? ?? 0;
      final lineDiscount = item['discount'] as int? ?? 0;
      if (name.isEmpty || quantity <= 0 || unitCost < 0 || lineDiscount < 0) {
        throw ArgumentError('Rincian barang pembelian tidak valid.');
      }
      final lineTotal = quantity * unitCost - lineDiscount;
      if (lineTotal < 0) throw ArgumentError('Diskon barang melebihi subtotal.');
      subtotal += lineTotal;
      normalized.add({
        'product_id': productId, 'product_name': name, 'quantity': quantity,
        'unit_cost': unitCost, 'discount': lineDiscount, 'subtotal': lineTotal,
      });
    }
    if (discount > subtotal) throw ArgumentError('Diskon pembelian melebihi subtotal.');
    final total = subtotal - discount;
    if (initialPayment > total) throw ArgumentError('Pembayaran awal melebihi total faktur.');

    final db = await _db;
    return db.transaction((txn) async {
      final supplier = await txn.query('suppliers', columns: ['id', 'name'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
      final settingRows = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['purchase_cost_method'], limit: 1);
      final configuredMethod = settingRows.isEmpty ? 'weighted_average' : settingRows.first['setting_value']?.toString();
      final costMethod = const ['weighted_average', 'last_cost', 'manual', 'per_batch'].contains(configuredMethod) ? configuredMethod! : 'weighted_average';
      if (supplier.isEmpty) throw StateError('Pemasok tidak ditemukan.');

      final purchaseId = await txn.insert('purchases', {
        'invoice_number': invoice, 'supplier_id': supplierId, 'subtotal': subtotal,
        'discount': discount, 'total': total, 'paid': initialPayment,
        'payment_status': initialPayment == 0 ? 'unpaid' : initialPayment == total ? 'paid' : 'partial',
        'purchase_date': (purchaseDate ?? DateTime.now()).toIso8601String(),
        'notes': _nullable(notes),
      });

      for (final item in normalized) {
        final purchaseItemId = await txn.insert('purchase_items', {...item, 'purchase_id': purchaseId});
        final productId = item['product_id'] as int?;
        if (productId == null) continue;
        final products = await txn.query('products',
          columns: ['stock', 'track_stock', 'is_active', 'purchase_price'],
          where: 'id = ?', whereArgs: [productId], limit: 1);
        if (products.isEmpty || (products.first['is_active'] as int? ?? 0) != 1) {
          throw StateError('Produk pembelian tidak ditemukan atau tidak aktif.');
        }
        if ((products.first['track_stock'] as int? ?? 1) == 1) {
          final before = products.first['stock'] as int? ?? 0;
          final quantity = item['quantity'] as int;
          final after = before + quantity;
          final oldCost = products.first['purchase_price'] as int? ?? 0;
          final batchTotals = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity_remaining), 0) AS quantity,
              COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
            FROM inventory_cost_batches
            WHERE product_id = ? AND quantity_remaining > 0
          ''', [productId]);
          final batchQuantity = (batchTotals.first['quantity'] as num?)?.toInt() ?? 0;
          final batchValue = (batchTotals.first['value'] as num?)?.toInt() ?? 0;
          final existingStockValue = batchQuantity == before
              ? batchValue
              : before * oldCost;
          final lineTotal = item['subtotal'] as int? ?? 0;
          final allocatedInvoiceDiscount = subtotal > 0
              ? (discount * lineTotal / subtotal).round()
              : 0;
          final lineNetCost = ((lineTotal - allocatedInvoiceDiscount) / quantity).round();
          int? nextPurchasePrice;
          if (costMethod == 'weighted_average') {
            nextPurchasePrice = after <= 0
                ? lineNetCost
                : ((existingStockValue + quantity * lineNetCost) / after).round();
          } else if (costMethod == 'last_cost') {
            nextPurchasePrice = lineNetCost;
          } else if (costMethod == 'manual') {
            nextPurchasePrice = null;
          } else if (costMethod == 'per_batch') {
            // Harga master tidak disamaratakan; HPP diambil dari batch FIFO saat penjualan.
            nextPurchasePrice = null;
          }
          await txn.update('products', {
            'stock': after,
            if (nextPurchasePrice != null) 'purchase_price': nextPurchasePrice,
            'updated_at': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [productId]);
          await txn.insert('inventory_cost_batches', {
            'product_id': productId,
            'purchase_id': purchaseId,
            'purchase_item_id': purchaseItemId,
            'batch_code': invoice,
            'quantity_received': quantity,
            'quantity_remaining': quantity,
            'unit_cost': lineNetCost,
            'received_at': (purchaseDate ?? DateTime.now()).toIso8601String(),
            'notes': 'Pembelian $invoice',
          });
          await txn.insert('stock_movements', {
            'product_id': productId, 'movement_type': 'in', 'quantity': quantity,
            'stock_before': before, 'stock_after': after, 'reference_type': 'purchase',
            'reference_id': purchaseId, 'notes': 'Pembelian ${invoice}',
          });
        }
      }

      if (initialPayment > 0) {
        // Satu timestamp dipakai bersama agar rekonsiliasi tidak terpecah
        // jika dua INSERT melewati pergantian detik.
        final paymentAt = DateTime.now().toIso8601String();
        await txn.insert('supplier_payments', {
          'supplier_id': supplierId, 'purchase_id': purchaseId, 'amount': initialPayment,
          'payment_date': paymentAt,
          'payment_method': _nullable(paymentMethod), 'notes': 'Pembayaran awal faktur ${invoice}',
        });
        await txn.insert('cash_transactions', {
          'transaction_type': 'expense', 'category': 'Pembayaran pembelian',
          'description': 'Pembayaran awal faktur ${invoice}', 'amount': initialPayment,
          'reference_type': 'purchase_payment', 'reference_id': purchaseId,
          'transaction_date': paymentAt,
        });
      }
      await ActivityLogRepository.record(
        txn,
        action: 'purchase_created',
        description: 'Mencatat pembelian faktur $invoice dari ${supplier.first['name']} senilai Rp$total.',
        entityType: 'purchase',
        entityId: purchaseId,
      );
      return purchaseId;
    });
  }

  Future<void> addPayment({required int purchaseId, required int amount, String? paymentMethod, String? notes}) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    if (amount <= 0) throw ArgumentError('Jumlah pembayaran harus lebih dari nol.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('purchases',
        columns: ['supplier_id', 'invoice_number', 'total', 'paid', 'return_credit', 'status'],
        where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (rows.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
      final row = rows.first;
      if (row['status']?.toString() == 'cancelled') throw StateError('Faktur sudah dibatalkan.');
      final total = row['total'] as int? ?? 0;
      final paid = row['paid'] as int? ?? 0;
      final returnCredit = row['return_credit'] as int? ?? 0;
      final remaining = total - paid - returnCredit;
      if (amount > remaining) throw StateError('Pembayaran melebihi sisa utang Rp$remaining.');
      final nextPaid = paid + amount;
      await txn.update('purchases', {
        'paid': nextPaid, 'payment_status': nextPaid + returnCredit >= total ? 'paid' : nextPaid == 0 ? 'unpaid' : 'partial',
      }, where: 'id = ?', whereArgs: [purchaseId]);
      final paymentAt = DateTime.now().toIso8601String();
      await txn.insert('supplier_payments', {
        'supplier_id': row['supplier_id'], 'purchase_id': purchaseId, 'amount': amount,
        'payment_method': _nullable(paymentMethod), 'payment_date': paymentAt,
        'notes': _nullable(notes),
      });
      await txn.insert('cash_transactions', {
        'transaction_type': 'expense', 'category': 'Pembayaran pembelian',
        'description': 'Pembayaran faktur ${row['invoice_number']}', 'amount': amount,
        'reference_type': 'purchase_payment', 'reference_id': purchaseId,
        'transaction_date': paymentAt,
      });
      await ActivityLogRepository.record(
        txn,
        action: 'purchase_payment_recorded',
        description: 'Mencatat pembayaran Rp$amount untuk faktur ${row['invoice_number']}.',
        entityType: 'purchase',
        entityId: purchaseId,
      );
    });
  }

  Future<List<Map<String, Object?>>> getOutstandingBySupplier() async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final db = await _db;
    return db.rawQuery('''
      SELECT s.id AS supplier_id, s.name AS supplier_name, COUNT(p.id) AS invoice_count,
        SUM(p.total) AS total_amount, SUM(p.paid) AS paid_amount,
        SUM(p.return_credit) AS return_credit,
        SUM(MAX(p.total - p.paid - p.return_credit, 0)) AS remaining_amount
      FROM purchases p JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.status = 'active' AND p.total > p.paid + p.return_credit GROUP BY s.id, s.name ORDER BY remaining_amount DESC
    ''');
  }

  Future<void> cancelPurchase({
    required int purchaseId,
    required String reason,
  }) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final note = reason.trim();
    if (note.isEmpty) throw ArgumentError('Alasan pembatalan wajib diisi.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'purchases',
        columns: ['id', 'invoice_number', 'supplier_id', 'paid', 'return_credit', 'status'],
        where: 'id = ?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
      final purchase = rows.first;
      if (purchase['status']?.toString() == 'cancelled') {
        throw StateError('Faktur ini sudah dibatalkan sebelumnya.');
      }
      if ((purchase['paid'] as num? ?? 0) > 0 ||
          (purchase['return_credit'] as num? ?? 0) > 0) {
        throw StateError(
          'Faktur memiliki pembayaran atau kredit retur. Selesaikan pembalikan pembayaran/kredit terlebih dahulu; sistem tidak akan mengubah kas secara otomatis.',
        );
      }
      final returns = await txn.query(
        'purchase_returns',
        columns: ['id'],
        where: "purchase_id = ? AND status = 'active'",
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (returns.isNotEmpty) {
        throw StateError('Faktur sudah memiliki retur aktif. Batalkan retur terlebih dahulu.');
      }
      final payments = await txn.query(
        'supplier_payments',
        columns: ['id'],
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (payments.isNotEmpty) {
        throw StateError('Riwayat pembayaran pemasok ditemukan. Faktur tidak dapat dibatalkan otomatis.');
      }

      final batches = await txn.query(
        'inventory_cost_batches',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
        orderBy: 'product_id ASC, id ASC',
      );
      final stockMovements = await txn.query(
        'stock_movements',
        columns: ['id'],
        where: "reference_type = 'purchase' AND reference_id = ?",
        whereArgs: [purchaseId],
      );
      if (stockMovements.length != batches.length) {
        throw StateError(
          'Faktur ini berasal dari pencatatan stok versi lama atau batch tidak lengkap. Audit stok manual diperlukan sebelum pembatalan.',
        );
      }
      for (final batch in batches) {
        final received = (batch['quantity_received'] as num?)?.toInt() ?? 0;
        final remaining = (batch['quantity_remaining'] as num?)?.toInt() ?? 0;
        if (received != remaining) {
          throw StateError(
            'Stok dari faktur ini sudah terpakai atau disesuaikan. Koreksi stok terlebih dahulu; pembatalan otomatis dihentikan agar stok tidak minus.',
          );
        }
      }

      final byProduct = <int, int>{};
      for (final batch in batches) {
        final productId = (batch['product_id'] as num?)?.toInt();
        final qty = (batch['quantity_received'] as num?)?.toInt() ?? 0;
        if (productId != null && qty > 0) {
          byProduct[productId] = (byProduct[productId] ?? 0) + qty;
        }
      }
      for (final batch in batches) {
        await txn.update(
          'inventory_cost_batches',
          {'quantity_remaining': 0, 'notes': 'Dibatalkan: $note'},
          where: 'id = ?',
          whereArgs: [batch['id']],
        );
      }
      for (final entry in byProduct.entries) {
        final productRows = await txn.query(
          'products',
          columns: ['stock', 'track_stock'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw StateError('Produk dari faktur tidak ditemukan; pembatalan dibatalkan.');
        }
        final before = (productRows.first['stock'] as num?)?.toInt() ?? 0;
        if ((productRows.first['track_stock'] as num?)?.toInt() != 1) continue;
        if (before < entry.value) {
          throw StateError('Stok saat ini tidak cukup untuk membalik pembelian produk ID ${entry.key}.');
        }
        final after = before - entry.value;
        await txn.update('products', {
          'stock': after,
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [entry.key]);
        await txn.insert('stock_movements', {
          'product_id': entry.key,
          'movement_type': 'out',
          'quantity': entry.value,
          'stock_before': before,
          'stock_after': after,
          'reference_type': 'purchase_cancel',
          'reference_id': purchaseId,
          'notes': 'Pembatalan faktur ${purchase['invoice_number']}: $note',
        });
        final settingRows = await txn.query(
          'app_settings',
          columns: ['setting_value'],
          where: 'setting_key = ?',
          whereArgs: ['purchase_cost_method'],
          limit: 1,
        );
        final method = settingRows.isEmpty
            ? 'weighted_average'
            : settingRows.first['setting_value']?.toString();
        if (method == 'weighted_average') {
          final totals = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity_remaining), 0) AS quantity,
              COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
            FROM inventory_cost_batches
            WHERE product_id = ? AND quantity_remaining > 0
          ''', [entry.key]);
          final qty = (totals.first['quantity'] as num?)?.toInt() ?? 0;
          final value = (totals.first['value'] as num?)?.toInt() ?? 0;
          if (qty > 0) {
            await txn.update('products', {
              'purchase_price': (value / qty).round(),
            }, where: 'id = ?', whereArgs: [entry.key]);
          }
        } else if (method == 'last_cost') {
          final previous = await txn.query(
            'inventory_cost_batches',
            columns: ['unit_cost'],
            where: 'product_id = ? AND (purchase_id IS NULL OR (purchase_id != ? AND purchase_id IN (SELECT id FROM purchases WHERE status = \'active\')))',
            whereArgs: [entry.key, purchaseId],
            orderBy: 'received_at DESC, id DESC',
            limit: 1,
          );
          if (previous.isNotEmpty) {
            await txn.update('products', {
              'purchase_price': previous.first['unit_cost'],
            }, where: 'id = ?', whereArgs: [entry.key]);
          }
        }
      }
      await txn.update('purchases', {
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'cancel_reason': note,
        'payment_status': 'cancelled',
      }, where: 'id = ?', whereArgs: [purchaseId]);
      await ActivityLogRepository.record(
        txn,
        action: 'purchase_cancelled',
        description: 'Membatalkan faktur pembelian ${purchase['invoice_number']}. Alasan: $note',
        entityType: 'purchase',
        entityId: purchaseId,
      );
    });
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
