import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';

class ServicePricingRepository {
  Future<Database> get _db => AppDatabase.instance.database;
  static const String modeBoth = 'both';

  Future<String> getPriceMode() async {
    final db = await _db;
    final rows = await db.query('app_settings', columns: ['setting_value'], where: 'setting_key = ?', whereArgs: ['service_price_mode'], limit: 1);
    return rows.isEmpty ? modeBoth : (rows.first['setting_value']?.toString() ?? modeBoth);
  }

  Future<void> setPriceModeBoth() async {
    final db = await _db;
    await db.insert('app_settings', {'setting_key': 'service_price_mode', 'setting_value': modeBoth, 'updated_at': DateTime.now().toIso8601String()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> getServices({bool activeOnly = false, String keyword = ''}) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (activeOnly) where.add('is_active = 1');
    if (keyword.trim().isNotEmpty) {
      where.add('(name LIKE ? OR category LIKE ? OR description LIKE ?)');
      final q = '%${keyword.trim()}%';
      args.addAll([q, q, q]);
    }
    return db.query('service_catalog', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'sort_order ASC, name COLLATE NOCASE ASC');
  }

  Future<int> saveService({int? id, required String name, String? category, String? description, required int standardPrice, required String reason}) async {
    if (name.trim().isEmpty) throw ArgumentError('Nama jasa wajib diisi.');
    if (standardPrice < 0) throw ArgumentError('Harga tidak boleh negatif.');
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      if (id == null) {
        return txn.insert('service_catalog', {'name': name.trim(), 'category': _clean(category), 'description': _clean(description), 'standard_price': standardPrice, 'is_active': 1, 'created_at': now, 'updated_at': now});
      }
      final old = await txn.query('service_catalog', columns: ['standard_price'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (old.isEmpty) throw StateError('Master jasa tidak ditemukan.');
      final oldPrice = old.first['standard_price'] as int? ?? 0;
      await txn.update('service_catalog', {'name': name.trim(), 'category': _clean(category), 'description': _clean(description), 'standard_price': standardPrice, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
      if (oldPrice != standardPrice) {
        await txn.insert('service_price_history', {'service_id': id, 'old_price': oldPrice, 'new_price': standardPrice, 'change_reason': _clean(reason), 'changed_by': 'Admin', 'changed_at': now});
      }
      return id;
    });
  }

  Future<void> setActive(int id, bool active) async {
    final db = await _db;
    await db.update('service_catalog', {'is_active': active ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> getPriceHistory({int? serviceId}) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT h.*, s.name AS service_name
      FROM service_price_history h
      JOIN service_catalog s ON s.id = h.service_id
      ${serviceId == null ? '' : 'WHERE h.service_id = ?'}
      ORDER BY h.id DESC LIMIT 300
    ''', serviceId == null ? [] : [serviceId]);
  }

  String? _clean(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
