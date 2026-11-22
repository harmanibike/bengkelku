import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class SupplierRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getSuppliers({String keyword = ''}) async {
    final db = await _db;
    final term = keyword.trim();
    return db.query(
      'suppliers',
      where: term.isEmpty ? null : '(name LIKE ? OR phone LIKE ? OR email LIKE ?)',
      whereArgs: term.isEmpty ? null : ['%$term%', '%$term%', '%$term%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<int> addSupplier({required String name, String? phone, String? address, String? email, String? notes}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pemasok wajib diisi.');
    final db = await _db;
    return db.insert('suppliers', {
      'name': cleanName, 'phone': _nullable(phone), 'address': _nullable(address),
      'email': _nullable(email), 'notes': _nullable(notes),
    });
  }

  Future<int> updateSupplier({required int id, required String name, String? phone, String? address, String? email, String? notes}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pemasok wajib diisi.');
    final db = await _db;
    return db.update('suppliers', {
      'name': cleanName, 'phone': _nullable(phone), 'address': _nullable(address),
      'email': _nullable(email), 'notes': _nullable(notes),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countPurchases(int supplierId) async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM purchases WHERE supplier_id = ?', [supplierId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
