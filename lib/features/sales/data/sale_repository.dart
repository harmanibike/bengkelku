import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/activity_log_repository.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/notifications/stock_reminder_notification_service.dart';

class SaleRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<void> _awardLoyaltyPoints(
    Transaction txn, {
    required int saleId,
    required int? customerId,
    required int eligibleAmount,
    required String description,
  }) async {
    if (customerId == null || eligibleAmount <= 0) return;
    final settingsRows = await txn.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['loyalty_program_settings'],
      limit: 1,
    );
    if (settingsRows.isEmpty) return;
    try {
      final decoded = jsonDecode(settingsRows.first['setting_value']?.toString() ?? '');
      if (decoded is! Map || decoded['enabled'] != true) return;
      final spend = decoded['spendAmountPerPoint'];
      if (spend is! num || spend <= 0) return;
      final points = eligibleAmount ~/ spend.toInt();
      if (points <= 0) return;
      final existing = await txn.query(
        'loyalty_point_ledger',
        columns: ['id'],
        where: 'reference_type = ? AND reference_id = ? AND entry_type = ?',
        whereArgs: ['sale', saleId, 'earn'],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await txn.insert('loyalty_point_ledger', {
        'customer_id': customerId,
        'sale_id': saleId,
        'reference_type': 'sale',
        'reference_id': saleId,
        'entry_type': 'earn',
        'points': points,
        'eligible_amount': eligibleAmount,
        'description': description,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Pengaturan loyalty yang belum valid tidak boleh menggagalkan transaksi.
    }
  }

  Future<List<Map<String, Object?>>> getSellableProducts({String keyword = ''}) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses penjualan.');
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

  Future<List<Map<String, Object?>>> getHeldTransactions() async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses transaksi kasir.');
    final db = await _db;
    return db.query('held_sales', orderBy: 'created_at ASC, id ASC');
  }

  Future<int> holdTransaction({
    required List<Map<String, Object?>> items,
    String buyerName = '',
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses transaksi kasir.');
    if (items.isEmpty) throw ArgumentError('Keranjang masih kosong.');
    final db = await _db;
    return db.insert('held_sales', {
      'buyer_name': buyerName.trim(),
      'items_json': jsonEncode(items),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteHeldTransaction(int id) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses transaksi kasir.');
    final db = await _db;
    await db.delete('held_sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> checkout({
    required List<Map<String, Object?>> items,
    required int paid,
    String? paymentMethod,
    int? customerId,
    String? customerName,
    int discount = 0,
    String? notes,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses penjualan.');
    if (items.isEmpty) throw ArgumentError('Keranjang masih kosong.');
    if (paid < 0) throw ArgumentError('Pembayaran tidak valid.');

    // Gabungkan baris produk yang sama sebelum memeriksa stok.
    // Ini mencegah stok diperiksa berulang terhadap angka stok awal yang sama.
    final mergedItems = <int, Map<String, Object?>>{};
    for (final item in items) {
      final productId = item['product_id'] as int;
      final quantity = item['quantity'] as int;
      final unitPrice = item['unit_price'] as int;
      if (quantity <= 0) {
        throw ArgumentError('Jumlah barang harus lebih dari nol.');
      }
      if (unitPrice < 0) {
        throw ArgumentError('Harga jual tidak valid.');
      }

      final existing = mergedItems[productId];
      if (existing == null) {
        mergedItems[productId] = {
          'product_id': productId,
          'quantity': quantity,
          'unit_price': unitPrice,
        };
      } else {
        if (existing['unit_price'] != unitPrice) {
          throw ArgumentError('Harga produk yang sama tidak boleh berbeda dalam satu transaksi.');
        }
        existing['quantity'] = (existing['quantity'] as int) + quantity;
      }
    }

    final db = await _db;
    final saleId = await db.transaction((txn) async {
      final settingRows = await txn.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['purchase_cost_method'], limit: 1);
      final configuredMethod = settingRows.isEmpty ? 'weighted_average' : settingRows.first['setting_value']?.toString();
      final useBatchCost = configuredMethod == 'per_batch';
      var subtotal = 0;
      final checkedItems = <Map<String, Object?>>[];

      for (final item in mergedItems.values) {
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

      if (discount < 0 || discount > subtotal) {
        throw ArgumentError('Diskon harus antara Rp0 dan subtotal.');
      }
      final total = subtotal - discount;
      final appliedPayment = paid.clamp(0, total).toInt();
      if (appliedPayment < total && customerId == null) {
        throw ArgumentError('Pilih pelanggan untuk transaksi belum lunas.');
      }
      final change = paid > total ? paid - total : 0;
      final paymentStatus = appliedPayment >= total ? 'paid' : (appliedPayment > 0 ? 'partial' : 'unpaid');
      final now = DateTime.now();
      final invoice = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.microsecondsSinceEpoch}';

      var savedCustomerName = customerName?.trim().isNotEmpty == true ? customerName!.trim() : 'Pelanggan Umum';
      if (customerId != null) {
        final customer = await txn.query('customers', columns: ['id', 'name'], where: 'id = ?', whereArgs: [customerId], limit: 1);
        if (customer.isEmpty) throw StateError('Pelanggan tidak ditemukan.');
        savedCustomerName = customer.first['name']?.toString() ?? savedCustomerName;
      }

      final saleId = await txn.insert('sales', {
        'invoice_number': invoice,
        'customer_id': customerId,
        'customer_name': savedCustomerName,
        'subtotal': subtotal,
        'discount': discount,
        'tax': 0,
        'total': total,
        'paid': appliedPayment,
        'change_amount': change,
        'payment_method': paymentMethod ?? 'cash',
        'payment_status': paymentStatus,
        'transaction_date': now.toIso8601String(),
        'notes': notes,
      });

      await ActivityLogRepository.record(
        txn,
        action: 'sale_created',
        description: 'Membuat penjualan $invoice dengan total Rp$subtotal.',
        entityType: 'sale',
        entityId: saleId,
      );
      for (final item in checkedItems) {
        final product = item['product'] as Map<String, Object?>;
        final quantity = item['quantity'] as int;
        final unitPrice = item['unit_price'] as int;
        final lineTotal = item['subtotal'] as int;
        final saleItemId = await txn.insert('sale_items', {
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
          final batchCost = await _consumeCostBatches(
            txn,
            productId: product['id'] as int,
            saleId: saleId,
            saleItemId: saleItemId,
            quantity: quantity,
          );
          if (useBatchCost) {
            await txn.update('sale_items', {'purchase_price': batchCost},
              where: 'id = ?', whereArgs: [saleItemId]);
          }
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

      if (appliedPayment > 0) {
        await txn.insert('cash_transactions', {
          'transaction_type': 'income',
          'category': 'Penjualan',
          'description': 'Pembayaran penjualan $invoice',
          'amount': appliedPayment,
          'reference_type': 'sale',
          'reference_id': saleId,
          'transaction_date': now.toIso8601String(),
        });
      }
      if (paymentStatus == 'paid') {
        await _awardLoyaltyPoints(
          txn,
          saleId: saleId,
          customerId: customerId,
          eligibleAmount: total,
          description: 'Poin dari penjualan $invoice',
        );
      }
      return saleId;
    });
    await StockReminderNotificationService.instance.syncStockReminder();
    return saleId;
  }

  Future<int> _consumeCostBatches(
    Transaction txn, {
    required int productId,
    required int saleId,
    required int saleItemId,
    required int quantity,
  }) async {
    final batches = await txn.query(
      'inventory_cost_batches',
      where: 'product_id = ? AND quantity_remaining > 0',
      whereArgs: [productId],
      orderBy: 'received_at ASC, id ASC',
    );
    var remaining = quantity;
    var totalCost = 0;
    for (final batch in batches) {
      if (remaining <= 0) break;
      final available = batch['quantity_remaining'] as int? ?? 0;
      if (available <= 0) continue;
      final take = available < remaining ? available : remaining;
      final unitCost = batch['unit_cost'] as int? ?? 0;
      await txn.update('inventory_cost_batches', {
        'quantity_remaining': available - take,
      }, where: 'id = ?', whereArgs: [batch['id']]);
      await txn.insert('sale_batch_allocations', {
        'sale_id': saleId,
        'sale_item_id': saleItemId,
        'batch_id': batch['id'],
        'quantity': take,
        'unit_cost': unitCost,
        'created_at': DateTime.now().toIso8601String(),
      });
      totalCost += take * unitCost;
      remaining -= take;
    }
    if (remaining > 0) {
      throw StateError(
        'Saldo batch biaya produk tidak mencukupi. Kekurangan $remaining unit. Periksa stok batch sebelum mengaktifkan metode per batch.',
      );
    }
    return (totalCost / quantity).round();
  }

  /// Mencatat pembayaran susulan untuk penjualan yang masih memiliki piutang.
  Future<int> addSalePayment({required int id, required int amount, String? paymentMethod}) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses pembayaran.');
    if (amount <= 0) throw ArgumentError('Jumlah pembayaran harus lebih dari nol.');
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('Transaksi penjualan tidak ditemukan.');
      final sale = rows.first;
      final status = sale['payment_status']?.toString() ?? 'paid';
      if (status == 'cancelled') throw StateError('Transaksi yang dibatalkan tidak dapat menerima pembayaran.');
      final total = sale['total'] as int? ?? 0;
      final paidBefore = sale['paid'] as int? ?? 0;
      final returnRows = await txn.rawQuery('''
        SELECT COALESCE(SUM(total_amount), 0) AS returned_amount,
               COALESCE(SUM(refunded_amount), 0) AS refunded_amount
        FROM sale_returns
        WHERE sale_id = ?
      ''', [id]);
      final returnedAmount = returnRows.first['returned_amount'] as int? ?? 0;
      final refundedAmount = returnRows.first['refunded_amount'] as int? ?? 0;
      final effectiveTotal = total - returnedAmount + refundedAmount;
      final remaining = effectiveTotal - paidBefore;
      if (remaining <= 0) throw StateError('Transaksi ini sudah lunas setelah memperhitungkan retur.');
      if (amount > remaining) throw ArgumentError('Pembayaran melebihi sisa tagihan $remaining.');
      final paidAfter = paidBefore + amount;
      final nextStatus = paidAfter >= effectiveTotal ? 'paid' : 'partial';
      final now = DateTime.now().toIso8601String();
      await txn.update('sales', {
        'paid': paidAfter,
        'payment_status': nextStatus,
        'payment_method': paymentMethod ?? sale['payment_method'] ?? 'cash',
      }, where: 'id = ?', whereArgs: [id]);
      if (nextStatus == 'paid') {
        await _awardLoyaltyPoints(
          txn,
          saleId: id,
          customerId: sale['customer_id'] as int?,
          eligibleAmount: effectiveTotal,
          description: 'Poin dari pelunasan penjualan ${sale['invoice_number'] ?? id}',
        );
      }
      await ActivityLogRepository.record(
        txn,
        action: 'sale_payment',
        description: 'Mencatat pembayaran penjualan ${sale['invoice_number'] ?? id} sebesar Rp$amount.',
        entityType: 'sale',
        entityId: id,
      );
      await txn.insert('cash_transactions', {
        'transaction_type': 'income',
        'category': 'Pembayaran Piutang Penjualan',
        'description': 'Pembayaran susulan penjualan ${sale['invoice_number'] ?? id}',
        'amount': amount,
        'reference_type': 'sale_payment',
        'reference_id': id,
        'transaction_date': now,
      });
      return paidAfter;
    });
  }

  /// Membatalkan penjualan tanpa menghapus nota atau riwayat kas.
  /// Stok dibalik berdasarkan pergerakan stok asli dari transaksi tersebut.
  Future<int> cancelSale({required int id, String? reason}) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat membatalkan penjualan.');
    final db = await _db;
    return db.transaction((txn) async {
      final sales = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (sales.isEmpty) {
        throw StateError('Transaksi penjualan tidak ditemukan.');
      }

      final sale = sales.first;
      final status = sale['payment_status']?.toString() ?? 'paid';
      if (status == 'cancelled') {
        throw StateError('Transaksi ini sudah pernah dibatalkan.');
      }
      if (!['paid', 'partial', 'unpaid'].contains(status)) {
        throw StateError('Status transaksi tidak dapat dibatalkan.');
      }

      final existingReturns = await txn.rawQuery(
        'SELECT COUNT(*) AS total FROM sale_returns WHERE sale_id = ?',
        [id],
      );
      if ((existingReturns.first['total'] as int? ?? 0) > 0) {
        throw StateError('Nota yang sudah memiliki retur tidak dapat dibatalkan seluruhnya.');
      }

      final total = sale['total'] as int? ?? 0;
      if (total <= 0) {
        throw StateError('Total transaksi tidak valid untuk pembatalan.');
      }

      final invoice = sale['invoice_number']?.toString() ?? 'ID-$id';
      final movements = await txn.query(
        'stock_movements',
        where: "reference_type = 'sale' AND reference_id = ? AND movement_type = 'out'",
        whereArgs: [id],
        orderBy: 'id ASC',
      );
      final now = DateTime.now().toIso8601String();
      final batchAllocations = await txn.query(
        'sale_batch_allocations',
        where: 'sale_id = ?',
        whereArgs: [id],
      );
      for (final allocation in batchAllocations) {
        final batchId = allocation['batch_id'] as int;
        final used = allocation['quantity'] as int? ?? 0;
        if (used > 0) {
          await txn.rawUpdate(
            'UPDATE inventory_cost_batches SET quantity_remaining = quantity_remaining + ? WHERE id = ?',
            [used, batchId],
          );
        }
      }

      final legacySaleItems = batchAllocations.isEmpty
          ? await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [id])
          : const <Map<String, Object?>>[];
      for (final movement in movements) {
        final productId = movement['product_id'] as int;
        final quantity = movement['quantity'] as int? ?? 0;
        if (quantity <= 0) continue;

        if (batchAllocations.isEmpty) {
          final matchingItems = legacySaleItems.where(
            (item) => item['product_id'] == productId,
          );
          final unitCost = matchingItems.isEmpty
              ? 0
              : matchingItems.first['purchase_price'] as int? ?? 0;
          await txn.insert('inventory_cost_batches', {
            'product_id': productId,
            'batch_code': 'CANCEL-$id-$productId',
            'quantity_received': quantity,
            'quantity_remaining': quantity,
            'unit_cost': unitCost,
            'received_at': now,
            'notes': 'Stok kembali dari pembatalan penjualan lama',
          });
        }

        final products = await txn.query(
          'products',
          columns: ['id', 'stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (products.isEmpty) {
          throw StateError(
            'Produk dari transaksi $invoice tidak ditemukan. Pembatalan dihentikan agar stok tidak salah.',
          );
        }

        final before = products.first['stock'] as int? ?? 0;
        final after = before + quantity;
        await txn.update(
          'products',
          {'stock': after, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [productId],
        );
        await txn.insert('stock_movements', {
          'product_id': productId,
          'movement_type': 'in',
          'quantity': quantity,
          'stock_before': before,
          'stock_after': after,
          'reference_type': 'sale_cancel',
          'reference_id': id,
          'notes': 'Pembatalan penjualan $invoice',
          'created_at': now,
        });
      }

      final cleanReason = reason?.trim();
      final amountReceived = (sale['paid'] as int? ?? 0).clamp(0, total).toInt();
      if (amountReceived > 0) {
        await txn.insert('cash_transactions', {
          'transaction_type': 'expense',
          'category': 'Pembatalan Penjualan',
          'description': cleanReason == null || cleanReason.isEmpty
              ? 'Pengembalian pembayaran penjualan $invoice'
              : 'Pengembalian pembayaran penjualan $invoice: $cleanReason',
          'amount': amountReceived,
          'reference_type': 'sale_cancel',
          'reference_id': id,
          'transaction_date': now,
        });
      }

      final earnedRows = await txn.query(
        'loyalty_point_ledger',
        where: 'sale_id = ? AND entry_type = ?',
        whereArgs: [id, 'earn'],
        limit: 1,
      );
      if (earnedRows.isNotEmpty) {
        final earned = earnedRows.first;
        final points = earned['points'] as int? ?? 0;
        if (points > 0) {
          await txn.insert('loyalty_point_ledger', {
            'customer_id': earned['customer_id'],
            'sale_id': id,
            'reference_type': 'sale_cancel',
            'reference_id': id,
            'entry_type': 'cancel',
            'points': -points,
            'eligible_amount': earned['eligible_amount'] ?? 0,
            'description': 'Pembatalan poin dari penjualan $invoice',
            'created_at': now,
          });
        }
      }

      await ActivityLogRepository.record(
        txn,
        action: 'sale_cancelled',
        description: 'Membatalkan penjualan $invoice.',
        entityType: 'sale',
        entityId: id,
      );
      return txn.update(
        'sales',
        {'payment_status': 'cancelled'},
        where: 'id = ? AND payment_status = ?',
        whereArgs: [id, status],
      );
    });
  }

  Future<List<Map<String, Object?>>> getSales({String keyword = ''}) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses riwayat penjualan.');
    final db = await _db;
    final term = keyword.trim();
    return db.rawQuery('''
      SELECT sales.*,
             COALESCE(NULLIF(sales.customer_name, ''), customers.name, 'Pelanggan Umum') AS customer_name,
             COALESCE(ret.returned_amount, 0) AS returned_amount,
             COALESCE(ret.refunded_amount, 0) AS refunded_amount,
             MAX(0, sales.total - sales.paid
               - COALESCE(ret.returned_amount, 0)
               + COALESCE(ret.refunded_amount, 0)) AS remaining_amount
      FROM sales
      LEFT JOIN customers ON customers.id = sales.customer_id
      LEFT JOIN (
        SELECT sale_id,
               SUM(total_amount) AS returned_amount,
               SUM(refunded_amount) AS refunded_amount
        FROM sale_returns
        GROUP BY sale_id
      ) ret ON ret.sale_id = sales.id
      WHERE (? = '' OR sales.invoice_number LIKE ?
         OR COALESCE(NULLIF(sales.customer_name, ''), customers.name, '') LIKE ?
         OR COALESCE(sales.notes, '') LIKE ?)
      ORDER BY sales.transaction_date DESC, sales.id DESC
      LIMIT 200
    ''', [term, '%$term%', '%$term%', '%$term%']);
  }

  Future<Map<String, Object?>?> getSaleById(int id) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses detail penjualan.');
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT sales.*, COALESCE(customers.name, 'Pelanggan Umum') AS customer_name,
             customers.phone AS customer_phone
      FROM sales
      LEFT JOIN customers ON customers.id = sales.customer_id
      WHERE sales.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    final items = await db.query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id ASC');
    return {...rows.first, 'items': items};
  }

  Future<List<Map<String, Object?>>> getSalePaymentHistory(int id) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses riwayat pembayaran.');
    final db = await _db;
    return db.query(
      'cash_transactions',
      where: "reference_id = ? AND reference_type IN ('sale', 'sale_payment') AND transaction_type = 'income'",
      whereArgs: [id],
      orderBy: 'transaction_date ASC, id ASC',
    );
  }
}
