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

      return txn.insert('service_orders', {
        'order_number': orderNumber,
        'customer_id': customerId,
        'bicycle_id': bicycleId,
        'complaint': cleanComplaint,
        'diagnosis': _nullableText(diagnosis),
        'service_status': 'waiting',
        'estimated_cost': estimated,
        'labor_cost': labor,
        'parts_cost': parts,
        'discount': safeDiscount,
        'total_cost': safeTotal,
        'down_payment': paid,
        'remaining_payment': safeTotal - paid,
        'mechanic_name': _nullableText(mechanicName),
        'received_at': now.toIso8601String(),
        'notes': _nullableText(notes),
        'before_photo_path': _nullableText(beforePhotoPath),
      });
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

  // Memperbarui hasil pemeriksaan dan rincian biaya.
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
    final existing = await getServiceOrderById(id);

    if (existing == null) {
      throw StateError('Nota servis tidak ditemukan.');
    }

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

    return db.update(
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
  }

  // Mengubah status pengerjaan.
  Future<int> updateServiceStatus({
    required int id,
    required String status,
  }) async {
    if (!serviceStatuses.contains(status)) {
      throw ArgumentError('Status servis tidak valid.');
    }

    final db = await _db;
    final data = <String, Object?>{
      'service_status': status,
    };

    if (status == 'completed') {
      data['completed_at'] = DateTime.now().toIso8601String();
    }

    return db.update(
      'service_orders',
      data,
      where: 'id = ?',
      whereArgs: [id],
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
        columns: ['total_cost', 'down_payment'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (result.isEmpty) {
        throw StateError('Nota servis tidak ditemukan.');
      }

      final total = result.first['total_cost'] as int? ?? 0;
      final paid = result.first['down_payment'] as int? ?? 0;
      final remaining = total - paid;

      if (amount > remaining) {
        throw ArgumentError('Pembayaran melebihi sisa tagihan.');
      }

      final newPaid = paid + amount;

      return txn.update(
        'service_orders',
        {
          'down_payment': newPaid,
          'remaining_payment': total - newPaid,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<int> deleteServiceOrder(int id) async {
    final db = await _db;
    return db.delete(
      'service_orders',
      where: 'id = ?',
      whereArgs: [id],
    );
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
