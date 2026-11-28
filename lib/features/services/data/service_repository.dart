import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/activity_log_repository.dart';

class ServiceRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  void _requireSignedIn() {
    if (AuthSession.instance.user == null) {
      throw StateError('Silakan login untuk mengakses data servis.');
    }
  }

  static const List<String> serviceStatuses = [
    'waiting',
    'checking',
    'in_progress',
    'completed',
    'delivered',
    'cancelled',
  ];

  // Nomor nota servis baru mengikuti format singkat nota penjualan:
  // SRV-YYMMDD-0001. Nomor lama tetap tersimpan tanpa perubahan.
  Future<String> _generateOrderNumber(Transaction txn, DateTime date) async {
    final datePart =
        '${date.year.toString().substring(2)}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    final prefix = 'SRV-$datePart-';
    final rows = await txn.rawQuery(
      'SELECT COUNT(*) AS total FROM service_orders WHERE order_number LIKE ?',
      ['$prefix%'],
    );
    final sequence = ((rows.first['total'] as num?)?.toInt() ?? 0) + 1;
    return '$prefix${sequence.toString().padLeft(4, '0')}';
  }

  int _safeAmount(int value) => value < 0 ? 0 : value;

  // Membuat nota penerimaan servis.
  Future<int> createServiceOrder({
    int? customerId,
    int? bicycleId,
    String? guestCustomerName,
    String? guestCustomerPhone,
    String? guestBicycleBrand,
    String? guestBicycleModel,
    String? guestBicycleType,
    String? guestBicycleColor,
    String? guestBicycleSerialNumber,
    required String complaint,
    String? diagnosis,
    int estimatedCost = 0,
    int laborCost = 0,
    int partsCost = 0,
    int directPartsCost = 0,
    int otherDirectCost = 0,
    int discount = 0,
    int downPayment = 0,
    String downPaymentMethod = 'cash',
    String? mechanicName,
    int? assignedMechanicId,
    String? notes,
    String? beforePhotoPath,
    List<Map<String, Object?>> items = const [],
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat membuat nota servis.');
    final db = await _db;

    final cleanComplaint = complaint.trim();
    if (cleanComplaint.isEmpty) {
      throw ArgumentError('Keluhan pelanggan wajib diisi.');
    }

    final estimated = _safeAmount(estimatedCost);
    final labor = _safeAmount(laborCost);
    final parts = items.isEmpty
        ? _safeAmount(partsCost)
        : items.fold<int>(0, (sum, item) => sum +
            _safeAmount((item['unit_price'] as int? ?? 0)) *
            ((item['quantity'] as int? ?? 0)));
    final requestedDirectParts = _safeAmount(directPartsCost);
    final otherDirect = _safeAmount(otherDirectCost);
    final safeDiscount = _safeAmount(discount);
    final total = (labor + parts > 0 ? labor + parts : estimated) -
        safeDiscount;
    final safeTotal = total < 0 ? 0 : total;
    final paid = _safeAmount(downPayment);

    if (paid > safeTotal) {
      throw ArgumentError('DP tidak boleh melebihi total biaya servis.');
    }

    return db.transaction((txn) async {
      Map<String, Object?>? registeredCustomer;
      Map<String, Object?>? registeredBicycle;
      if (customerId != null) {
        final customers = await txn.query(
          'customers',
          columns: ['id', 'name', 'phone'],
          where: 'id = ?',
          whereArgs: [customerId],
          limit: 1,
        );
        if (customers.isEmpty) throw StateError('Pelanggan tidak ditemukan.');
        registeredCustomer = customers.first;
        if (bicycleId != null) {
          final bicycles = await txn.query(
            'bicycles',
            where: 'id = ? AND customer_id = ?',
            whereArgs: [bicycleId, customerId],
            limit: 1,
          );
          if (bicycles.isEmpty) {
            throw StateError('Sepeda tidak ditemukan atau bukan milik pelanggan ini.');
          }
          registeredBicycle = bicycles.first;
        }
      } else if (bicycleId == null) {
        if (_nullableText(guestCustomerName) == null ||
            _nullableText(guestBicycleBrand) == null) {
          throw ArgumentError('Nama pelanggan dan identitas objek servis wajib diisi untuk Pelanggan Umum.');
        }
      } else {
        throw ArgumentError('Data pelanggan dan sepeda tidak lengkap.');
      }

      final now = DateTime.now();
      final orderNumber = await _generateOrderNumber(txn, now);
      final queueDate = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final queueRows = await txn.rawQuery(
        'SELECT COALESCE(MAX(queue_number), 0) + 1 AS next_number FROM service_orders WHERE queue_date = ?',
        [queueDate],
      );
      final queueNumber = (queueRows.first['next_number'] as int?) ?? 1;
      var effectiveMechanicId = assignedMechanicId;
      var effectiveMechanicName = _nullableText(mechanicName);
      if (effectiveMechanicId == null) {
        final leastBusy = await txn.rawQuery("""
          SELECT u.id, u.display_name, COUNT(s.id) AS active_jobs
          FROM app_users u
          LEFT JOIN service_orders s
            ON s.assigned_mechanic_id = u.id
            AND s.service_status IN ('waiting', 'checking', 'in_progress')
          WHERE u.role = 'mechanic' AND u.is_active = 1
          GROUP BY u.id, u.display_name
          ORDER BY active_jobs ASC, u.id ASC
          LIMIT 1
        """);
        if (leastBusy.isNotEmpty) {
          effectiveMechanicId = leastBusy.first['id'] as int;
          effectiveMechanicName = leastBusy.first['display_name']?.toString();
        }
      }

      final serviceOrderId = await txn.insert('service_orders', {
        'order_number': orderNumber,
        'customer_id': customerId,
        'bicycle_id': bicycleId,
        'customer_name': registeredCustomer == null
            ? _nullableText(guestCustomerName)
            : registeredBicycle == null
                ? _nullableText(registeredCustomer['name']?.toString())
                : null,
        'customer_phone': registeredCustomer == null
            ? _nullableText(guestCustomerPhone)
            : registeredBicycle == null
                ? _nullableText(registeredCustomer['phone']?.toString())
                : null,
        'bicycle_brand': registeredBicycle == null
            ? _nullableText(guestBicycleBrand)
            : null,
        'bicycle_model': registeredBicycle == null
            ? _nullableText(guestBicycleModel)
            : null,
        'bicycle_type': registeredBicycle == null
            ? _nullableText(guestBicycleType)
            : null,
        'bicycle_color': registeredBicycle == null
            ? _nullableText(guestBicycleColor)
            : null,
        'bicycle_serial_number': registeredBicycle == null
            ? _nullableText(guestBicycleSerialNumber)
            : null,
        'complaint': cleanComplaint,
        'diagnosis': _nullableText(diagnosis),
        'service_status': 'waiting',
        'estimated_cost': estimated,
        'labor_cost': labor,
        'parts_cost': parts,
        'direct_parts_cost': requestedDirectParts,
        'other_direct_cost': otherDirect,
        'discount': safeDiscount,
        'total_cost': safeTotal,
        'down_payment': paid,
        'remaining_payment': safeTotal - paid,
        'mechanic_name': effectiveMechanicName,
        'assigned_mechanic_id': effectiveMechanicId,
        'queue_number': queueNumber,
        'queue_date': queueDate,
        'queue_priority': 0,
        'received_at': now.toIso8601String(),
        'notes': _nullableText(notes),
        'before_photo_path': _nullableText(beforePhotoPath),
      });

      // Biaya modal FIFO dihitung dari batch yang benar-benar dipakai.
      var allocatedDirectPartsCost = 0;
      // Simpan beberapa sparepart dalam nota yang sama. Barang berstok
      // divalidasi dan dikurangi bersama transaksi nota agar tidak terjadi
      // stok minus atau nota tersimpan tanpa mutasi stok yang lengkap.
      for (final item in items) {
        final productId = item['product_id'] as int?;
        final quantity = item['quantity'] as int? ?? 0;
        final unitPrice = _safeAmount(item['unit_price'] as int? ?? 0);
        if (productId == null || quantity <= 0) {
          throw ArgumentError('Data sparepart tidak valid.');
        }
        final productRows = await txn.query(
          'products',
          where: 'id = ? AND is_active = 1',
          whereArgs: [productId],
          limit: 1,
        );
        if (productRows.isEmpty) {
          throw StateError('Sparepart tidak ditemukan atau sudah tidak aktif.');
        }
        final product = productRows.first;
        final tracked = (product['track_stock'] as int? ?? 0) == 1;
        final stockBefore = product['stock'] as int? ?? 0;
        final name = product['name']?.toString() ?? 'Sparepart';
        final subtotal = quantity * unitPrice;
        final serviceItemId = await txn.insert('service_order_items', {
          'service_order_id': serviceOrderId,
          'product_id': productId,
          'item_name': name,
          'item_type': 'part',
          'quantity': quantity,
          'unit_price': unitPrice,
          'subtotal': subtotal,
          'is_active': 1,
        });
        if (tracked) {
          if (stockBefore < quantity) {
            throw StateError('Stok $name tidak cukup. Tersedia $stockBefore, dibutuhkan $quantity.');
          }
          final batches = await txn.query(
            'inventory_cost_batches',
            where: 'product_id = ? AND quantity_remaining > 0',
            whereArgs: [productId],
            orderBy: 'received_at ASC, id ASC',
          );
          final batchBalance = batches.fold<int>(
            0, (sum, batch) => sum + (batch['quantity_remaining'] as int? ?? 0));
          if (batchBalance < quantity) {
            throw StateError('Saldo batch stok $name tidak mencukupi. Periksa riwayat stok sebelum digunakan untuk servis.');
          }
          var remaining = quantity;
          for (final batch in batches) {
            if (remaining <= 0) break;
            final available = batch['quantity_remaining'] as int? ?? 0;
            if (available <= 0) continue;
            final take = available < remaining ? available : remaining;
            await txn.update('inventory_cost_batches', {
              'quantity_remaining': available - take,
            }, where: 'id = ?', whereArgs: [batch['id']]);
            final unitCost = (batch['unit_cost'] as num?)?.toInt() ?? 0;
            await txn.insert('service_part_allocations', {
              'service_order_item_id': serviceItemId,
              'batch_id': batch['id'],
              'quantity': take,
              'unit_cost': unitCost,
              'created_at': now.toIso8601String(),
            });
            allocatedDirectPartsCost += take * unitCost;
            remaining -= take;
          }
          final stockAfter = stockBefore - quantity;
          await txn.update('products', {
            'stock': stockAfter,
            'updated_at': now.toIso8601String(),
          }, where: 'id = ?', whereArgs: [productId]);
          await txn.insert('stock_movements', {
            'product_id': productId,
            'movement_type': 'out',
            'quantity': quantity,
            'stock_before': stockBefore,
            'stock_after': stockAfter,
            'reference_type': 'service_order',
            'reference_id': serviceOrderId,
            'notes': 'Sparepart digunakan untuk servis $orderNumber',
            'created_at': now.toIso8601String(),
          });
        }
      }

      final effectiveDirectPartsCost = requestedDirectParts > 0
          ? requestedDirectParts
          : allocatedDirectPartsCost;
      await txn.update(
        'service_orders',
        {'direct_parts_cost': effectiveDirectPartsCost},
        where: 'id = ?',
        whereArgs: [serviceOrderId],
      );

      await ActivityLogRepository.record(
        txn,
        action: 'service_created',
        description: 'Menerima servis baru dengan nomor $orderNumber.',
        entityType: 'service_order',
        entityId: serviceOrderId,
      );
      await txn.insert('service_status_history', {
        'service_order_id': serviceOrderId,
        'old_status': null,
        'new_status': 'waiting',
        'note': 'Servis diterima',
        'changed_at': now.toIso8601String(),
      });

      // Rekam biaya awal agar riwayat biaya lengkap sejak nota dibuat.
      await txn.insert('service_direct_cost_history', {
        'service_order_id': serviceOrderId,
        'old_direct_parts_cost': 0,
        'new_direct_parts_cost': effectiveDirectPartsCost,
        'old_other_direct_cost': 0,
        'new_other_direct_cost': otherDirect,
        'changed_at': now.toIso8601String(),
      });

      // DP dicatat sebagai kas masuk dalam transaksi database yang sama.
      // Jika pencatatan kas gagal, nota servis juga dibatalkan (rollback).
      if (paid > 0) {
        await txn.insert('cash_transactions', {
          'transaction_type': 'income',
          'category': 'Servis',
          'description': 'DP servis $orderNumber',
          'amount': paid,
          'reference_type': 'service_order',
          'reference_id': serviceOrderId,
          'payment_method': downPaymentMethod,
          'transaction_date': now.toIso8601String(),
        });
      }

      return serviceOrderId;
    });
  }

  // Daftar nota servis beserta nama pelanggan dan sepeda.
  Future<List<Map<String, Object?>>> getServiceOrders({
    String keyword = '',
    String? status,
    int? assignedMechanicId,
  }) async {
    _requireSignedIn();
    final db = await _db;
    final conditions = <String>[];
    final arguments = <Object?>[];

    if (keyword.trim().isNotEmpty) {
      final search = '%${keyword.trim()}%';
      conditions.add(
        '(s.order_number LIKE ? OR s.complaint LIKE ? '
        'OR COALESCE(s.customer_name, c.name, \'\') LIKE ? '
        'OR COALESCE(s.customer_phone, c.phone, \'\') LIKE ? '
        'OR COALESCE(s.bicycle_brand, b.brand, \'\') LIKE ? '
        'OR COALESCE(s.bicycle_model, b.model, \'\') LIKE ? '
        'OR COALESCE(s.bicycle_type, b.bicycle_type, \'\') LIKE ? '
        'OR COALESCE(s.bicycle_serial_number, b.serial_number, \'\') LIKE ?)',
      );
      arguments.addAll([
        search,
        search,
        search,
        search,
        search,
        search,
        search,
        search,
      ]);
    }

    final session = AuthSession.instance;
    final effectiveMechanicId = session.isMechanic ? session.userId : assignedMechanicId;
    if (session.isMechanic && effectiveMechanicId == null) {
      throw StateError('Sesi mekanik tidak valid. Silakan login kembali.');
    }
    if (effectiveMechanicId != null) {
      conditions.add('s.assigned_mechanic_id = ?');
      arguments.add(effectiveMechanicId);
    }

    if (status == 'active_queue') {
      conditions.add("s.service_status IN ('waiting', 'checking', 'in_progress')");
    } else if (status != null && status.trim().isNotEmpty) {
      if (!serviceStatuses.contains(status)) {
        throw ArgumentError('Status servis tidak valid.');
      }
      conditions.add('s.service_status = ?');
      arguments.add(status);
    }

    final whereClause =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    final rows = await db.rawQuery('''
      SELECT
        s.*,
        COALESCE(s.customer_name, c.name, 'Pelanggan Umum') AS customer_name,
        COALESCE(s.customer_phone, c.phone) AS customer_phone,
        COALESCE(s.bicycle_brand, b.brand) AS bicycle_brand,
        COALESCE(s.bicycle_model, b.model) AS bicycle_model,
        COALESCE(s.bicycle_type, b.bicycle_type) AS bicycle_type,
        COALESCE(s.bicycle_color, b.color) AS bicycle_color,
        COALESCE(s.bicycle_serial_number, b.serial_number) AS bicycle_serial_number
      FROM service_orders s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN bicycles b ON b.id = s.bicycle_id
      $whereClause
      ORDER BY COALESCE(s.queue_date, substr(s.received_at, 1, 10)) DESC,
        s.queue_priority DESC, COALESCE(s.queue_number, 2147483647) ASC, s.id DESC
    ''', arguments);
    return AuthSession.instance.isMechanic ? rows.map(_withoutFinancialFields).toList() : rows;
  }

  Map<String, Object?> _withoutFinancialFields(Map<String, Object?> row) {
    final safe = Map<String, Object?>.from(row);
    for (final key in const [
      'estimated_cost', 'labor_cost', 'parts_cost', 'direct_parts_cost',
      'other_direct_cost', 'discount', 'total_cost', 'down_payment',
      'remaining_payment',
    ]) {
      safe.remove(key);
    }
    return safe;
  }

  // Detail satu nota servis.
  Future<Map<String, Object?>?> getServiceOrderById(int id) async {
    _requireSignedIn();
    final db = await _db;
    final session = AuthSession.instance;
    if (session.isMechanic && session.userId == null) {
      throw StateError('Sesi mekanik tidak valid. Silakan login kembali.');
    }
    final result = await db.rawQuery('''
      SELECT
        s.*,
        COALESCE(s.customer_name, c.name, 'Pelanggan Umum') AS customer_name,
        COALESCE(s.customer_phone, c.phone) AS customer_phone,
        c.address AS customer_address,
        COALESCE(s.bicycle_brand, b.brand) AS bicycle_brand,
        COALESCE(s.bicycle_model, b.model) AS bicycle_model,
        COALESCE(s.bicycle_type, b.bicycle_type) AS bicycle_type,
        COALESCE(s.bicycle_color, b.color) AS bicycle_color,
        b.frame_size AS bicycle_frame_size,
        COALESCE(s.bicycle_serial_number, b.serial_number) AS bicycle_serial_number
      FROM service_orders s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN bicycles b ON b.id = s.bicycle_id
      WHERE s.id = ? AND (? IS NULL OR s.assigned_mechanic_id = ?)
      LIMIT 1
    ''', [id, session.isMechanic ? session.userId : null, session.isMechanic ? session.userId : null]);

    if (result.isEmpty) return null;
    final service = Map<String, Object?>.from(result.first);
    service['items'] = await db.query(
      'service_order_items',
      where: 'service_order_id = ? AND is_active = 1',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    if (session.isMechanic) {
      service['items'] = (service['items'] as List)
          .map((item) {
            final safeItem = Map<String, Object?>.from(item as Map);
            safeItem.remove('unit_price');
            safeItem.remove('subtotal');
            return safeItem;
          })
          .toList();
      return _withoutFinancialFields(service);
    }
    return service;
  }

  // Memperbarui hasil pemeriksaan dan rincian biaya secara atomik.
  // Pembacaan, validasi DP, dan perubahan tagihan berada dalam satu transaksi
  // agar tidak menimpa pembayaran yang masuk bersamaan.
  Future<int> updateServiceOrder({
    required int id,
    String? complaint,
    String? diagnosis,
    int? estimatedCost,
    int? laborCost,
    int? partsCost,
    int? discount,
    String? mechanicName,
    String? notes,
    bool customerApproved = false,
    String? customerApprovalNote,
    String? changeReason,
  }) async {
    AuthSession.instance.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat mengubah estimasi servis.',
    );
    final db = await _db;

    return db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Nota servis tidak ditemukan.');
      }
      final existing = rows.first;

      final labor = _safeAmount(
        laborCost ?? (existing['labor_cost'] as int? ?? 0),
      );
      final parts = _safeAmount(
        partsCost ?? (existing['parts_cost'] as int? ?? 0),
      );
      final estimated = _safeAmount(
        estimatedCost ?? (existing['estimated_cost'] as int? ?? 0),
      );
      final safeDiscount = _safeAmount(
        discount ?? (existing['discount'] as int? ?? 0),
      );
      final calculated = (labor + parts > 0 ? labor + parts : estimated) -
          safeDiscount;
      final total = calculated < 0 ? 0 : calculated;
      final paid = existing['down_payment'] as int? ?? 0;
      final oldEstimated = existing['estimated_cost'] as int? ?? 0;
      final oldLabor = existing['labor_cost'] as int? ?? 0;
      final oldParts = existing['parts_cost'] as int? ?? 0;
      final oldDiscount = existing['discount'] as int? ?? 0;
      final oldTotal = existing['total_cost'] as int? ?? 0;
      final financialChanged = estimated != oldEstimated ||
          labor != oldLabor || parts != oldParts || safeDiscount != oldDiscount;
      final status = existing['service_status']?.toString();
      if (financialChanged && !customerApproved) {
        throw StateError('Minta persetujuan pelanggan sebelum mengubah estimasi atau tagihan.');
      }
      if (financialChanged && (status == 'completed' || status == 'delivered' || status == 'cancelled')) {
        throw StateError('Estimasi servis yang sudah selesai, diambil, atau dibatalkan tidak dapat diubah agar laporan periode tetap akurat.');
      }
      if (paid > total) {
        throw ArgumentError(
          'Total baru lebih kecil dari seluruh pembayaran yang sudah diterima. Selesaikan pengembalian atau kredit pelanggan terlebih dahulu.',
        );
      }
      final now = DateTime.now().toIso8601String();
      if (financialChanged) {
        await txn.insert('service_estimate_history', {
          'service_order_id': id,
          'old_estimated_cost': oldEstimated,
          'new_estimated_cost': estimated,
          'old_labor_cost': oldLabor,
          'new_labor_cost': labor,
          'old_parts_cost': oldParts,
          'new_parts_cost': parts,
          'old_discount': oldDiscount,
          'new_discount': safeDiscount,
          'old_total_cost': oldTotal,
          'new_total_cost': total,
          'reason': _nullableText(changeReason),
          'customer_approved': 1,
          'customer_approval_note': _nullableText(customerApprovalNote),
          'changed_by_id': AuthSession.instance.userId,
          'changed_by_name': AuthSession.instance.displayName,
          'changed_at': now,
        });
        await ActivityLogRepository.record(
          txn,
          action: 'service_estimate_changed',
          description: 'Mengubah estimasi/tagihan servis #$id dari Rp$oldTotal menjadi Rp$total setelah persetujuan pelanggan.',
          entityType: 'service_order',
          entityId: id,
        );
      }

      return txn.update(
        'service_orders',
        {
          if (complaint != null) 'complaint': complaint.trim(),
          if (diagnosis != null) 'diagnosis': _nullableText(diagnosis),
          'estimated_cost': estimated,
          'labor_cost': labor,
          'parts_cost': parts,
          'discount': safeDiscount,
          'total_cost': total,
          'remaining_payment': total - paid,
          if (mechanicName != null)
            'mechanic_name': _nullableText(mechanicName),
          if (notes != null) 'notes': _nullableText(notes),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, Object?>>> getActiveSpareparts({String keyword = ''}) async {
    _requireSignedIn();
    final db = await _db;
    final term = keyword.trim();
    return db.query(
      'products',
      columns: ['id', 'name', 'sku', 'barcode', 'selling_price', 'stock', 'track_stock'],
      where: term.isEmpty
          ? 'is_active = 1'
          : 'is_active = 1 AND (name LIKE ? OR sku LIKE ? OR barcode LIKE ?)',
      whereArgs: term.isEmpty ? null : ['%$term%', '%$term%', '%$term%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  // Mekanik hanya mengusulkan perubahan sparepart; tidak dapat mengubah stok/tagihan.
  Future<int> proposeServicePartChange({
    required int serviceOrderId,
    required String requestType,
    int? serviceOrderItemId,
    int? productId,
    int quantity = 1,
    String? mechanicNote,
  }) async {
    final session = AuthSession.instance;
    final canProposeAdd = session.isMechanic || session.isCashierOrAdmin;
    if (session.userId == null || (requestType == 'add' && !canProposeAdd) ||
        (requestType == 'cancel' && !session.isMechanic)) {
      throw StateError('Akses tidak diizinkan untuk perubahan sparepart ini.');
    }
    if (requestType != 'add' && requestType != 'cancel') {
      throw ArgumentError('Jenis usulan tidak valid.');
    }
    if (requestType == 'add' && (productId == null || quantity <= 0)) {
      throw ArgumentError('Pilih sparepart dan jumlah yang valid.');
    }
    final db = await _db;
    return db.transaction((txn) async {
      final orders = await txn.query(
        'service_orders',
        columns: ['id', 'service_status', 'assigned_mechanic_id'],
        where: session.isMechanic ? 'id = ? AND assigned_mechanic_id = ?' : 'id = ?',
        whereArgs: session.isMechanic ? [serviceOrderId, session.userId] : [serviceOrderId],
        limit: 1,
      );
      if (orders.isEmpty) {
        throw StateError(session.isMechanic ? 'Servis bukan penugasan Anda.' : 'Data servis tidak ditemukan.');
      }
      final status = orders.first['service_status']?.toString();
      if (!const ['waiting', 'checking', 'in_progress'].contains(status)) {
        throw StateError('Usulan hanya dapat dibuat selama servis masih dikerjakan.');
      }

      String itemName;
      int? requestProductId;
      int requestQuantity;
      int requestUnitPrice = 0;
      if (requestType == 'add') {
        final products = await txn.query(
          'products',
          columns: ['id', 'name', 'is_active', 'selling_price', 'stock', 'track_stock'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (products.isEmpty || (products.first['is_active'] as int? ?? 0) != 1) {
          throw StateError('Sparepart tidak ditemukan atau tidak aktif.');
        }
        final product = products.first;
        final tracked = (product['track_stock'] as int? ?? 0) == 1;
        final availableStock = (product['stock'] as int? ?? 0);
        if (tracked && availableStock <= 0) {
          throw StateError('Stok sparepart habis. Produk tidak dapat dipilih untuk servis.');
        }
        if (tracked && quantity > availableStock) {
          throw StateError('Stok tidak mencukupi. Tersedia $availableStock, diminta $quantity.');
        }
        itemName = product['name']?.toString() ?? 'Sparepart';
        requestProductId = productId;
        requestQuantity = quantity;
        requestUnitPrice = (product['selling_price'] as num?)?.toInt() ?? 0;
      } else {
        if (serviceOrderItemId == null) {
          throw ArgumentError('Pilih sparepart yang akan dibatalkan.');
        }
        final items = await txn.query(
          'service_order_items',
          where: 'id = ? AND service_order_id = ? AND item_type = ? AND is_active = 1',
          whereArgs: [serviceOrderItemId, serviceOrderId, 'part'],
          limit: 1,
        );
        if (items.isEmpty) throw StateError('Sparepart aktif tidak ditemukan pada nota ini.');
        itemName = items.first['item_name']?.toString() ?? 'Sparepart';
        requestProductId = items.first['product_id'] as int?;
        requestQuantity = items.first['quantity'] as int? ?? 1;
        requestUnitPrice = items.first['unit_price'] as int? ?? 0;
      }

      return txn.insert('service_part_change_requests', {
        'service_order_id': serviceOrderId,
        'request_type': requestType,
        'service_order_item_id': serviceOrderItemId,
        'product_id': requestProductId,
        'item_name': itemName,
        'quantity': requestQuantity,
        'unit_price': requestUnitPrice,
        'mechanic_note': _nullableText(mechanicNote),
        'status': 'pending',
        'proposed_by_id': session.userId,
        'proposed_by_name': session.displayName,
        'proposed_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<int> countPendingServicePartChangeRequests() async {
    AuthSession.instance.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat melihat pengajuan sparepart.',
    );
    final db = await _db;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM service_part_change_requests WHERE status = 'pending' AND request_type = 'add'",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, Object?>>> getServicePartChangeRequests(int serviceOrderId) async {
    AuthSession.instance.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat meninjau usulan sparepart.',
    );
    final db = await _db;
    return db.query(
      'service_part_change_requests',
      where: 'service_order_id = ?',
      whereArgs: [serviceOrderId],
      orderBy: 'proposed_at DESC, id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getServiceEstimateHistory(int serviceOrderId) async {
    AuthSession.instance.requireCashierOrAdmin(
      'Riwayat estimasi hanya dapat diakses Admin dan Kasir.',
    );
    final db = await _db;
    return db.query(
      'service_estimate_history',
      where: 'service_order_id = ?',
      whereArgs: [serviceOrderId],
      orderBy: 'changed_at DESC, id DESC',
    );
  }

  // Admin/Kasir wajib mengonfirmasi izin pelanggan sebelum usulan diterapkan.
  // Perubahan stok, rincian item, total tagihan, dan audit tersimpan atomik.
  Future<int> reviewServicePartChange({
    required int requestId,
    required bool approve,
    bool customerApproved = false,
    String? customerApprovalNote,
  }) async {
    final session = AuthSession.instance;
    session.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat menyetujui perubahan sparepart.',
    );
    if (approve && !customerApproved) {
      throw StateError('Minta dan catat persetujuan pelanggan sebelum menerapkan perubahan.');
    }
    final db = await _db;
    return db.transaction((txn) async {
      final requests = await txn.query(
        'service_part_change_requests',
        where: "id = ? AND status = 'pending'",
        whereArgs: [requestId],
        limit: 1,
      );
      if (requests.isEmpty) throw StateError('Usulan tidak ditemukan atau sudah ditinjau.');
      final request = requests.first;
      final serviceId = request['service_order_id'] as int;
      final orders = await txn.query(
        'service_orders',
        where: 'id = ?',
        whereArgs: [serviceId],
        limit: 1,
      );
      if (orders.isEmpty) throw StateError('Nota servis tidak ditemukan.');
      final order = orders.first;
      final serviceStatus = order['service_status']?.toString();
      if (approve && !const ['waiting', 'checking', 'in_progress'].contains(serviceStatus)) {
        throw StateError('Perubahan sparepart hanya dapat diterapkan saat servis masih dikerjakan.');
      }

      final now = DateTime.now().toIso8601String();
      var fifoCostDelta = 0;
      final oldEstimated = order['estimated_cost'] as int? ?? 0;
      final oldLabor = order['labor_cost'] as int? ?? 0;
      final oldParts = order['parts_cost'] as int? ?? 0;
      final oldDiscount = order['discount'] as int? ?? 0;
      final oldTotal = order['total_cost'] as int? ?? 0;

      if (approve) {
        final requestType = request['request_type']?.toString();
        if (requestType == 'add') {
          final productId = request['product_id'] as int?;
          final quantity = request['quantity'] as int? ?? 0;
          // Gunakan harga katalog yang disimpan saat pengajuan dibuat.
          // Admin/Kasir tidak perlu mengetik atau mengirim harga manual.
          final unitPrice = (request['unit_price'] as num?)?.toInt() ?? 0;
          if (productId == null || quantity <= 0) {
            throw StateError('Data sparepart usulan tidak valid.');
          }
          final products = await txn.query(
            'products',
            where: 'id = ? AND is_active = 1',
            whereArgs: [productId],
            limit: 1,
          );
          if (products.isEmpty) throw StateError('Sparepart tidak ditemukan atau tidak aktif.');
          final product = products.first;
          final tracked = (product['track_stock'] as int? ?? 0) == 1;
          final stockBefore = product['stock'] as int? ?? 0;
          final itemName = product['name']?.toString() ?? request['item_name']?.toString() ?? 'Sparepart';
          if (tracked && stockBefore < quantity) {
            throw StateError('Stok $itemName tidak cukup. Tersedia $stockBefore, dibutuhkan $quantity.');
          }
          final itemId = await txn.insert('service_order_items', {
            'service_order_id': serviceId,
            'product_id': productId,
            'item_name': itemName,
            'item_type': 'part',
            'quantity': quantity,
            'unit_price': unitPrice,
            'subtotal': quantity * unitPrice,
            'is_active': 1,
          });
          if (tracked) {
            final batches = await txn.query(
              'inventory_cost_batches',
              where: 'product_id = ? AND quantity_remaining > 0',
              whereArgs: [productId],
              orderBy: 'received_at ASC, id ASC',
            );
            final batchBalance = batches.fold<int>(
              0, (sum, batch) => sum + (batch['quantity_remaining'] as int? ?? 0));
            if (batchBalance < quantity) {
              throw StateError('Saldo batch FIFO $itemName tidak mencukupi. Periksa riwayat stok.');
            }
            var remaining = quantity;
            for (final batch in batches) {
              if (remaining <= 0) break;
              final available = batch['quantity_remaining'] as int? ?? 0;
              if (available <= 0) continue;
              final take = available < remaining ? available : remaining;
              await txn.update(
                'inventory_cost_batches',
                {'quantity_remaining': available - take},
                where: 'id = ?',
                whereArgs: [batch['id']],
              );
              final unitCost = (batch['unit_cost'] as num?)?.toInt() ?? 0;
              await txn.insert('service_part_allocations', {
                'service_order_item_id': itemId,
                'batch_id': batch['id'],
                'quantity': take,
                'unit_cost': unitCost,
                'created_at': now,
              });
              fifoCostDelta += take * unitCost;
              remaining -= take;
            }
            final stockAfter = stockBefore - quantity;
            await txn.update(
              'products',
              {'stock': stockAfter, 'updated_at': now},
              where: 'id = ?',
              whereArgs: [productId],
            );
            await txn.insert('stock_movements', {
              'product_id': productId,
              'movement_type': 'out',
              'quantity': quantity,
              'stock_before': stockBefore,
              'stock_after': stockAfter,
              'reference_type': 'service_order_part_change',
              'reference_id': serviceId,
              'notes': 'Penambahan sparepart dari usulan servis #$serviceId',
              'created_at': now,
            });
          }
        } else if (requestType == 'cancel') {
          final itemId = request['service_order_item_id'] as int?;
          if (itemId == null) throw StateError('Item sparepart yang akan dibatalkan tidak ditemukan.');
          final itemRows = await txn.query(
            'service_order_items',
            where: 'id = ? AND service_order_id = ? AND item_type = ? AND is_active = 1',
            whereArgs: [itemId, serviceId, 'part'],
            limit: 1,
          );
          if (itemRows.isEmpty) throw StateError('Sparepart sudah tidak aktif atau tidak ditemukan.');
          final item = itemRows.first;
          final productId = item['product_id'] as int?;
          if (productId != null) {
            final products = await txn.query(
              'products',
              where: 'id = ?',
              whereArgs: [productId],
              limit: 1,
            );
            if (products.isNotEmpty && (products.first['track_stock'] as int? ?? 0) == 1) {
              final allocations = await txn.query(
                'service_part_allocations',
                where: 'service_order_item_id = ?',
                whereArgs: [itemId],
                orderBy: 'id ASC',
              );
              final allocated = allocations.fold<int>(
                0, (sum, row) => sum + (row['quantity'] as int? ?? 0));
              final quantity = item['quantity'] as int? ?? 0;
              if (allocated != quantity) {
                throw StateError('Alokasi FIFO sparepart lama belum tercatat lengkap. Stok tidak diubah agar saldo tidak keliru; lakukan rekonsiliasi stok terlebih dahulu.');
              }
              for (final allocation in allocations) {
                fifoCostDelta -= (allocation['quantity'] as int? ?? 0) *
                    (allocation['unit_cost'] as int? ?? 0);
                final batchId = allocation['batch_id'] as int;
                final batchRows = await txn.query(
                  'inventory_cost_batches',
                  where: 'id = ?',
                  whereArgs: [batchId],
                  limit: 1,
                );
                if (batchRows.isEmpty) throw StateError('Batch FIFO asal tidak ditemukan. Stok tidak diubah.');
                final batch = batchRows.first;
                await txn.update(
                  'inventory_cost_batches',
                  {'quantity_remaining': (batch['quantity_remaining'] as int? ?? 0) + (allocation['quantity'] as int? ?? 0)},
                  where: 'id = ?',
                  whereArgs: [batchId],
                );
              }
              final product = products.first;
              final stockBefore = product['stock'] as int? ?? 0;
              await txn.update(
                'products',
                {'stock': stockBefore + quantity, 'updated_at': now},
                where: 'id = ?',
                whereArgs: [productId],
              );
              await txn.insert('stock_movements', {
                'product_id': productId,
                'movement_type': 'in',
                'quantity': quantity,
                'stock_before': stockBefore,
                'stock_after': stockBefore + quantity,
                'reference_type': 'service_order_part_change',
                'reference_id': serviceId,
                'notes': 'Pembatalan sparepart dari usulan servis #$serviceId',
                'created_at': now,
              });
            }
          }
          await txn.update(
            'service_order_items',
            {'is_active': 0},
            where: 'id = ?',
            whereArgs: [itemId],
          );
        } else {
          throw StateError('Jenis usulan tidak dikenali.');
        }
      }
      if (approve && fifoCostDelta != 0) {
        final oldDirectParts = (order['direct_parts_cost'] as num?)?.toInt() ?? 0;
        final oldOtherDirect = (order['other_direct_cost'] as num?)?.toInt() ?? 0;
        final newDirectParts = (oldDirectParts + fifoCostDelta).clamp(0, 1 << 62).toInt();
        await txn.insert('service_direct_cost_history', {
          'service_order_id': serviceId,
          'old_direct_parts_cost': oldDirectParts,
          'new_direct_parts_cost': newDirectParts,
          'old_other_direct_cost': oldOtherDirect,
          'new_other_direct_cost': oldOtherDirect,
          'changed_at': now,
        });
        await txn.update('service_orders', {
          'direct_parts_cost': newDirectParts,
        }, where: 'id = ?', whereArgs: [serviceId]);
      }

      if (approve) {
        final itemSubtotal = (request['quantity'] as int? ?? 0) *
            (request['unit_price'] as int? ?? 0);
        final effectiveSubtotal = itemSubtotal;
        final newParts = request['request_type'] == 'add'
            ? oldParts + effectiveSubtotal
            : (oldParts - itemSubtotal < 0 ? 0 : oldParts - itemSubtotal);
        final calculated = (oldLabor + newParts > 0 ? oldLabor + newParts : oldEstimated) - oldDiscount;
        final newTotal = calculated < 0 ? 0 : calculated;
        final paid = order['down_payment'] as int? ?? 0;
        if (newTotal < paid) {
          throw StateError('Total baru lebih kecil dari seluruh pembayaran yang sudah diterima. Proses pengembalian/ kredit pelanggan harus diselesaikan terlebih dahulu; perubahan belum diterapkan.');
        }
        await txn.update(
          'service_orders',
          {'parts_cost': newParts, 'total_cost': newTotal, 'remaining_payment': newTotal - paid},
          where: 'id = ?',
          whereArgs: [serviceId],
        );
        await txn.insert('service_estimate_history', {
        'service_order_id': serviceId,
        'old_estimated_cost': oldEstimated,
        'new_estimated_cost': oldEstimated,
        'old_labor_cost': oldLabor,
        'new_labor_cost': oldLabor,
        'old_parts_cost': oldParts,
        'new_parts_cost': newParts,
        'old_discount': oldDiscount,
        'new_discount': oldDiscount,
        'old_total_cost': oldTotal,
        'new_total_cost': newTotal,
        'reason': request['mechanic_note']?.toString() ?? 'Perubahan sparepart servis',
        'customer_approved': approve ? 1 : 0,
        'customer_approval_note': approve ? _nullableText(customerApprovalNote) : null,
        'changed_by_id': session.userId,
        'changed_by_name': session.displayName,
        'changed_at': now,
        });
      }
      await txn.update(
        'service_part_change_requests',
        {
          'status': approve ? 'approved' : 'rejected',
          'reviewed_by_id': session.userId,
          'reviewed_by_name': session.displayName,
          'customer_approved': approve && customerApproved ? 1 : 0,
          'customer_approval_note': approve ? _nullableText(customerApprovalNote) : null,
          'reviewed_at': now,
        },
        where: 'id = ?',
        whereArgs: [requestId],
      );
      await ActivityLogRepository.record(
        txn,
        action: approve ? 'service_part_change_approved' : 'service_part_change_rejected',
        description: '${approve ? 'Menyetujui' : 'Menolak'} usulan sparepart "${request['item_name']}" untuk servis #$serviceId.',
        entityType: 'service_order',
        entityId: serviceId,
      );
      return 1;
    });
  }

  // Riwayat audit perubahan modal, tidak mengubah tagihan dan stok.
  Future<List<Map<String, Object?>>> getServiceDirectCostHistory(int id) async {
    AuthSession.instance.requireAdmin('Riwayat biaya modal hanya dapat diakses Admin.');
    final db = await _db;
    return db.query(
      'service_direct_cost_history',
      where: 'service_order_id = ?',
      whereArgs: [id],
      orderBy: 'changed_at DESC, id DESC',
    );
  }

  Future<int> updateServiceDirectCosts({
    required int id,
    required int directPartsCost,
    required int otherDirectCost,
  }) async {
    if (!AuthSession.instance.isAdmin) {
      throw StateError('Hanya Admin yang dapat mengubah biaya modal servis.');
    }
    if (directPartsCost < 0 || otherDirectCost < 0) {
      throw ArgumentError('Biaya langsung tidak boleh negatif.');
    }
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        columns: ['id', 'direct_parts_cost', 'other_direct_cost'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Nota servis tidak ditemukan.');
      }
      final oldParts = rows.first['direct_parts_cost'] as int? ?? 0;
      final oldOther = rows.first['other_direct_cost'] as int? ?? 0;
      if (oldParts == directPartsCost && oldOther == otherDirectCost) {
        return 0;
      }

      final now = DateTime.now().toIso8601String();
      await txn.insert('service_direct_cost_history', {
        'service_order_id': id,
        'old_direct_parts_cost': oldParts,
        'new_direct_parts_cost': directPartsCost,
        'old_other_direct_cost': oldOther,
        'new_other_direct_cost': otherDirectCost,
        'changed_at': now,
      });
      await ActivityLogRepository.record(
        txn,
        action: 'service_direct_cost_changed',
        description: 'Mengubah biaya langsung servis #$id.',
        entityType: 'service_order',
        entityId: id,
      );
      return txn.update(
        'service_orders',
        {
          'direct_parts_cost': directPartsCost,
          'other_direct_cost': otherDirectCost,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // Deposit otomatis dipakai saat pekerjaan selesai, bukan saat sepeda diambil.
  static const Set<String> walletAutoPaymentStatuses = {'completed'};

  // Perubahan status harus mengikuti alur kerja dan selalu tercatat.
  static const Map<String, List<String>> allowedStatusTransitions = {
    'waiting': ['checking', 'cancelled'],
    'checking': ['waiting', 'in_progress', 'cancelled'],
    'in_progress': ['checking', 'completed', 'cancelled'],
    'completed': ['in_progress', 'delivered'],
    'delivered': [],
    'cancelled': [],
  };

  Future<int> updateServiceStatus({
    required int id,
    required String status,
    String? note,
    int? actingMechanicId,
  }) async {
    _requireSignedIn();
    if (!serviceStatuses.contains(status)) {
      throw ArgumentError('Status servis tidak valid.');
    }
    // Pembatalan dapat memicu pengembalian uang tunai dan saldo pelanggan.
    // Karena itu mekanik tidak boleh membatalkan nota melalui pemanggilan
    // repository langsung, meskipun UI saat ini menyembunyikan opsi tersebut.
    if (status == 'cancelled') {
      AuthSession.instance.requireCashierOrAdmin(
        'Hanya Admin dan Kasir yang dapat membatalkan servis.',
      );
    }
    final session = AuthSession.instance;
    if (session.isMechanic && (actingMechanicId == null || actingMechanicId != session.userId)) {
      throw StateError('Akses ditolak: akun mekanik hanya boleh mengubah tugasnya sendiri.');
    }

    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        columns: ['service_status', 'remaining_payment', 'down_payment', 'order_number', 'assigned_mechanic_id', 'customer_id'],
        where: 'id = ? AND (? IS NULL OR assigned_mechanic_id = ?)',
        whereArgs: [id, actingMechanicId, actingMechanicId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Nota servis tidak ditemukan atau bukan penugasan Anda.');

      final current = rows.first['service_status']?.toString() ?? 'waiting';
      if (current == status) return 0;
      final allowed = allowedStatusTransitions[current] ?? const <String>[];
      if (!allowed.contains(status)) {
        throw StateError(
          'Perubahan status dari "$current" ke "$status" tidak diizinkan.',
        );
      }

      // Pengambilan sepeda tidak mensyaratkan tagihan lunas.
      // Status pekerjaan/pengambilan terpisah dari status pembayaran.
      final now = DateTime.now().toIso8601String();
      final data = <String, Object?>{'service_status': status};
      if (status == 'completed') data['completed_at'] = now;

      final updated = await txn.update(
        'service_orders',
        data,
        where: 'id = ? AND service_status = ?',
        whereArgs: [id, current],
      );
      if (updated != 1) {
        throw StateError('Status servis berubah. Muat ulang lalu coba lagi.');
      }

      // Saat Admin/Kasir menyelesaikan servis, gunakan deposit pelanggan
      // otomatis untuk mengurangi sisa tagihan. Akun mekanik tidak menjalankan
      // mutasi keuangan ketika hanya memperbarui status pekerjaan.
      // Deposit otomatis dipakai saat pekerjaan dinyatakan selesai, bukan saat sepeda hanya diambil.
      if (!session.isMechanic && walletAutoPaymentStatuses.contains(status)) {
        final customerId = rows.first['customer_id'] as int?;
        final remaining = (rows.first['remaining_payment'] as num?)?.toInt() ?? 0;
        if (customerId != null && remaining > 0) {
          final walletRows = await txn.rawQuery(
            'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
            [customerId],
          );
          final balance = walletRows.isEmpty ? 0 : (walletRows.first['balance_after'] as num?)?.toInt() ?? 0;
          final applied = balance < remaining ? balance : remaining;
          if (applied > 0) {
            final paid = (rows.first['down_payment'] as num?)?.toInt() ?? 0;
            await txn.update('service_orders', {
              'down_payment': paid + applied,
              'remaining_payment': remaining - applied,
            }, where: 'id = ?', whereArgs: [id]);
            await txn.insert('customer_wallet_ledger', {
              'customer_id': customerId,
              'entry_type': 'service_payment',
              'amount': applied,
              'balance_after': balance - applied,
              'description': 'Pembayaran otomatis dari saldo deposit servis ${rows.first['order_number'] ?? id}',
              'reference_type': 'service_order',
              'reference_id': id,
              'payment_method': 'customer_wallet',
              'created_by_id': AuthSession.instance.userId,
              'created_by_name': AuthSession.instance.displayName,
              'created_at': now,
            });
            await ActivityLogRepository.record(
              txn,
              action: 'service_wallet_auto_payment',
              description: 'Menggunakan saldo pelanggan Rp$applied untuk pelunasan servis ${rows.first['order_number'] ?? id}.',
              entityType: 'service_order',
              entityId: id,
            );
          }
        }
      }

      if (status == 'cancelled') {
        final paidRows = await txn.rawQuery(
          '''
          SELECT LOWER(COALESCE(payment_method, 'cash')) AS payment_method,
            SUM(amount) AS total_paid
          FROM cash_transactions
          WHERE reference_type = 'service_order'
            AND reference_id = ?
            AND transaction_type = 'income'
          GROUP BY LOWER(COALESCE(payment_method, 'cash'))
          ''',
          [id],
        );
        final walletPayments = await txn.rawQuery('''
          SELECT COALESCE(SUM(amount), 0) AS total
          FROM customer_wallet_ledger
          WHERE reference_type = 'service_order' AND reference_id = ? AND entry_type = 'service_payment'
        ''', [id]);
        final walletRefund = (walletPayments.first['total'] as num?)?.toInt() ?? 0;
        final customerId = rows.first['customer_id'] as int?;
        if (walletRefund > 0 && customerId == null) {
          throw StateError(
            'Pengembalian saldo servis tidak dapat diproses karena relasi pelanggan hilang.',
          );
        }
        if (walletRefund > 0 && customerId != null) {
          final balanceRows = await txn.rawQuery(
            'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
            [customerId],
          );
          final balance = balanceRows.isEmpty ? 0 : (balanceRows.first['balance_after'] as num?)?.toInt() ?? 0;
          await txn.insert('customer_wallet_ledger', {
            'customer_id': customerId, 'entry_type': 'refund', 'amount': walletRefund,
            'balance_after': balance + walletRefund,
            'description': 'Pengembalian saldo dari pembatalan servis ${rows.first['order_number'] ?? id}',
            'reference_type': 'service_order_cancellation', 'reference_id': id,
            'payment_method': 'customer_wallet',
            'created_by_id': AuthSession.instance.userId,
            'created_by_name': AuthSession.instance.displayName,
            'created_at': now,
          });
        }
        for (final payment in paidRows) {
          final refundAmount = (payment['total_paid'] as num?)?.toInt() ?? 0;
          if (refundAmount <= 0) continue;
          await txn.insert('cash_transactions', {
            'transaction_type': 'expense',
            'category': 'Pembatalan Servis',
            'description':
                'Pengembalian pembayaran servis ${rows.first['order_number'] ?? id}',
            'amount': refundAmount,
            'reference_type': 'service_order_cancellation',
            'reference_id': id,
            'payment_method': payment['payment_method']?.toString() ?? 'cash',
            'transaction_date': now,
          });
        }
      }

      await txn.insert('service_status_history', {
        'service_order_id': id,
        'old_status': current,
        'new_status': status,
        'note': _nullableText(note),
        'changed_at': now,
      });
      await ActivityLogRepository.record(
        txn,
        action: 'service_status_changed',
        description: 'Mengubah status servis ${rows.first['order_number'] ?? id} dari $current menjadi $status.',
        entityType: 'service_order',
        entityId: id,
      );
      return updated;
    });
  }

  /// Daftar servis yang masih memiliki piutang, termasuk sepeda yang sudah diambil.
  Future<List<Map<String, Object?>>> getOutstandingServiceOrders({
    String keyword = '',
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Daftar piutang servis hanya dapat diakses Admin dan Kasir.');
    final db = await _db;
    final term = keyword.trim();
    return db.rawQuery('''
      SELECT
        s.*,
        COALESCE(s.customer_name, c.name, 'Pelanggan Umum') AS customer_name,
        COALESCE(s.customer_phone, c.phone) AS customer_phone,
        COALESCE(s.bicycle_brand, b.brand) AS bicycle_brand,
        COALESCE(s.bicycle_model, b.model) AS bicycle_model
      FROM service_orders s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN bicycles b ON b.id = s.bicycle_id
      WHERE s.remaining_payment > 0
        AND s.service_status != 'cancelled'
        AND (
          ? = ''
          OR s.order_number LIKE ?
          OR COALESCE(s.customer_name, c.name, '') LIKE ?
          OR COALESCE(s.customer_phone, c.phone, '') LIKE ?
        )
      ORDER BY s.received_at ASC, s.id ASC
    ''', [term, '%$term%', '%$term%', '%$term%']);
  }

  Future<List<Map<String, Object?>>> getServiceStatusHistory(int id) async {
    _requireSignedIn();
    final db = await _db;
    final session = AuthSession.instance;
    if (session.isMechanic) {
      final assigned = await db.query('service_orders', columns: ['id'], where: 'id = ? AND assigned_mechanic_id = ?', whereArgs: [id, session.userId], limit: 1);
      if (assigned.isEmpty) throw StateError('Akses ditolak: servis bukan penugasan Anda.');
    }
    return db.query(
      'service_status_history',
      where: 'service_order_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
  }

  // Menyimpan atau mengganti foto sebelum/sesudah servis.
  Future<int> updateServicePhotos({
    required int id,
    String? beforePhotoPath,
    String? afterPhotoPath,
  }) async {
    _requireSignedIn();
    final session = AuthSession.instance;
    if (session.isMechanic) {
      final dbCheck = await _db;
      final assigned = await dbCheck.query('service_orders', columns: ['id'], where: 'id = ? AND assigned_mechanic_id = ?', whereArgs: [id, session.userId], limit: 1);
      if (assigned.isEmpty) throw StateError('Akses ditolak: servis bukan penugasan Anda.');
    }
    final db = await _db;
    final values = <String, Object?>{};

    if (beforePhotoPath != null) {
      values['before_photo_path'] = _nullableText(beforePhotoPath);
    }

    if (afterPhotoPath != null) {
      values['after_photo_path'] = _nullableText(afterPhotoPath);
    }

    if (values.isEmpty) return 0;

    return db.update(
      'service_orders',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Mencatat pembayaran tambahan dan menghitung sisa tagihan.
  Future<int> addWalletPayment({required int id, required int amount}) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses pembayaran.');
    if (amount <= 0) throw ArgumentError('Jumlah pembayaran harus lebih dari nol.');
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('service_orders', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) throw StateError('Nota servis tidak ditemukan.');
      final order = rows.first;
      if (order['service_status'] == 'cancelled') throw StateError('Servis yang dibatalkan tidak dapat menerima pembayaran.');
      final customerId = order['customer_id'] as int?;
      if (customerId == null) throw StateError('Saldo pelanggan hanya dapat digunakan oleh pelanggan terdaftar.');
      final total = (order['total_cost'] as num?)?.toInt() ?? 0;
      final paid = (order['down_payment'] as num?)?.toInt() ?? 0;
      final remaining = total - paid;
      if (amount > remaining) throw ArgumentError('Pembayaran melebihi sisa tagihan.');
      final walletRows = await txn.rawQuery(
        'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
        [customerId],
      );
      final balance = walletRows.isEmpty ? 0 : (walletRows.first['balance_after'] as num?)?.toInt() ?? 0;
      if (amount > balance) throw StateError('Saldo pelanggan tidak mencukupi. Saldo tersedia Rp$balance.');
      final nextBalance = balance - amount;
      final now = DateTime.now().toIso8601String();
      await txn.update('service_orders', {
        'down_payment': paid + amount,
        'remaining_payment': remaining - amount,
      }, where: 'id = ?', whereArgs: [id]);
      await txn.insert('customer_wallet_ledger', {
        'customer_id': customerId, 'entry_type': 'service_payment', 'amount': amount,
        'balance_after': nextBalance, 'description': 'Pembayaran servis ${order['order_number'] ?? id}',
        'reference_type': 'service_order', 'reference_id': id, 'payment_method': 'customer_wallet',
        'created_by_id': AuthSession.instance.userId, 'created_by_name': AuthSession.instance.displayName,
        'created_at': now,
      });
      await ActivityLogRepository.record(txn, action: 'service_wallet_payment',
        description: 'Membayar servis ${order['order_number'] ?? id} sebesar Rp$amount dari saldo pelanggan.',
        entityType: 'service_order', entityId: id);
      return 1;
    });
  }

  Future<int> addPayment({
    required int id,
    required int amount,
    int tipAmount = 0,
    int walletDepositAmount = 0,
    String? tipRecipientName,
    String paymentMethod = 'cash',
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat memproses pembayaran servis.');
    if (amount <= 0) {
      throw ArgumentError('Jumlah pembayaran harus lebih dari nol.');
    }
    if (tipAmount < 0 || walletDepositAmount < 0 || (tipAmount > 0 && walletDepositAmount > 0)) throw ArgumentError('Nominal tip atau deposit tidak valid. Pilih salah satu.');

    final db = await _db;

    return db.transaction((txn) async {
      final result = await txn.query(
        'service_orders',
        columns: ['order_number', 'total_cost', 'down_payment', 'service_status', 'mechanic_name', 'assigned_mechanic_id', 'customer_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (result.isEmpty) {
        throw StateError('Nota servis tidak ditemukan.');
      }

      final orderNumber = result.first['order_number']?.toString() ?? 'ID-$id';
      final serviceStatus = result.first['service_status']?.toString() ?? 'waiting';
      if (serviceStatus == 'cancelled') {
        throw StateError('Pembayaran tidak dapat ditambahkan pada servis yang dibatalkan.');
      }
      final total = result.first['total_cost'] as int? ?? 0;
      final paid = result.first['down_payment'] as int? ?? 0;
      final remaining = total - paid;

      if (amount > remaining) {
        throw ArgumentError('Pembayaran untuk tagihan melebihi sisa tagihan.');
      }
      if (walletDepositAmount > 0 && result.first['customer_id'] == null) {
        throw StateError('Kelebihan pembayaran hanya dapat disimpan sebagai saldo untuk pelanggan terdaftar.');
      }

      final newPaid = paid + amount;
      final now = DateTime.now();

      final updatedRows = await txn.update(
        'service_orders',
        {
          'down_payment': newPaid,
          'remaining_payment': total - newPaid,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (walletDepositAmount > 0) {
        final customerId = result.first['customer_id'] as int;
        final walletRows = await txn.rawQuery(
          'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
          [customerId],
        );
        final balance = walletRows.isEmpty ? 0 : (walletRows.first['balance_after'] as num?)?.toInt() ?? 0;
        final ledgerId = await txn.insert('customer_wallet_ledger', {
          'customer_id': customerId,
          'entry_type': 'deposit',
          'amount': walletDepositAmount,
          'balance_after': balance + walletDepositAmount,
          'description': 'Kelebihan pembayaran servis $orderNumber disimpan sebagai saldo pelanggan',
          'reference_type': 'customer_deposit',
          'payment_method': paymentMethod,
          'created_by_id': AuthSession.instance.userId,
          'created_by_name': AuthSession.instance.displayName,
          'created_at': now.toIso8601String(),
        });
        await txn.insert('cash_transactions', {
          'transaction_type': 'income',
          'category': 'Deposit Pelanggan',
          'description': 'Kelebihan pembayaran servis $orderNumber menjadi saldo deposit',
          'amount': walletDepositAmount,
          'reference_type': 'customer_deposit',
          'reference_id': ledgerId,
          'payment_method': paymentMethod,
          'transaction_date': now.toIso8601String(),
        });
      }

      // Pembayaran lanjutan juga masuk ke kas, terhubung ke nota servis.
      await ActivityLogRepository.record(
        txn,
        action: 'service_payment',
        description: 'Mencatat pembayaran servis $orderNumber sebesar Rp$amount.',
        entityType: 'service_order',
        entityId: id,
      );
      await txn.insert('cash_transactions', {
        'transaction_type': 'income',
        'category': 'Servis',
        'description': 'Pembayaran servis $orderNumber',
        'amount': amount,
        'reference_type': 'service_order',
        'reference_id': id,
        'payment_method': paymentMethod,
        'transaction_date': now.toIso8601String(),
      });
      if (tipAmount > 0) {
        final recipient = tipRecipientName?.trim().isNotEmpty == true
            ? tipRecipientName!.trim()
            : result.first['mechanic_name']?.toString();
        final tipId = await txn.insert('tip_transactions', {
          'amount': tipAmount,
          'source_type': 'service_order',
          'source_id': id,
          'recipient_account_id': result.first['assigned_mechanic_id'],
          'recipient_name': recipient,
          'payment_method': paymentMethod,
          'status': 'held',
          'received_by_id': AuthSession.instance.userId,
          'received_by_name': AuthSession.instance.displayName,
          'received_at': now.toIso8601String(),
        });
        await ActivityLogRepository.record(
          txn,
          action: 'tip_received',
          description: 'Mencatat uang tip servis $orderNumber sebesar Rp$tipAmount.',
          entityType: 'tip',
          entityId: tipId,
        );
      }

      return updatedRows;
    });
  }

  Future<List<Map<String, Object?>>> getServicePaymentHistory(int id) async {
    AuthSession.instance.requireCashierOrAdmin('Akun Mekanik tidak memiliki akses riwayat pembayaran.');
    final db = await _db;
    return db.rawQuery('''
      SELECT id, transaction_type, amount, category, description, reference_type, reference_id, transaction_date, payment_method, 'cash' AS payment_source
      FROM cash_transactions
      WHERE reference_type = 'service_order' AND reference_id = ? AND transaction_type = 'income'
      UNION ALL
      SELECT id, 'income' AS transaction_type, amount, 'Saldo Pelanggan' AS category, description, reference_type, reference_id, created_at AS transaction_date, payment_method, 'wallet' AS payment_source
      FROM customer_wallet_ledger
      WHERE reference_type = 'service_order' AND reference_id = ? AND entry_type = 'service_payment'
      ORDER BY transaction_date ASC, id ASC
    ''', [id, id]);
  }

  Future<int> deleteServiceOrder(int id) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat menghapus nota servis.');
    final db = await _db;
    final photoPaths = <String>{};

    final deleted = await db.transaction((txn) async {
      final orders = await txn.query(
        'service_orders',
        columns: ['id', 'service_status', 'down_payment', 'before_photo_path', 'after_photo_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (orders.isEmpty) return 0;
      final order = orders.first;

      // Hanya nota yang masih berada di antrean awal yang boleh dibersihkan.
      // Nota yang pernah masuk pemeriksaan/pengerjaan harus dipertahankan.
      if (order['service_status']?.toString() != 'waiting') {
        throw StateError('Hanya nota servis dummy yang masih berstatus menunggu dapat dihapus.');
      }
      if ((order['down_payment'] as num? ?? 0) > 0) {
        throw StateError('Nota servis memiliki uang muka; penghapusan ditolak.');
      }

      final payments = await txn.query(
        'cash_transactions',
        columns: ['id'],
        where: "reference_type = 'service_order' AND reference_id = ?",
        whereArgs: [id],
        limit: 1,
      );
      if (payments.isNotEmpty) {
        throw StateError('Nota servis sudah memiliki pembayaran kas dan tidak dapat dihapus.');
      }

      final walletEntries = await txn.query(
        'customer_wallet_ledger',
        columns: ['id'],
        where: "reference_type IN ('service_order', 'service_order_cancellation') AND reference_id = ?",
        whereArgs: [id],
        limit: 1,
      );
      if (walletEntries.isNotEmpty) {
        throw StateError('Nota servis memiliki riwayat saldo pelanggan dan tidak dapat dihapus.');
      }

      final stockMovements = await txn.query(
        'stock_movements',
        columns: ['id'],
        where: "reference_id = ? AND reference_type IN ('service_order', 'service_order_part', 'service_order_cancel')",
        whereArgs: [id],
        limit: 1,
      );
      final partAllocations = await txn.query(
        'service_part_allocations',
        columns: ['id'],
        where: 'service_order_item_id IN (SELECT id FROM service_order_items WHERE service_order_id = ?)',
        whereArgs: [id],
        limit: 1,
      );
      if (stockMovements.isNotEmpty || partAllocations.isNotEmpty) {
        throw StateError('Nota servis sudah memengaruhi stok atau batch biaya dan tidak dapat dihapus.');
      }

      for (final table in [
        'service_direct_cost_history',
        'service_estimate_history',
        'service_part_change_requests',
        'receipt_snapshots',
      ]) {
        final where = table == 'receipt_snapshots'
            ? "source_type = 'service_order' AND source_id = ?"
            : 'service_order_id = ?';
        final linked = await txn.query(
          table,
          columns: ['id'],
          where: where,
          whereArgs: [id],
          limit: 1,
        );
        if (linked.isNotEmpty) {
          throw StateError('Nota servis memiliki riwayat atau arsip terkait ($table); penghapusan ditolak.');
        }
      }

      final tips = await txn.query(
        'tip_transactions',
        columns: ['id'],
        where: "source_type = 'service_order' AND source_id = ?",
        whereArgs: [id],
        limit: 1,
      );
      if (tips.isNotEmpty) {
        throw StateError('Nota servis memiliki catatan uang tip dan tidak dapat dihapus.');
      }

      // Kumpulkan hanya foto di folder privat aplikasi. Jangan menyentuh file
      // di luar folder ini atau foto yang masih dipakai nota servis lain.
      final appDirectory = await getApplicationDocumentsDirectory();
      final photoDirectory = Directory(
        '${appDirectory.path}${Platform.pathSeparator}service_photos',
      );
      final photoRoot = photoDirectory.absolute.path;
      for (final value in [order['before_photo_path'], order['after_photo_path']]) {
        final path = value?.toString();
        if (path == null || path.isEmpty) continue;
        final absolutePath = File(path).absolute.path;
        if (!absolutePath.startsWith('$photoRoot${Platform.pathSeparator}')) continue;
        final shared = await txn.query(
          'service_orders',
          columns: ['id'],
          where: 'id != ? AND (before_photo_path = ? OR after_photo_path = ?)',
          whereArgs: [id, path, path],
          limit: 1,
        );
        if (shared.isEmpty) photoPaths.add(absolutePath);
      }

      final invoice = await txn.query(
        'service_orders',
        columns: ['order_number'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final count = await txn.delete('service_orders', where: 'id = ?', whereArgs: [id]);
      if (count > 0) {
        await ActivityLogRepository.record(
          txn,
          action: 'service_dummy_deleted',
          description: 'Menghapus nota servis dummy ${invoice.first['order_number'] ?? id}.',
          entityType: 'service_order',
          entityId: id,
        );
      }
      return count;
    });

    // File dihapus setelah transaksi database berhasil. Kegagalan file cleanup
    // tidak boleh membatalkan atau merusak penghapusan database yang sudah sah.
    for (final path in photoPaths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Best effort: hanya orphan photo yang mungkin tertinggal.
      }
    }
    return deleted;
  }

  Future<int> countServiceOrders({String? status}) async {
    _requireSignedIn();
    final db = await _db;
    final session = AuthSession.instance;

    if (status != null && !serviceStatuses.contains(status)) {
      throw ArgumentError('Status servis tidak valid.');
    }

    final result = session.isMechanic
        ? await db.rawQuery(
            status == null
                ? 'SELECT COUNT(*) AS total FROM service_orders WHERE assigned_mechanic_id = ?'
                : 'SELECT COUNT(*) AS total FROM service_orders WHERE assigned_mechanic_id = ? AND service_status = ?',
            status == null ? [session.userId] : [session.userId, status],
          )
        : await db.rawQuery(
            status == null
                ? 'SELECT COUNT(*) AS total FROM service_orders'
                : 'SELECT COUNT(*) AS total FROM service_orders WHERE service_status = ?',
            status == null ? [] : [status],
          );

    return Sqflite.firstIntValue(result) ?? 0;
  }


  // Admin dan Kasir boleh mengatur penugasan; pengelolaan akun mekanik
  // (buat/edit/nonaktifkan akun) tetap menjadi kewenangan Admin.
  Future<int> assignMechanic({required int serviceOrderId, int? mechanicId}) async {
    AuthSession.instance.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat mengubah penugasan mekanik.',
    );
    final db = await _db;
    String? mechanicName;
    if (mechanicId != null) {
      final users = await db.query(
        'app_users',
        columns: ['id', 'display_name'],
        where: "id = ? AND role = 'mechanic' AND is_active = 1",
        whereArgs: [mechanicId],
        limit: 1,
      );
      if (users.isEmpty) {
        throw StateError('Akun mekanik tidak ditemukan atau tidak aktif.');
      }
      mechanicName = users.first['display_name']?.toString();
    }
    return db.update(
      'service_orders',
      {
        'assigned_mechanic_id': mechanicId,
        'mechanic_name': mechanicName,
      },
      where: 'id = ?',
      whereArgs: [serviceOrderId],
    );
  }


  Future<Map<String, Object?>?> getLeastBusyMechanic() async {
    AuthSession.instance.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat melihat daftar mekanik.',
    );
    final db = await _db;
    final rows = await db.rawQuery("""
      SELECT u.id, u.display_name, COUNT(s.id) AS active_jobs
      FROM app_users u
      LEFT JOIN service_orders s
        ON s.assigned_mechanic_id = u.id
        AND s.service_status IN ('waiting', 'checking', 'in_progress')
      WHERE u.role = 'mechanic' AND u.is_active = 1
      GROUP BY u.id, u.display_name
      ORDER BY active_jobs ASC, u.id ASC
      LIMIT 1
    """);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> setQueuePriority({required int serviceOrderId, required bool priority}) async {
    if (!AuthSession.instance.isAdmin) {
      throw StateError('Hanya Admin yang dapat mengubah prioritas antrian.');
    }
    final db = await _db;
    return db.update(
      'service_orders',
      {'queue_priority': priority ? 1 : 0},
      where: "id = ? AND service_status IN ('waiting', 'checking', 'in_progress')",
      whereArgs: [serviceOrderId],
    );
  }


  static const List<Map<String, String>> serviceInspectionDefaults = [
    {'key': 'frame_fork', 'label': 'Rangka dan garpu depan'},
    {'key': 'brakes', 'label': 'Rem depan dan belakang'},
    {'key': 'gears', 'label': 'Operan gigi dan transmisi'},
    {'key': 'wheels_tires', 'label': 'Roda, velg, dan ban'},
    {'key': 'chain_crank', 'label': 'Rantai, crank, dan pedal'},
    {'key': 'handlebar_headset', 'label': 'Setang dan headset'},
    {'key': 'saddle', 'label': 'Sadel dan seatpost'},
    {'key': 'accessories', 'label': 'Lampu dan aksesori'},
    {'key': 'road_test', 'label': 'Uji jalan dan keselamatan'},
  ];

  Future<List<Map<String, Object?>>> getServiceInspectionChecklist(
    int serviceOrderId,
  ) async {
    _requireSignedIn();
    final db = await _db;
    final session = AuthSession.instance;
    final order = await db.query(
      'service_orders',
      columns: ['id', 'assigned_mechanic_id'],
      where: 'id = ?',
      whereArgs: [serviceOrderId],
      limit: 1,
    );
    if (order.isEmpty) throw StateError('Nota servis tidak ditemukan.');
    if (session.isMechanic && order.first['assigned_mechanic_id'] != session.userId) {
      throw StateError('Checklist hanya dapat dilihat pada servis yang ditugaskan kepada Anda.');
    }
    await db.transaction((txn) async {
      for (final item in serviceInspectionDefaults) {
        await txn.insert(
          'service_inspection_items',
          {
            'service_order_id': serviceOrderId,
            'check_key': item['key'],
            'label': item['label'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
    return db.query(
      'service_inspection_items',
      where: 'service_order_id = ?',
      whereArgs: [serviceOrderId],
      orderBy: 'id ASC',
    );
  }

  Future<void> updateServiceInspectionItem({
    required int serviceOrderId,
    required String checkKey,
    required bool checked,
    String? note,
  }) async {
    _requireSignedIn();
    final db = await _db;
    final session = AuthSession.instance;
    final allowed = serviceInspectionDefaults.any((item) => item['key'] == checkKey);
    if (!allowed) throw ArgumentError('Komponen pemeriksaan tidak valid.');
    final order = await db.query(
      'service_orders',
      columns: ['id', 'assigned_mechanic_id'],
      where: 'id = ?',
      whereArgs: [serviceOrderId],
      limit: 1,
    );
    if (order.isEmpty) throw StateError('Nota servis tidak ditemukan.');
    if (session.isMechanic) {
      if (order.first['assigned_mechanic_id'] != session.userId) {
        throw StateError('Anda hanya dapat mengubah checklist servis yang ditugaskan kepada Anda.');
      }
    } else {
      session.requireCashierOrAdmin('Akses checklist servis ditolak.');
    }
    final item = serviceInspectionDefaults.firstWhere((entry) => entry['key'] == checkKey);
    await db.insert(
      'service_inspection_items',
      {
        'service_order_id': serviceOrderId,
        'check_key': checkKey,
        'label': item['label'],
        'is_checked': checked ? 1 : 0,
        'note': _nullableText(note),
        'checked_by_user_id': session.userId,
        'checked_at': checked ? DateTime.now().toIso8601String() : null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String? _nullableText(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
