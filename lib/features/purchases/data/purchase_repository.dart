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
      WHERE ? = '' OR p.invoice_number LIKE ? OR s.name LIKE ? OR COALESCE(p.order_number, '') LIKE ? OR COALESCE(p.tracking_number, '') LIKE ?
      ORDER BY p.purchase_date DESC, p.id DESC
    ''', [term, '%$term%', '%$term%', '%$term%', '%$term%']);
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
    String purchaseType = 'direct',
    String? marketplace,
    String? orderNumber,
    String? trackingNumber,
    int shippingFee = 0,
    int packingFee = 0,
    int insuranceFee = 0,
    int marketplaceFee = 0,
    int transferFee = 0,
    int otherFee = 0,
    int initialPayment = 0,
    String? paymentMethod,
    String? notes,
    DateTime? purchaseDate,
  }) async {
    AuthSession.instance.requireAdmin('Fitur pembelian hanya dapat diakses Admin.');
    final invoice = invoiceNumber.trim();
    if (invoice.isEmpty) throw ArgumentError('Nomor faktur wajib diisi.');
    if (items.isEmpty) throw ArgumentError('Minimal satu barang harus ditambahkan.');
    final fees = [shippingFee, packingFee, insuranceFee, marketplaceFee, transferFee, otherFee];
    if (!const ['direct', 'online'].contains(purchaseType)) throw ArgumentError('Jenis pembelian tidak valid.');
    if (discount < 0 || initialPayment < 0 || fees.any((fee) => fee < 0)) {
      throw ArgumentError('Diskon, biaya tambahan, dan pembayaran tidak boleh negatif.');
    }
    if (purchaseType == 'online' && (marketplace?.trim().isEmpty ?? true)) {
      throw ArgumentError('Nama marketplace/toko online wajib diisi untuk pembelian online.');
    }
    var subtotal = 0;
    final normalized = <Map<String, Object?>>[];
    for (final item in items) {
      final productId = item['product_id'] as int?;
      final variantId = item['variant_id'] as int?;
      final name = (item['product_name'] as String? ?? '').trim();
      final quantity = item['quantity'] as int? ?? 0;
      final unitCost = item['unit_cost'] as int? ?? 0;
      final lineDiscount = item['discount'] as int? ?? 0;
      if (variantId != null && productId == null) {
        throw ArgumentError('Varian pembelian harus terhubung ke produk induk.');
      }
      if (name.isEmpty || quantity <= 0 || unitCost < 0 || lineDiscount < 0) {
        throw ArgumentError('Rincian barang pembelian tidak valid.');
      }
      final lineTotal = quantity * unitCost - lineDiscount;
      if (lineTotal < 0) throw ArgumentError('Diskon barang melebihi subtotal.');
      subtotal += lineTotal;
      normalized.add({
        'product_id': productId, 'variant_id': variantId, 'product_name': name,
        'quantity': quantity, 'unit_cost': unitCost, 'discount': lineDiscount, 'subtotal': lineTotal,
      });
    }
    if (discount > subtotal) throw ArgumentError('Diskon pembelian melebihi subtotal.');
    final additionalCosts = fees.fold<int>(0, (sum, fee) => sum + fee);
    final total = subtotal - discount + additionalCosts;
    if (initialPayment > total) throw ArgumentError('Pembayaran awal melebihi total faktur.');
    final db = await _db;
    return db.transaction((txn) async {
      final supplier = await txn.query('suppliers', columns: ['id', 'name'], where: 'id = ?', whereArgs: [supplierId], limit: 1);
      if (supplier.isEmpty) throw StateError('Pemasok tidak ditemukan.');
      final lineCosts = _allocatePurchaseLineCosts(
        normalized.map((item) => item['subtotal'] as int).toList(),
        discount: discount,
        additionalCosts: additionalCosts,
      );
      final purchaseId = await txn.insert('purchases', {
        'invoice_number': invoice, 'supplier_id': supplierId, 'subtotal': subtotal,
        'discount': discount, 'total': total, 'paid': initialPayment,
        'purchase_type': purchaseType,
        'marketplace': _nullable(marketplace),
        'order_number': _nullable(orderNumber),
        'tracking_number': _nullable(trackingNumber),
        'shipping_fee': shippingFee,
        'packing_fee': packingFee,
        'insurance_fee': insuranceFee,
        'marketplace_fee': marketplaceFee,
        'transfer_fee': transferFee,
        'other_fee': otherFee,
        'payment_status': initialPayment == 0 ? 'unpaid' : initialPayment == total ? 'paid' : 'partial',
        'receiving_status': 'pending',
        'purchase_date': (purchaseDate ?? DateTime.now()).toIso8601String(), 'notes': _nullable(notes),
      });
      for (var index = 0; index < normalized.length; index++) {
        final item = normalized[index];
        final productId = item['product_id'] as int?;
        final variantId = item['variant_id'] as int?;
        final quantity = item['quantity'] as int;
        final allocatedUnitCost = lineCosts[index] ~/ quantity;
        if (productId != null) {
          final products = await txn.query('products',
            columns: ['is_active'], where: 'id = ?', whereArgs: [productId], limit: 1);
          if (products.isEmpty || (products.first['is_active'] as int? ?? 0) != 1) {
            throw StateError('Produk pembelian tidak ditemukan atau tidak aktif.');
          }
          if (variantId != null) {
            final variants = await txn.query('product_variants',
              where: 'id = ? AND product_id = ? AND is_active = 1',
              whereArgs: [variantId, productId], limit: 1);
            if (variants.isEmpty) throw StateError('Varian pembelian tidak ditemukan, tidak aktif, atau bukan milik produk tersebut.');
          }
        }
        await txn.insert('purchase_items', {
          ...item,
          'purchase_id': purchaseId,
          'quantity_received': 0,
          'allocated_unit_cost': allocatedUnitCost,
          'allocated_landed_total': lineCosts[index],
          'received_cost_total': 0,
        });
      }
      if (initialPayment > 0) {
        final paymentAt = DateTime.now().toIso8601String();
        await txn.insert('supplier_payments', {
          'supplier_id': supplierId, 'purchase_id': purchaseId, 'amount': initialPayment,
          'payment_date': paymentAt, 'payment_method': _nullable(paymentMethod),
          'notes': 'Pembayaran awal faktur $invoice',
        });
        await txn.insert('cash_transactions', {
          'transaction_type': 'expense', 'category': 'Pembayaran pembelian',
          'description': 'Pembayaran awal faktur $invoice', 'amount': initialPayment,
          'reference_type': 'purchase_payment', 'reference_id': purchaseId,
          'payment_method': _nullable(paymentMethod) ?? 'cash', 'transaction_date': paymentAt,
        });
      }
      await ActivityLogRepository.record(txn,
        action: 'purchase_created',
        description: 'Mencatat pembelian faktur $invoice dari ${supplier.first['name']} senilai Rp$total.',
        entityType: 'purchase', entityId: purchaseId);
      return purchaseId;
    });
  }


  /// Membagi diskon faktur dan biaya perolehan secara proporsional.
  /// Metode sisa terbesar memastikan seluruh rupiah teralokasi tanpa selisih pembulatan.
  List<int> _allocatePurchaseLineCosts(
    List<int> lineSubtotals, {
    required int discount,
    required int additionalCosts,
  }) {
    final subtotal = lineSubtotals.fold<int>(0, (sum, value) => sum + value);
    if (subtotal <= 0) return List<int>.filled(lineSubtotals.length, 0);
    List<int> allocate(int amount) {
      final bases = <int>[];
      final remainders = <int>[];
      var allocated = 0;
      for (final value in lineSubtotals) {
        final numerator = amount * value;
        final base = numerator ~/ subtotal;
        bases.add(base);
        remainders.add(numerator % subtotal);
        allocated += base;
      }
      final order = List<int>.generate(lineSubtotals.length, (i) => i)
        ..sort((a, b) => remainders[b].compareTo(remainders[a]));
      for (var i = 0; i < amount - allocated; i++) {
        bases[order[i % order.length]]++;
      }
      return bases;
    }
    final discounts = allocate(discount);
    final fees = allocate(additionalCosts);
    return List<int>.generate(
      lineSubtotals.length,
      (i) => lineSubtotals[i] - discounts[i] + fees[i],
    );
  }

  Future<void> receivePurchaseItems({
    required int purchaseId,
    required Map<int, int> receivedQuantities,
    DateTime? receivedAt,
  }) async {
    AuthSession.instance.requireAdmin('Penerimaan pembelian hanya dapat dilakukan Admin.');
    if (receivedQuantities.isEmpty || receivedQuantities.values.any((quantity) => quantity <= 0)) {
      throw ArgumentError('Masukkan jumlah barang diterima yang lebih dari nol.');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final purchases = await txn.query(
        'purchases',
        columns: ['invoice_number', 'status', 'receiving_status'],
        where: 'id = ?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (purchases.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
      final purchase = purchases.first;
      if (purchase['status']?.toString() == 'cancelled') {
        throw StateError('Faktur yang dibatalkan tidak dapat menerima barang.');
      }
      final items = await txn.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
        orderBy: 'id ASC',
      );
      final byId = {for (final item in items) (item['id'] as num).toInt(): item};
      for (final entry in receivedQuantities.entries) {
        final item = byId[entry.key];
        if (item == null) throw ArgumentError('Rincian barang bukan bagian dari faktur ini.');
        final ordered = (item['quantity'] as num?)?.toInt() ?? 0;
        final received = (item['quantity_received'] as num?)?.toInt() ?? 0;
        final nextReceived = received + entry.value;
        if (nextReceived > ordered) {
          throw StateError('Jumlah diterima melebihi pesanan untuk ${item['product_name']}. Sisa: ${ordered - received}.');
        }
      }
      final timestamp = (receivedAt ?? DateTime.now()).toIso8601String();
      final settingRows = await txn.query('app_settings',
        columns: ['setting_value'], where: 'setting_key = ?',
        whereArgs: ['purchase_cost_method'], limit: 1);
      final configuredMethod = settingRows.isEmpty ? 'weighted_average' : settingRows.first['setting_value']?.toString();
      final costMethod = const ['weighted_average', 'last_cost', 'manual', 'per_batch'].contains(configuredMethod)
          ? configuredMethod! : 'weighted_average';
      for (final entry in receivedQuantities.entries) {
        final item = byId[entry.key]!;
        final productId = (item['product_id'] as num?)?.toInt();
        final variantId = (item['variant_id'] as num?)?.toInt();
        final quantity = entry.value;
        final nextReceived = ((item['quantity_received'] as num?)?.toInt() ?? 0) + quantity;
        final allocatedTotal = (item['allocated_landed_total'] as num?)?.toInt() ??
            ((item['allocated_unit_cost'] as num?)?.toInt() ??
                (item['unit_cost'] as num?)?.toInt() ?? 0) *
                ((item['quantity'] as num?)?.toInt() ?? 0);
        final previousReceived = (item['quantity_received'] as num?)?.toInt() ?? 0;
        final previousCost = (item['received_cost_total'] as num?)?.toInt() ??
            previousReceived * ((item['allocated_unit_cost'] as num?)?.toInt() ?? 0);
        final orderedQuantity = (item['quantity'] as num?)?.toInt() ?? 1;
        final cumulativeCost = (allocatedTotal * nextReceived + orderedQuantity ~/ 2) ~/ orderedQuantity;
        final receiptCost = cumulativeCost - previousCost;
        final unitCost = receiptCost ~/ quantity;
        final higherCostUnits = receiptCost % quantity;
        await txn.update('purchase_items', {
          'quantity_received': nextReceived,
          'received_cost_total': cumulativeCost,
        }, where: 'id = ?', whereArgs: [entry.key]);
        if (productId == null) continue;
        final products = await txn.query('products',
          columns: ['stock', 'track_stock', 'purchase_price', 'is_active'],
          where: 'id = ?', whereArgs: [productId], limit: 1);
        if (products.isEmpty || (products.first['is_active'] as num?)?.toInt() != 1) {
          throw StateError('Produk penerimaan tidak ditemukan atau tidak aktif.');
        }
        var owner = products.first;
        var table = 'products';
        var ownerId = productId;
        if (variantId != null) {
          final variants = await txn.query('product_variants',
            columns: ['stock', 'track_stock', 'purchase_price', 'is_active'],
            where: 'id = ? AND product_id = ? AND is_active = 1',
            whereArgs: [variantId, productId], limit: 1);
          if (variants.isEmpty) throw StateError('Varian penerimaan tidak ditemukan atau tidak aktif.');
          owner = variants.first;
          table = 'product_variants';
          ownerId = variantId;
        }
        if ((owner['track_stock'] as num?)?.toInt() != 1) continue;
        final before = (owner['stock'] as num?)?.toInt() ?? 0;
        final after = before + quantity;
        final oldCost = (owner['purchase_price'] as num?)?.toInt() ?? 0;
        final batchTotals = await txn.rawQuery('''
          SELECT COALESCE(SUM(quantity_remaining), 0) AS quantity,
            COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
          FROM inventory_cost_batches
          WHERE product_id = ? AND ${variantId == null ? 'variant_id IS NULL' : 'variant_id = ?'} AND quantity_remaining > 0
        ''', variantId == null ? [productId] : [productId, variantId]);
        final batchQuantity = (batchTotals.first['quantity'] as num?)?.toInt() ?? 0;
        final batchValue = (batchTotals.first['value'] as num?)?.toInt() ?? 0;
        final existingStockValue = batchQuantity == before ? batchValue : before * oldCost;
        int? nextPurchasePrice;
        if (costMethod == 'weighted_average') {
          nextPurchasePrice = after <= 0 ? unitCost : ((existingStockValue + receiptCost) / after).round();
        } else if (costMethod == 'last_cost') {
          nextPurchasePrice = (receiptCost + quantity ~/ 2) ~/ quantity;
        }
        await txn.update(table, {
          'stock': after,
          if (nextPurchasePrice != null) 'purchase_price': nextPurchasePrice,
          'updated_at': timestamp,
        }, where: 'id = ?', whereArgs: [ownerId]);
        // Pecah sisa pembulatan ke batch unit-cost +1 agar total biaya tepat.
        final baseUnits = quantity - higherCostUnits;
        if (baseUnits > 0) {
          await txn.insert('inventory_cost_batches', {
            'product_id': productId, 'variant_id': variantId, 'purchase_id': purchaseId,
            'purchase_item_id': entry.key, 'batch_code': purchase['invoice_number'],
            'quantity_received': baseUnits, 'quantity_remaining': baseUnits,
            'unit_cost': unitCost, 'received_at': timestamp,
            'notes': 'Penerimaan pembelian ${purchase['invoice_number']}',
          });
        }
        if (higherCostUnits > 0) {
          await txn.insert('inventory_cost_batches', {
            'product_id': productId, 'variant_id': variantId, 'purchase_id': purchaseId,
            'purchase_item_id': entry.key, 'batch_code': purchase['invoice_number'],
            'quantity_received': higherCostUnits, 'quantity_remaining': higherCostUnits,
            'unit_cost': unitCost + 1, 'received_at': timestamp,
            'notes': 'Penyesuaian pembulatan HPP ${purchase['invoice_number']}',
          });
        }
        await txn.insert('stock_movements', {
          'product_id': productId, 'variant_id': variantId, 'movement_type': 'in',
          'quantity': quantity, 'stock_before': before, 'stock_after': after,
          'reference_type': 'purchase', 'reference_id': purchaseId,
          'notes': 'Penerimaan pembelian ${purchase['invoice_number']}',
          'created_at': timestamp,
        });
      }
      final allItems = await txn.query('purchase_items',
        columns: ['quantity', 'quantity_received'], where: 'purchase_id = ?', whereArgs: [purchaseId]);
      final allReceived = allItems.every((item) =>
        (item['quantity_received'] as num?)?.toInt() == (item['quantity'] as num?)?.toInt());
      final anyReceived = allItems.any((item) => ((item['quantity_received'] as num?)?.toInt() ?? 0) > 0);
      await txn.update('purchases', {
        'receiving_status': allReceived ? 'received' : anyReceived ? 'partial' : 'pending',
      }, where: 'id = ?', whereArgs: [purchaseId]);
      await ActivityLogRepository.record(
        txn,
        action: 'purchase_items_received',
        description: 'Mencatat penerimaan barang faktur ${purchase['invoice_number']}.',
        entityType: 'purchase',
        entityId: purchaseId,
      );
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
        'payment_method': _nullable(paymentMethod) ?? 'cash',
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
        'inventory_cost_batches', where: 'purchase_id = ?', whereArgs: [purchaseId],
        orderBy: 'product_id ASC, variant_id ASC, id ASC');
      final stockMovements = await txn.query('stock_movements',
        columns: ['id'], where: "reference_type = 'purchase' AND reference_id = ?", whereArgs: [purchaseId]);
      if (stockMovements.length != batches.length) {
        throw StateError('Faktur ini berasal dari pencatatan stok versi lama atau batch tidak lengkap. Audit stok manual diperlukan sebelum pembatalan.');
      }
      final grouped = <String, Map<String, Object?>>{};
      for (final batch in batches) {
        final received = (batch['quantity_received'] as num?)?.toInt() ?? 0;
        final remaining = (batch['quantity_remaining'] as num?)?.toInt() ?? 0;
        if (received != remaining) {
          throw StateError('Stok dari faktur ini sudah terpakai atau disesuaikan. Koreksi stok terlebih dahulu; pembatalan otomatis dihentikan agar stok tidak minus.');
        }
        final productId = (batch['product_id'] as num?)?.toInt();
        final variantId = (batch['variant_id'] as num?)?.toInt();
        if (productId != null && received > 0) {
          final key = '$productId:${variantId ?? 'product'}';
          final group = grouped.putIfAbsent(key, () => {
            'product_id': productId, 'variant_id': variantId, 'quantity': 0,
          });
          group['quantity'] = (group['quantity'] as int) + received;
        }
      }
      for (final batch in batches) {
        await txn.update('inventory_cost_batches',
          {'quantity_remaining': 0, 'notes': 'Dibatalkan: $note'},
          where: 'id = ?', whereArgs: [batch['id']]);
      }
      final settingRows = await txn.query('app_settings',
        columns: ['setting_value'], where: 'setting_key = ?',
        whereArgs: ['purchase_cost_method'], limit: 1);
      final method = settingRows.isEmpty ? 'weighted_average' : settingRows.first['setting_value']?.toString();
      for (final entry in grouped.values) {
        final productId = entry['product_id'] as int;
        final variantId = entry['variant_id'] as int?;
        final quantity = entry['quantity'] as int;
        final table = variantId == null ? 'products' : 'product_variants';
        final ownerRows = await txn.query(table, columns: ['stock', 'track_stock'],
          where: 'id = ?', whereArgs: [variantId ?? productId], limit: 1);
        if (ownerRows.isEmpty) throw StateError('Produk/varian dari faktur tidak ditemukan; pembatalan dibatalkan.');
        final before = (ownerRows.first['stock'] as num?)?.toInt() ?? 0;
        if ((ownerRows.first['track_stock'] as num?)?.toInt() != 1) continue;
        if (before < quantity) throw StateError('Stok saat ini tidak cukup untuk membalik pembelian produk/varian ID ${variantId ?? productId}.');
        final after = before - quantity;
        await txn.update(table, {'stock': after, 'updated_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [variantId ?? productId]);
        await txn.insert('stock_movements', {
          'product_id': productId, 'variant_id': variantId, 'movement_type': 'out',
          'quantity': quantity, 'stock_before': before, 'stock_after': after,
          'reference_type': 'purchase_cancel', 'reference_id': purchaseId,
          'notes': 'Pembatalan faktur ${purchase['invoice_number']}: $note',
        });
        final filter = variantId == null ? 'variant_id IS NULL' : 'variant_id = ?';
        final args = variantId == null ? <Object?>[productId] : <Object?>[productId, variantId];
        if (method == 'weighted_average') {
          final totals = await txn.rawQuery('''
            SELECT COALESCE(SUM(quantity_remaining), 0) AS quantity,
              COALESCE(SUM(quantity_remaining * unit_cost), 0) AS value
            FROM inventory_cost_batches
            WHERE product_id = ? AND $filter AND quantity_remaining > 0
          ''', args);
          final qty = (totals.first['quantity'] as num?)?.toInt() ?? 0;
          final value = (totals.first['value'] as num?)?.toInt() ?? 0;
          if (qty > 0) await txn.update(table, {'purchase_price': (value / qty).round()},
            where: 'id = ?', whereArgs: [variantId ?? productId]);
        } else if (method == 'last_cost') {
          final previous = await txn.query('inventory_cost_batches', columns: ['unit_cost'],
            where: "product_id = ? AND $filter AND (purchase_id IS NULL OR (purchase_id != ? AND purchase_id IN (SELECT id FROM purchases WHERE status = 'active')))",
            whereArgs: [...args, purchaseId], orderBy: 'received_at DESC, id DESC', limit: 1);
          if (previous.isNotEmpty) await txn.update(table, {'purchase_price': previous.first['unit_cost']},
            where: 'id = ?', whereArgs: [variantId ?? productId]);
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

  /// Permanently removes a purchase test record only after the existing
  /// cancellation workflow has safely reversed its stock and cost batches.
  Future<int> deleteDummyPurchase({required int purchaseId}) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat menghapus transaksi.');
    final db = await _db;
    final rows = await db.query('purchases',
      where: 'id = ?', whereArgs: [purchaseId], limit: 1);
    if (rows.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');
    final purchase = rows.first;
    if ((purchase['paid'] as num? ?? 0) != 0 ||
        (purchase['return_credit'] as num? ?? 0) != 0) {
      throw StateError('Faktur memiliki pembayaran atau kredit retur dan tidak dapat dihapus sebagai dummy.');
    }

    final returns = await db.query('purchase_returns',
      columns: ['id'], where: 'purchase_id = ?', whereArgs: [purchaseId], limit: 1);
    if (returns.isNotEmpty) {
      throw StateError('Faktur memiliki riwayat retur. Data tersebut harus tetap dipertahankan.');
    }
    final snapshots = await db.query('receipt_snapshots',
      columns: ['id'], where: "source_type = 'purchase' AND source_id = ?",
      whereArgs: [purchaseId], limit: 1);
    if (snapshots.isNotEmpty) {
      throw StateError('Faktur memiliki arsip nota dan tidak dapat dihapus.');
    }

    // Reuse the audited stock reversal: it rejects used batches, payments,
    // incomplete stock movement records and any stock inconsistency.
    if (purchase['status']?.toString() != 'cancelled') {
      await cancelPurchase(
        purchaseId: purchaseId,
        reason: 'Pembersihan transaksi dummy oleh Admin',
      );
    }

    return db.transaction((txn) async {
      final current = await txn.query('purchases',
        where: 'id = ? AND status = ?', whereArgs: [purchaseId, 'cancelled'], limit: 1);
      if (current.isEmpty) throw StateError('Faktur belum berhasil dibatalkan; penghapusan dihentikan.');
      final payments = await txn.query('supplier_payments',
        columns: ['id'], where: 'purchase_id = ?', whereArgs: [purchaseId], limit: 1);
      if (payments.isNotEmpty) throw StateError('Riwayat pembayaran pemasok ditemukan; faktur tidak dihapus.');
      final cash = await txn.query('cash_transactions',
        columns: ['id'],
        where: "reference_id = ? AND reference_type IN ('purchase', 'purchase_payment')",
        whereArgs: [purchaseId], limit: 1);
      if (cash.isNotEmpty) throw StateError('Catatan kas terkait ditemukan; faktur tidak dihapus.');

      final batches = await txn.query('inventory_cost_batches',
        columns: ['id'], where: 'purchase_id = ?', whereArgs: [purchaseId]);
      for (final batch in batches) {
        final allocations = await txn.query('sale_batch_allocations',
          columns: ['id'], where: 'batch_id = ?', whereArgs: [batch['id']], limit: 1);
        if (allocations.isNotEmpty) {
          throw StateError('Batch pembelian sudah dipakai penjualan; faktur tidak dihapus.');
        }
      }
      await txn.delete('stock_movements',
        where: "reference_id = ? AND reference_type IN ('purchase', 'purchase_cancel')",
        whereArgs: [purchaseId]);
      await txn.delete('inventory_cost_batches',
        where: 'purchase_id = ?', whereArgs: [purchaseId]);
      final invoice = current.first['invoice_number']?.toString() ?? 'ID-$purchaseId';
      final count = await txn.delete('purchases', where: 'id = ?', whereArgs: [purchaseId]);
      await ActivityLogRepository.record(
        txn,
        action: 'purchase_dummy_deleted',
        description: 'Menghapus faktur pembelian dummy $invoice.',
        entityType: 'purchase',
        entityId: purchaseId,
      );
      return count;
    });
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
