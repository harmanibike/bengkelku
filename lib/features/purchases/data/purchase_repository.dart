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
      if (supplier.isEmpty) throw StateError('Pemasok tidak ditemukan.');

      final purchaseId = await txn.insert('purchases', {
        'invoice_number': invoice, 'supplier_id': supplierId, 'subtotal': subtotal,
        'discount': discount, 'total': total, 'paid': initialPayment,
        'payment_status': initialPayment == 0 ? 'unpaid' : initialPayment == total ? 'paid' : 'partial',
        'purchase_date': (purchaseDate ?? DateTime.now()).toIso8601String(),
        'notes': _nullable(notes),
      });

      for (final item in normalized) {
        await txn.insert('purchase_items', {...item, 'purchase_id': purchaseId});
        final productId = item['product_id'] as int?;
        if (productId == null) continue;
        final products = await txn.query('products',
          columns: ['stock', 'track_stock', 'is_active'],
          where: 'id = ?', whereArgs: [productId], limit: 1);
        if (products.isEmpty || (products.first['is_active'] as int? ?? 0) != 1) {
          throw StateError('Produk pembelian tidak ditemukan atau tidak aktif.');
        }
        if ((products.first['track_stock'] as int? ?? 1) == 1) {
          final before = products.first['stock'] as int? ?? 0;
          final quantity = item['quantity'] as int;
          final after = before + quantity;
          await txn.update('products', {
            'stock': after, 'purchase_price': item['unit_cost'],
            'updated_at': DateTime.now().toIso8601String(),
          }, where: 'id = ?', whereArgs: [productId]);
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
        columns: ['supplier_id', 'invoice_number', 'total', 'paid'],
        where: 'id = ?', whereArgs: [purchaseId], limit: 1);
      if (rows.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
      final row = rows.first;
      final total = row['total'] as int? ?? 0;
      final paid = row['paid'] as int? ?? 0;
      final remaining = total - paid;
      if (amount > remaining) throw StateError('Pembayaran melebihi sisa utang Rp$remaining.');
      final nextPaid = paid + amount;
      await txn.update('purchases', {
        'paid': nextPaid, 'payment_status': nextPaid == total ? 'paid' : 'partial',
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
        SUM(p.total - p.paid) AS remaining_amount
      FROM purchases p JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.total > p.paid GROUP BY s.id, s.name ORDER BY remaining_amount DESC
    ''');
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
