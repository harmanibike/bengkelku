import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';

import '../../../core/database/app_database.dart';

class PurchaseReturnRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getPurchases() async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');
    final db = await _db;
    return db.rawQuery('''
      SELECT p.id, p.invoice_number, p.purchase_date, s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.status = 'active' AND EXISTS (SELECT 1 FROM purchase_items pi WHERE pi.purchase_id = p.id)
      ORDER BY p.purchase_date DESC, p.id DESC
    ''');
  }

  Future<List<Map<String, Object?>>> getReturnableItems(int purchaseId) async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');
    final db = await _db;
    return db.rawQuery('''
      SELECT pi.id AS purchase_item_id, pi.product_id, pi.product_name,
        pi.quantity AS purchased_quantity, pi.quantity_received AS received_quantity, pi.unit_cost,
        COALESCE((SELECT SUM(pri.quantity)
          FROM purchase_return_items pri
          JOIN purchase_returns pr ON pr.id = pri.purchase_return_id
          WHERE pri.purchase_item_id = pi.id AND pr.status = 'active'), 0) AS returned_quantity,
        MAX(pi.quantity_received - COALESCE((SELECT SUM(pri.quantity)
          FROM purchase_return_items pri
          JOIN purchase_returns pr ON pr.id = pri.purchase_return_id
          WHERE pri.purchase_item_id = pi.id AND pr.status = 'active'), 0), 0) AS returnable_quantity
      FROM purchase_items pi
      WHERE pi.purchase_id = ?
      ORDER BY pi.id
    ''', [purchaseId]);
  }

  Future<List<Map<String, Object?>>> getReturns() async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');
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
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');
    final db = await _db;
    return db.rawQuery('''
      SELECT pr.id AS return_id, pr.return_number, pr.total_amount,
        pr.credit_applied, pr.refund_received,
        (pr.total_amount - pr.credit_applied - pr.refund_received) AS available_credit,
        p.supplier_id, p.invoice_number AS source_invoice, s.name AS supplier_name
      FROM purchase_returns pr
      JOIN purchases p ON p.id = pr.purchase_id
      JOIN suppliers s ON s.id = p.supplier_id
      WHERE pr.status = 'active' AND pr.total_amount > pr.credit_applied + pr.refund_received
      ORDER BY pr.return_date ASC, pr.id ASC
    ''');
  }

  Future<List<Map<String, Object?>>> getCreditTargetInvoices(int returnId) async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');
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
        AND p.status = 'active' AND p.total > p.paid + p.return_credit
      ORDER BY p.purchase_date ASC, p.id ASC
    ''', [returnId]);
  }

  Future<List<Map<String, Object?>>> getCreditApplications(int returnId) async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');
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
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');

    if (amount <= 0) throw ArgumentError('Jumlah kredit harus lebih dari nol.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT pr.id AS return_id, pr.return_number, pr.status, pr.total_amount,
          pr.credit_applied, pr.refund_received,
          source.supplier_id, source.status AS source_status,
          target.id AS target_id, target.invoice_number, target.supplier_id AS target_supplier_id,
          target.total, target.paid, target.return_credit, target.status AS target_status
        FROM purchase_returns pr
        JOIN purchases source ON source.id = pr.purchase_id
        JOIN purchases target ON target.id = ?
        WHERE pr.id = ?
        LIMIT 1
      ''', [purchaseId, returnId]);
      if (rows.isEmpty) throw StateError('Retur atau faktur tujuan tidak ditemukan.');
      final row = rows.first;
      if (row['status']?.toString() == 'cancelled' || row['source_status']?.toString() == 'cancelled' || row['target_status']?.toString() == 'cancelled') throw StateError('Retur atau faktur sudah dibatalkan.');
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
    String refundPaymentMethod = 'cash',
  }) async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');

    if (!['cash', 'bank_transfer'].contains(refundPaymentMethod)) {
      throw ArgumentError('Metode penerimaan refund tidak valid.');
    }
    if (creditApplied < 0 || refundReceived < 0) {
      throw ArgumentError('Nilai penyelesaian tidak boleh negatif.');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT pr.id, pr.return_number, pr.status, pr.purchase_id, pr.total_amount,
          pr.credit_applied, pr.refund_received,
          p.supplier_id, p.invoice_number, p.total, p.paid, p.return_credit, p.status AS purchase_status
        FROM purchase_returns pr
        JOIN purchases p ON p.id = pr.purchase_id
        WHERE pr.id = ?
        LIMIT 1
      ''', [returnId]);
      if (rows.isEmpty) throw StateError('Data retur tidak ditemukan.');
      final row = rows.first;
      if (row['status']?.toString() == 'cancelled' || row['purchase_status']?.toString() == 'cancelled') throw StateError('Retur atau faktur sudah dibatalkan.');
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
      // Uang tunai dari pemasok hanya boleh diakui sebesar pembayaran
      // pembelian yang benar-benar pernah diterima pemasok, setelah refund
      // retur sebelumnya. Retur atas faktur yang belum dibayar hanya dapat
      // menjadi kredit untuk mengurangi utang, bukan pemasukan kas.
      final priorRefundRows = await txn.rawQuery('''
        SELECT COALESCE(SUM(refund_received), 0) AS total
        FROM purchase_returns
        WHERE purchase_id = ? AND id != ?
      ''', [row['purchase_id'], returnId]);
      final priorRefunds = (priorRefundRows.first['total'] as num?)?.toInt() ?? 0;
      final availableCashRefund = (paid - priorRefunds - alreadyRefund)
          .clamp(0, 1 << 62).toInt();
      if (refundReceived > availableCashRefund) {
        throw StateError(
          'Pengembalian tunai pemasok melebihi pembayaran pembelian yang tersedia. '
          'Maksimal Rp$availableCashRefund; sisanya gunakan kredit untuk mengurangi utang.',
        );
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
          'payment_method': refundPaymentMethod,
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
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');

    if (quantities.isEmpty || quantities.values.every((q) => q <= 0)) {
      throw ArgumentError('Pilih minimal satu barang dan jumlah retur.');
    }
    final number = returnNumber.trim();
    if (number.isEmpty) throw ArgumentError('Nomor retur wajib diisi.');

    final db = await _db;
    return db.transaction((txn) async {
      final purchase = await txn.query('purchases',
        columns: ['id', 'invoice_number', 'status'], where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (purchase.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
      if (purchase.first['status']?.toString() == 'cancelled') throw StateError('Faktur pembelian sudah dibatalkan.');

      var total = 0;
      final selected = <Map<String, Object?>>[];
      for (final entry in quantities.entries) {
        final quantity = entry.value;
        if (quantity <= 0) continue;
        final itemRows = await txn.query('purchase_items',
          where: 'id = ? AND purchase_id = ?', whereArgs: [entry.key, purchaseId], limit: 1);
        if (itemRows.isEmpty) throw StateError('Barang tidak sesuai dengan faktur pembelian.');
        final item = itemRows.first;
        if (item['variant_id'] != null) {
          throw StateError('Retur pembelian untuk varian belum tersedia. Stok varian tidak diubah agar pencatatan tetap akurat.');
        }
        final purchased = item['quantity'] as int? ?? 0;
        final received = (item['quantity_received'] as num?)?.toInt() ?? 0;
        final returnedRows = await txn.rawQuery('''
          SELECT COALESCE(SUM(pri.quantity), 0) AS total
          FROM purchase_return_items pri
          JOIN purchase_returns pr ON pr.id = pri.purchase_return_id
          WHERE pri.purchase_item_id = ? AND pr.status = 'active'
        ''', [entry.key]);
        final alreadyReturned = returnedRows.first['total'] as int? ?? 0;
        final available = received - alreadyReturned;
        if (quantity > available) {
          throw StateError('Retur ${item['product_name']} melebihi jumlah yang sudah diterima dan belum diretur ($available).');
        }
        final unitCost = (item['unit_cost'] as num?)?.toInt() ?? 0;
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
        final returnItemId = await txn.insert('purchase_return_items', {
          ...item,
          'purchase_return_id': returnId,
          // Isi eksplisit agar database hasil migrasi lama tidak meninggalkan
          // NULL yang dikhususkan untuk retur historis sebelum versi 34.
          'stock_deducted': 0,
        });
        final productId = item['product_id'] as int?;
        if (productId == null) continue;
        final products = await txn.query('products',
          columns: ['stock', 'track_stock', 'purchase_price'],
          where: 'id = ?', whereArgs: [productId], limit: 1);
        if (products.isEmpty || (products.first['track_stock'] as int? ?? 1) != 1) continue;
        await txn.update(
          'purchase_return_items',
          {'stock_deducted': 1},
          where: 'id = ?',
          whereArgs: [returnItemId],
        );
        final before = products.first['stock'] as int? ?? 0;
        final quantity = item['quantity'] as int;
        if (before < quantity) {
          throw StateError('Stok ${item['product_name']} tidak cukup untuk retur. Stok tersedia: $before.');
        }
        final after = before - quantity;
        var batchRemaining = quantity;
        final sourceBatches = await txn.query(
          'inventory_cost_batches',
          where: 'product_id = ? AND purchase_item_id = ? AND quantity_remaining > 0',
          whereArgs: [productId, item['purchase_item_id']],
          orderBy: 'received_at ASC, id ASC',
        );
        final batches = sourceBatches.isNotEmpty
            ? sourceBatches
            : await txn.query(
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
          await txn.insert('purchase_return_batch_allocations', {
            'return_id': returnId,
            'return_item_id': returnItemId,
            'batch_id': batch['id'],
            'quantity': take,
            'unit_cost': batch['unit_cost'] ?? 0,
            'created_at': DateTime.now().toIso8601String(),
          });
          batchRemaining -= take;
        }
        if (batchRemaining > 0) {
          throw StateError('Stok batch asal tidak mencukupi untuk retur. Sisa yang dapat diretur dari batch ini belum cukup.');
        }
        final settingRows = await txn.query(
          'app_settings',
          columns: ['setting_value'],
          where: 'setting_key = ?',
          whereArgs: ['purchase_cost_method'],
          limit: 1,
        );
        final costMethod = settingRows.isEmpty
            ? 'weighted_average'
            : settingRows.first['setting_value']?.toString();
        if (costMethod == 'weighted_average') {
          final totals = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity_remaining), 0) AS quantity,
              COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
            FROM inventory_cost_batches
            WHERE product_id = ? AND quantity_remaining > 0
          ''', [productId]);
          final remainingQty = (totals.first['quantity'] as num?)?.toInt() ?? 0;
          final remainingValue = (totals.first['value'] as num?)?.toInt() ?? 0;
          if (remainingQty > 0) {
            await txn.update('products', {
              'purchase_price': (remainingValue / remainingQty).round(),
            }, where: 'id = ?', whereArgs: [productId]);
          }
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

  Future<void> cancelReturn({
    required int returnId,
    required String reason,
  }) async {
    AuthSession.instance.requireAdmin('Fitur ini hanya dapat diakses Admin.');

    final note = reason.trim();
    if (note.isEmpty) throw ArgumentError('Alasan pembatalan wajib diisi.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT pr.*, p.invoice_number
        FROM purchase_returns pr
        JOIN purchases p ON p.id = pr.purchase_id
        WHERE pr.id = ?
        LIMIT 1
      ''', [returnId]);
      if (rows.isEmpty) throw StateError('Retur pembelian tidak ditemukan.');
      final row = rows.first;
      if (row['status']?.toString() == 'cancelled') {
        throw StateError('Retur ini sudah dibatalkan sebelumnya.');
      }
      final credit = (row['credit_applied'] as num?)?.toInt() ?? 0;
      final refund = (row['refund_received'] as num?)?.toInt() ?? 0;
      if (credit > 0 || refund > 0) {
        throw StateError(
          'Retur sudah diselesaikan dengan kredit atau uang kembali. Batalkan/selesaikan pembalikan tersebut terlebih dahulu.',
        );
      }
      final applications = await txn.query(
        'supplier_return_credit_applications',
        columns: ['id'],
        where: 'return_id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      if (applications.isNotEmpty) {
        throw StateError('Riwayat pemakaian kredit retur ditemukan. Retur tidak dapat dibatalkan otomatis.');
      }
      final allocations = await txn.query(
        'purchase_return_batch_allocations',
        where: 'return_id = ?',
        whereArgs: [returnId],
        orderBy: 'id ASC',
      );
      final returnItems = await txn.query(
        'purchase_return_items',
        where: 'purchase_return_id = ?',
        whereArgs: [returnId],
      );
      final returnItemById = <int, Map<String, Object?>>{};
      for (final item in returnItems) {
        final itemId = (item['id'] as num?)?.toInt();
        if (itemId != null) returnItemById[itemId] = item;
      }
      final allocationByItem = <int, int>{};
      for (final allocation in allocations) {
        final itemId = (allocation['return_item_id'] as num?)?.toInt();
        final batchId = (allocation['batch_id'] as num?)?.toInt();
        final quantity = (allocation['quantity'] as num?)?.toInt() ?? 0;
        final returnItem = itemId == null ? null : returnItemById[itemId];
        if (returnItem == null || batchId == null || quantity <= 0) {
          throw StateError(
            'Alokasi batch retur tidak valid. Pembatalan dihentikan untuk menjaga nilai persediaan.',
          );
        }
        final productId = (returnItem['product_id'] as num?)?.toInt();
        final batches = await txn.query(
          'inventory_cost_batches',
          columns: ['product_id'],
          where: 'id = ?',
          whereArgs: [batchId],
          limit: 1,
        );
        if (productId == null ||
            batches.isEmpty ||
            (batches.first['product_id'] as num?)?.toInt() != productId) {
          throw StateError(
            'Batch alokasi tidak sesuai dengan produk retur. Pembatalan dihentikan.',
          );
        }
        allocationByItem[itemId!] = (allocationByItem[itemId] ?? 0) + quantity;
      }

      // Gunakan pergerakan stok saat retur dibuat sebagai sumber kebenaran.
      // track_stock dapat berubah setelah transaksi dan tidak boleh mengubah
      // keputusan apakah stok perlu dikembalikan.
      final stockMovements = await txn.query(
        'stock_movements',
        columns: ['product_id', 'movement_type', 'quantity'],
        where: 'reference_type = ? AND reference_id = ?',
        whereArgs: ['purchase_return', returnId],
      );
      final recordedOutByProduct = <int, int>{};
      for (final movement in stockMovements) {
        if (movement['movement_type']?.toString() != 'out') {
          throw StateError('Riwayat pergerakan stok retur tidak valid. Pembatalan dihentikan.');
        }
        final productId = (movement['product_id'] as num?)?.toInt();
        final quantity = (movement['quantity'] as num?)?.toInt() ?? 0;
        if (productId == null || quantity <= 0) {
          throw StateError('Detail pergerakan stok retur tidak valid. Pembatalan dihentikan.');
        }
        recordedOutByProduct[productId] =
            (recordedOutByProduct[productId] ?? 0) + quantity;
      }

      final expectedByProduct = <int, int>{};
      for (final item in returnItems) {
        final productId = (item['product_id'] as num?)?.toInt();
        final quantity = (item['quantity'] as num?)?.toInt() ?? 0;
        final stockDeducted = (item['stock_deducted'] as num?)?.toInt();
        // NULL = data lama tanpa snapshot; verifikasi wajib lewat movement history.
        if (productId != null && quantity > 0 && stockDeducted != 0) {
          expectedByProduct[productId] =
              (expectedByProduct[productId] ?? 0) + quantity;
        }
      }

      for (final productId in recordedOutByProduct.keys) {
        if (!expectedByProduct.containsKey(productId)) {
          throw StateError(
            'Riwayat stok retur memuat produk yang tidak ada pada detail retur. Pembatalan dihentikan.',
          );
        }
      }

      final restoreByProduct = <int, int>{};
      for (final entry in expectedByProduct.entries) {
        final productId = entry.key;
        final expectedQuantity = entry.value;
        final recordedQuantity = recordedOutByProduct[productId];
        if (recordedQuantity != null) {
          if (recordedQuantity != expectedQuantity) {
            throw StateError(
              'Riwayat stok retur tidak sesuai dengan detail barang. Pembatalan dihentikan untuk menjaga stok.',
            );
          }
          restoreByProduct[productId] = recordedQuantity;
          continue;
        }

        // Retur lama tanpa movement tidak menyimpan bukti apakah stok
        // dikurangi saat retur dibuat. Jangan menebak dari pengaturan saat ini.
        throw StateError(
          'Retur lama tidak memiliki riwayat pergerakan stok. Pembatalan otomatis dihentikan untuk audit stok.',
        );
      }

      for (final item in returnItems) {
        final itemId = (item['id'] as num?)?.toInt();
        final expected = (item['quantity'] as num?)?.toInt() ?? 0;
        final productId = (item['product_id'] as num?)?.toInt();
        final stockDeducted = (item['stock_deducted'] as num?)?.toInt();
        final stockWasDeducted = productId != null &&
            (stockDeducted == 1 ||
                (stockDeducted == null &&
                    restoreByProduct.containsKey(productId)));
        final allocatedQuantity =
            itemId == null ? 0 : (allocationByItem[itemId] ?? 0);
        if (stockWasDeducted && allocatedQuantity != expected) {
          throw StateError(
            'Alokasi batch retur tidak lengkap. Pembatalan otomatis dihentikan untuk menjaga stok.',
          );
        }
        if (!stockWasDeducted && allocatedQuantity > 0) {
          throw StateError(
            'Alokasi batch ditemukan untuk barang yang tidak mengurangi stok. Pembatalan dihentikan untuk audit persediaan.',
          );
        }
      }
      if (allocations.isEmpty && restoreByProduct.isNotEmpty) {
        throw StateError(
          'Retur ini dibuat sebelum pencatatan alokasi batch tersedia. Pembatalan otomatis tidak aman; stok perlu diaudit terlebih dahulu.',
        );
      }
      for (final entry in restoreByProduct.entries) {
        final products = await txn.query(
          'products',
          columns: ['stock'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (products.isEmpty) throw StateError('Produk retur tidak ditemukan.');
        final before = (products.first['stock'] as num?)?.toInt() ?? 0;
        final after = before + entry.value;
        await txn.update('products', {
          'stock': after,
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [entry.key]);
        await txn.insert('stock_movements', {
          'product_id': entry.key,
          'movement_type': 'in',
          'quantity': entry.value,
          'stock_before': before,
          'stock_after': after,
          'reference_type': 'purchase_return_cancel',
          'reference_id': returnId,
          'notes': 'Pembatalan retur ${row['return_number']}: $note',
        });
      }
      for (final allocation in allocations) {
        final batchId = (allocation['batch_id'] as num).toInt();
        final quantity = (allocation['quantity'] as num).toInt();
        final updated = await txn.rawUpdate(
          'UPDATE inventory_cost_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?',
          [quantity, batchId],
        );
        if (updated != 1) throw StateError('Batch asal retur tidak ditemukan; transaksi dibatalkan.');
      }
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
        for (final productId in restoreByProduct.keys) {
          final totals = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity_remaining), 0) AS quantity,
              COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
            FROM inventory_cost_batches
            WHERE product_id = ? AND quantity_remaining > 0
          ''', [productId]);
          final quantity = (totals.first['quantity'] as num?)?.toInt() ?? 0;
          final value = (totals.first['value'] as num?)?.toInt() ?? 0;
          if (quantity > 0) {
            await txn.update('products', {
              'purchase_price': (value / quantity).round(),
            }, where: 'id = ?', whereArgs: [productId]);
          }
        }
      }
      await txn.update('purchase_returns', {
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'cancel_reason': note,
      }, where: 'id = ?', whereArgs: [returnId]);
    });
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
