import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class ServiceRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  static const List<String> serviceStatuses = [
    'waiting',
    'checking',
    'in_progress',
    'completed',
    'delivered',
    'cancelled',
  ];

  // Membuat nomor servis unik berdasarkan tanggal dan waktu.
  String _generateOrderNumber([DateTime? dateTime]) {
    final date = dateTime ?? DateTime.now();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    final datePart =
        '${date.year}${twoDigits(date.month)}${twoDigits(date.day)}';
    final timePart =
        '${twoDigits(date.hour)}${twoDigits(date.minute)}${twoDigits(date.second)}';

    return 'SRV-$datePart-$timePart-${date.millisecond.toString().padLeft(3, '0')}';
  }

  int _safeAmount(int value) => value < 0 ? 0 : value;

  // Membuat nota penerimaan servis.
  Future<int> createServiceOrder({
    required int customerId,
    required int bicycleId,
    required String complaint,
    String? diagnosis,
    int estimatedCost = 0,
    int laborCost = 0,
    int partsCost = 0,
    int directPartsCost = 0,
    int otherDirectCost = 0,
    int discount = 0,
    int downPayment = 0,
    String? mechanicName,
    String? notes,
    String? beforePhotoPath,
  }) async {
    final db = await _db;

    final cleanComplaint = complaint.trim();
    if (cleanComplaint.isEmpty) {
      throw ArgumentError('Keluhan pelanggan wajib diisi.');
    }

    final estimated = _safeAmount(estimatedCost);
    final labor = _safeAmount(laborCost);
    final parts = _safeAmount(partsCost);
    final directParts = _safeAmount(directPartsCost);
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
      final customer = await txn.query(
        'customers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );

      if (customer.isEmpty) {
        throw StateError('Pelanggan tidak ditemukan.');
      }

      final bicycle = await txn.query(
        'bicycles',
        columns: ['id'],
        where: 'id = ? AND customer_id = ?',
        whereArgs: [bicycleId, customerId],
        limit: 1,
      );

      if (bicycle.isEmpty) {
        throw StateError(
          'Sepeda tidak ditemukan atau bukan milik pelanggan ini.',
        );
      }

      final now = DateTime.now();
      final orderNumber = _generateOrderNumber(now);

      final serviceOrderId = await txn.insert('service_orders', {
        'order_number': orderNumber,
        'customer_id': customerId,
        'bicycle_id': bicycleId,
        'complaint': cleanComplaint,
        'diagnosis': _nullableText(diagnosis),
        'service_status': 'waiting',
        'estimated_cost': estimated,
        'labor_cost': labor,
        'parts_cost': parts,
        'direct_parts_cost': directParts,
        'other_direct_cost': otherDirect,
        'discount': safeDiscount,
        'total_cost': safeTotal,
        'down_payment': paid,
        'remaining_payment': safeTotal - paid,
        'mechanic_name': _nullableText(mechanicName),
        'received_at': now.toIso8601String(),
        'notes': _nullableText(notes),
        'before_photo_path': _nullableText(beforePhotoPath),
      });

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
        'new_direct_parts_cost': directParts,
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
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final arguments = <Object?>[];

    if (keyword.trim().isNotEmpty) {
      final search = '%${keyword.trim()}%';
      conditions.add(
        '(s.order_number LIKE ? OR s.complaint LIKE ? '
        'OR c.name LIKE ? OR c.phone LIKE ? '
        'OR b.brand LIKE ? OR b.model LIKE ? '
        'OR b.serial_number LIKE ?)',
      );
      arguments.addAll([
        search,
        search,
        search,
        search,
        search,
        search,
        search,
      ]);
    }

    if (status != null && status.trim().isNotEmpty) {
      if (!serviceStatuses.contains(status)) {
        throw ArgumentError('Status servis tidak valid.');
      }
      conditions.add('s.service_status = ?');
      arguments.add(status);
    }

    final whereClause =
        conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';

    return db.rawQuery('''
      SELECT
        s.*,
        c.name AS customer_name,
        c.phone AS customer_phone,
        b.brand AS bicycle_brand,
        b.model AS bicycle_model,
        b.bicycle_type AS bicycle_type,
        b.color AS bicycle_color,
        b.serial_number AS bicycle_serial_number
      FROM service_orders s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN bicycles b ON b.id = s.bicycle_id
      $whereClause
      ORDER BY s.id DESC
    ''', arguments);
  }

  // Detail satu nota servis.
  Future<Map<String, Object?>?> getServiceOrderById(int id) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT
        s.*,
        c.name AS customer_name,
        c.phone AS customer_phone,
        c.address AS customer_address,
        b.brand AS bicycle_brand,
        b.model AS bicycle_model,
        b.bicycle_type AS bicycle_type,
        b.color AS bicycle_color,
        b.frame_size AS bicycle_frame_size,
        b.serial_number AS bicycle_serial_number
      FROM service_orders s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN bicycles b ON b.id = s.bicycle_id
      WHERE s.id = ?
      LIMIT 1
    ''', [id]);

    return result.isEmpty ? null : result.first;
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
  }) async {
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

      if (paid > total) {
        throw ArgumentError(
          'Total baru tidak boleh lebih kecil dari DP yang sudah dibayar.',
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

  // Riwayat audit perubahan modal, tidak mengubah tagihan dan stok.
  Future<List<Map<String, Object?>>> getServiceDirectCostHistory(int id) async {
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
  }) async {
    if (!serviceStatuses.contains(status)) {
      throw ArgumentError('Status servis tidak valid.');
    }

    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'service_orders',
        columns: ['service_status', 'remaining_payment', 'order_number'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Nota servis tidak ditemukan.');

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

      if (status == 'cancelled') {
        final paidRows = await txn.rawQuery(
          '''
          SELECT COALESCE(SUM(amount), 0) AS total_paid
          FROM cash_transactions
          WHERE reference_type = 'service_order'
            AND reference_id = ?
            AND transaction_type = 'income'
          ''',
          [id],
        );
        final refund = Sqflite.firstIntValue(paidRows) ?? 0;
        if (refund > 0) {
          await txn.insert('cash_transactions', {
            'transaction_type': 'expense',
            'category': 'Pembatalan Servis',
            'description':
                'Pengembalian pembayaran servis ${rows.first['order_number'] ?? id}',
            'amount': refund,
            'reference_type': 'service_order_cancellation',
            'reference_id': id,
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
      return updated;
    });
  }

  /// Daftar servis yang masih memiliki piutang, termasuk sepeda yang sudah diambil.
  Future<List<Map<String, Object?>>> getOutstandingServiceOrders({
    String keyword = '',
  }) async {
    final db = await _db;
    final term = keyword.trim();
    return db.rawQuery('''
      SELECT
        s.*,
        c.name AS customer_name,
        c.phone AS customer_phone,
        b.brand AS bicycle_brand,
        b.model AS bicycle_model
      FROM service_orders s
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN bicycles b ON b.id = s.bicycle_id
      WHERE s.remaining_payment > 0
        AND s.service_status != 'cancelled'
        AND (
          ? = ''
          OR s.order_number LIKE ?
          OR COALESCE(c.name, '') LIKE ?
          OR COALESCE(c.phone, '') LIKE ?
        )
      ORDER BY s.received_at ASC, s.id ASC
    ''', [term, '%$term%', '%$term%', '%$term%']);
  }

  Future<List<Map<String, Object?>>> getServiceStatusHistory(int id) async {
    final db = await _db;
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
  Future<int> addPayment({
    required int id,
    required int amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Jumlah pembayaran harus lebih dari nol.');
    }

    final db = await _db;

    return db.transaction((txn) async {
      final result = await txn.query(
        'service_orders',
        columns: ['order_number', 'total_cost', 'down_payment', 'service_status'],
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
        throw ArgumentError('Pembayaran melebihi sisa tagihan.');
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

      // Pembayaran lanjutan juga masuk ke kas, terhubung ke nota servis.
      await txn.insert('cash_transactions', {
        'transaction_type': 'income',
        'category': 'Servis',
        'description': 'Pembayaran servis $orderNumber',
        'amount': amount,
        'reference_type': 'service_order',
        'reference_id': id,
        'transaction_date': now.toIso8601String(),
      });

      return updatedRows;
    });
  }

  Future<int> deleteServiceOrder(int id) async {
    final db = await _db;

    return db.transaction((txn) async {
      final order = await txn.query(
        'service_orders',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (order.isEmpty) return 0;

      // Jangan hapus nota yang sudah memiliki pembayaran kas.
      // cash_transactions tidak memakai foreign key ke service_orders;
      // menghapus nota saja akan meninggalkan pemasukan tanpa sumber.
      final payments = await txn.query(
        'cash_transactions',
        columns: ['id'],
        where: "reference_type = 'service_order' AND reference_id = ?",
        whereArgs: [id],
        limit: 1,
      );

      if (payments.isNotEmpty) {
        throw StateError(
          'Nota servis sudah memiliki pembayaran. '
          'Batalkan melalui proses koreksi kas agar riwayat keuangan tetap utuh.',
        );
      }

      return txn.delete(
        'service_orders',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<int> countServiceOrders({String? status}) async {
    final db = await _db;

    if (status != null && !serviceStatuses.contains(status)) {
      throw ArgumentError('Status servis tidak valid.');
    }

    final result = await db.rawQuery(
      status == null
          ? 'SELECT COUNT(*) AS total FROM service_orders'
          : 'SELECT COUNT(*) AS total FROM service_orders '
              'WHERE service_status = ?',
      status == null ? [] : [status],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  String? _nullableText(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
