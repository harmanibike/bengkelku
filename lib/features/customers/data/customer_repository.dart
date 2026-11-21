
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class CustomerRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  // =========================
  // DATA PELANGGAN
  // =========================

  Future<int> addCustomer({
    required String name,
    String? phone,
    String? address,
    String? email,
    String? notes,
  }) async {
    final db = await _db;

    return db.insert('customers', {
      'name': name.trim(),
      'phone': phone?.trim(),
      'address': address?.trim(),
      'email': email?.trim(),
      'notes': notes?.trim(),
    });
  }

  Future<int> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? address,
    String? email,
    String? notes,
  }) async {
    final db = await _db;

    return db.update(
      'customers',
      {
        'name': name.trim(),
        'phone': phone?.trim(),
        'address': address?.trim(),
        'email': email?.trim(),
        'notes': notes?.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> getCustomers({
    String keyword = '',
  }) async {
    final db = await _db;
    final search = '%${keyword.trim()}%';

    return db.query(
      'customers',
      where: keyword.trim().isEmpty
          ? null
          : 'name LIKE ? OR phone LIKE ?',
      whereArgs: keyword.trim().isEmpty
          ? null
          : [search, search],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<Map<String, Object?>?> getCustomerById(int id) async {
    final db = await _db;
    final result = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  Future<int> deleteCustomer(int id) async {
    final db = await _db;

    // Riwayat transaksi tetap aman.
    // Relasi sepeda dan servis mengikuti aturan foreign key.
    return db.delete(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countCustomers() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM customers',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // =========================
  // DATA SEPEDA
  // =========================

  Future<int> addBicycle({
    int? customerId,
    String? brand,
    String? model,
    String? bicycleType,
    String? color,
    String? frameSize,
    String? serialNumber,
    String? purchaseDate,
    String? warrantyUntil,
    String? notes,
  }) async {
    final db = await _db;

    return db.insert('bicycles', {
      'customer_id': customerId,
      'brand': brand?.trim(),
      'model': model?.trim(),
      'bicycle_type': bicycleType?.trim(),
      'color': color?.trim(),
      'frame_size': frameSize?.trim(),
      'serial_number': _nullableText(serialNumber),
      'purchase_date': purchaseDate,
      'warranty_until': warrantyUntil,
      'notes': notes?.trim(),
    });
  }

  Future<int> updateBicycle({
    required int id,
    int? customerId,
    String? brand,
    String? model,
    String? bicycleType,
    String? color,
    String? frameSize,
    String? serialNumber,
    String? purchaseDate,
    String? warrantyUntil,
    String? notes,
  }) async {
    final db = await _db;

    return db.update(
      'bicycles',
      {
        'customer_id': customerId,
        'brand': brand?.trim(),
        'model': model?.trim(),
        'bicycle_type': bicycleType?.trim(),
        'color': color?.trim(),
        'frame_size': frameSize?.trim(),
        'serial_number': _nullableText(serialNumber),
        'purchase_date': purchaseDate,
        'warranty_until': warrantyUntil,
        'notes': notes?.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> getBicycles({
    int? customerId,
    String keyword = '',
  }) async {
    final db = await _db;
    final conditions = <String>[];
    final arguments = <Object?>[];

    if (customerId != null) {
      conditions.add('b.customer_id = ?');
      arguments.add(customerId);
    }

    if (keyword.trim().isNotEmpty) {
      conditions.add(
        '(b.brand LIKE ? OR b.model LIKE ? '
        'OR b.serial_number LIKE ? OR c.name LIKE ?)',
      );

      final search = '%${keyword.trim()}%';
      arguments.addAll([search, search, search, search]);
    }

    final whereClause = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';

    return db.rawQuery('''
      SELECT
        b.*,
        c.name AS customer_name,
        c.phone AS customer_phone
      FROM bicycles b
      LEFT JOIN customers c ON c.id = b.customer_id
      $whereClause
      ORDER BY b.id DESC
    ''', arguments);
  }

  Future<Map<String, Object?>?> getBicycleById(int id) async {
    final db = await _db;
    final result = await db.query(
      'bicycles',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    return result.isEmpty ? null : result.first;
  }

  Future<int> deleteBicycle(int id) async {
    final db = await _db;

    return db.delete(
      'bicycles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countBicycles() async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM bicycles',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  String? _nullableText(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
