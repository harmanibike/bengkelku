
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/activity_log_repository.dart';
import '../../../core/auth/auth_session.dart';

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
    String? photoBase64,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengelola pelanggan.');
    final db = await _db;

    return db.transaction((txn) async {
      final id = await txn.insert('customers', {
        'name': name.trim(),
        'phone': phone?.trim(),
        'address': address?.trim(),
        'email': email?.trim(),
        'notes': notes?.trim(),
        'photo_base64': photoBase64,
      });
      await ActivityLogRepository.record(
        txn,
        action: 'customer_created',
        description: 'Menambahkan pelanggan ${name.trim()}.',
        entityType: 'customer',
        entityId: id,
      );
      return id;
    });
  }

  Future<int> importCustomers(List<Map<String, Object?>> customers) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengelola pelanggan.');
    if (customers.isEmpty) return 0;
    final db = await _db;

    return db.transaction((txn) async {
      var imported = 0;
      for (final customer in customers) {
        final name = (customer['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final id = await txn.insert('customers', {
          'name': name,
          'phone': (customer['phone'] as String?)?.trim(),
          'email': (customer['email'] as String?)?.trim(),
          'photo_base64': customer['photo_base64'],
        });
        await ActivityLogRepository.record(
          txn,
          action: 'customer_created',
          description: 'Mengimpor pelanggan $name dari kontak telepon.',
          entityType: 'customer',
          entityId: id,
        );
        imported++;
      }
      return imported;
    });
  }

  Future<int> updateCustomer({
    required int id,
    required String name,
    String? phone,
    String? address,
    String? email,
    String? notes,
    String? photoBase64,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengelola pelanggan.');
    final db = await _db;

    return db.transaction((txn) async {
      final updated = await txn.update(
        'customers',
        {
          'name': name.trim(),
          'phone': phone?.trim(),
          'address': address?.trim(),
          'email': email?.trim(),
          'notes': notes?.trim(),
          'photo_base64': photoBase64,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated > 0) {
        await ActivityLogRepository.record(
          txn,
          action: 'customer_updated',
          description: 'Memperbarui data pelanggan ${name.trim()}.',
          entityType: 'customer',
          entityId: id,
        );
      }
      return updated;
    });
  }

  Future<List<Map<String, Object?>>> getCustomers({
    String keyword = '',
    int? limit,
    int offset = 0,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat pelanggan.');
    final db = await _db;
    final search = '%${keyword.trim()}%';
    final whereClause = keyword.trim().isEmpty
        ? ''
        : 'WHERE c.name LIKE ? OR c.phone LIKE ?';
    final args = <Object?>[];
    if (keyword.trim().isNotEmpty) args.addAll([search, search]);
    final limitClause = limit == null ? '' : 'LIMIT ? OFFSET ?';
    if (limit != null) args.addAll([limit, offset]);

    return db.rawQuery('''
      SELECT c.*,
        COALESCE((
          SELECT SUM(l.points)
          FROM loyalty_point_ledger l
          WHERE l.customer_id = c.id
        ), 0) AS loyalty_points,
        COALESCE((
          SELECT w.balance_after
          FROM customer_wallet_ledger w
          WHERE w.customer_id = c.id
          ORDER BY w.id DESC
          LIMIT 1
        ), 0) AS wallet_balance
      FROM customers c
      $whereClause
      ORDER BY c.name COLLATE NOCASE ASC
      $limitClause
    ''', args);
  }

  Future<Map<String, Object?>?> findCustomerByNameOrPhone(String input) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mencari pelanggan.');
    final keyword = input.trim();
    if (keyword.length < 3) return null;

    final db = await _db;
    final customers = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
    final normalizedInput = keyword.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

    String normalizePhone(String value) {
      var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.startsWith('62')) digits = '0' + digits.substring(2);
      return digits;
    }

    final inputDigits = normalizePhone(keyword);
    if (inputDigits.length >= 6) {
      final phoneMatches = customers.where((customer) {
        final phone = normalizePhone((customer['phone'] ?? '').toString());
        return phone.isNotEmpty && phone == inputDigits;
      }).toList();
      if (phoneMatches.length == 1) return phoneMatches.first;
      if (phoneMatches.length > 1) return null;
    }

    final nameMatches = customers.where((customer) {
      final name = (customer['name'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
      return name == normalizedInput;
    }).toList();
    if (nameMatches.length == 1) return nameMatches.first;
    if (nameMatches.length > 1) return null;

    // Nama parsial hanya otomatis dipilih jika hasilnya tepat satu.
    final partialMatches = customers.where((customer) {
      final name = (customer['name'] ?? '').toString().toLowerCase();
      return name.contains(normalizedInput);
    }).toList();
    return partialMatches.length == 1 ? partialMatches.first : null;
  }

  Future<Map<String, Object?>?> getCustomerById(int id) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat pelanggan.');
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
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat menghapus pelanggan.');
    final db = await _db;

    // Riwayat transaksi tetap aman.
    // Relasi sepeda dan servis mengikuti aturan foreign key.
    return db.transaction((txn) async {
      final rows = await txn.query('customers',
        columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
      final deleted = await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
      if (deleted > 0) {
        await ActivityLogRepository.record(
          txn,
          action: 'customer_deleted',
          description: 'Menghapus data pelanggan ${rows.isEmpty ? '#$id' : rows.first['name']}.',
          entityType: 'customer',
          entityId: id,
        );
      }
      return deleted;
    });
  }

  Future<int> countCustomers() async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat data pelanggan.');
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
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengelola sepeda pelanggan.');
    final db = await _db;

    return db.transaction((txn) async {
      final id = await txn.insert('bicycles', {
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
      await ActivityLogRepository.record(
        txn,
        action: 'bicycle_created',
        description: 'Menambahkan sepeda ${[brand, model].where((v) => v != null && v.trim().isNotEmpty).join(' ')}.',
        entityType: 'bicycle',
        entityId: id,
      );
      return id;
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
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengelola sepeda pelanggan.');
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
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat sepeda pelanggan.');
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
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat sepeda pelanggan.');
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
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat menghapus data sepeda.');
    final db = await _db;

    return db.delete(
      'bicycles',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countBicycles() async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat data sepeda.');
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
