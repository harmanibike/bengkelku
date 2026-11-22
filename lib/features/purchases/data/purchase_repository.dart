import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class PurchaseRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getPurchases({String keyword = ''}) async {
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
    final db = await _db;
    return db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId], orderBy: 'id ASC');
  }

  Future<List<Map<String, Object?>>> getPurchasePayments(int purchaseId) async {
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
      final supplier = await txn.query('suppliers', columns: ['id'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
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
          final lineDiscount = item['discount'] as int? ?? 0;
          final lineNetCost = ((quantity * (item['unit_cost'] as int) - lineDiscount) / quantity).round();
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
        await txn.insert('supplier_payments', {
          'supplier_id': supplierId, 'purchase_id': purchaseId, 'amount': initialPayment,
          'payment_method': _nullable(paymentMethod), 'notes': 'Pembayaran awal faktur ${invoice}',
        });
        await txn.insert('cash_transactions', {
          'transaction_type': 'expense', 'category': 'Pembayaran pembelian',
          'description': 'Pembayaran awal faktur ${invoice}', 'amount': initialPayment,
          'reference_type': 'purchase_payment', 'reference_id': purchaseId,
        });
      }
      return purchaseId;
    });
  }

  Future<void> addPayment({required int purchaseId, required int amount, String? paymentMethod, String? notes}) async {
    if (amount <= 0) throw ArgumentError('Jumlah pembayaran harus lebih dari nol.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('purchases',
        columns: ['supplier_id', 'invoice_number', 'total', 'paid', 'return_credit'],
        where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (rows.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
      final row = rows.first;
      final total = row['total'] as int? ?? 0;
      final paid = row['paid'] as int? ?? 0;
      final returnCredit = row['return_credit'] as int? ?? 0;
      final remaining = total - paid - returnCredit;
      if (amount > remaining) throw StateError('Pembayaran melebihi sisa utang Rp$remaining.');
      final nextPaid = paid + amount;
      await txn.update('purchases', {
        'paid': nextPaid, 'payment_status': nextPaid + returnCredit >= total ? 'paid' : nextPaid == 0 ? 'unpaid' : 'partial',
      }, where: 'id = ?', whereArgs: [purchaseId]);
      await txn.insert('supplier_payments', {
        'supplier_id': row['supplier_id'], 'purchase_id': purchaseId, 'amount': amount,
        'payment_method': _nullable(paymentMethod), 'notes': _nullable(notes),
      });
      await txn.insert('cash_transactions', {
        'transaction_type': 'expense', 'category': 'Pembayaran pembelian',
        'description': 'Pembayaran faktur ${row['invoice_number']}', 'amount': amount,
        'reference_type': 'purchase_payment', 'reference_id': purchaseId,
      });
    });
  }

  Future<List<Map<String, Object?>>> getOutstandingBySupplier() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT s.id AS supplier_id, s.name AS supplier_name, COUNT(p.id) AS invoice_count,
        SUM(p.total) AS total_amount, SUM(p.paid) AS paid_amount,
        SUM(p.return_credit) AS return_credit,
        SUM(MAX(p.total - p.paid - p.return_credit, 0)) AS remaining_amount
      FROM purchases p JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.total > p.paid + p.return_credit GROUP BY s.id, s.name ORDER BY remaining_amount DESC
    ''');
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
