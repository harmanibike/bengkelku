import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';

class PurchaseCostSettingsRepository {
  static const settingKey = 'purchase_cost_method';
  static const weightedAverage = 'weighted_average';
  static const lastCost = 'last_cost';
  static const manual = 'manual';
  static const perBatch = 'per_batch';

  static const methods = <String, String>{
    weightedAverage: 'Rata-rata tertimbang',
    lastCost: 'Harga akhir',
    manual: 'Manual',
    perBatch: 'Per batch',
  };

  Future<Database> get _db => AppDatabase.instance.database;

  Future<String> getMethod() async {
    AuthSession.instance.requireAdmin('Pengaturan metode harga beli hanya dapat diakses Admin.');
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [settingKey],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.first['setting_value']?.toString();
    return methods.containsKey(value) ? value! : weightedAverage;
  }

  Future<void> setMethod(String method) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah metode harga beli.');
    if (!methods.containsKey(method)) {
      throw ArgumentError('Metode harga beli tidak dikenal.');
    }
    final db = await _db;
    await db.insert(
      'app_settings',
      {
        'setting_key': settingKey,
        'setting_value': method,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, Object?>>> getProductBatches(int productId) async {
    AuthSession.instance.requireAdmin('Riwayat batch biaya hanya dapat diakses Admin.');
    final db = await _db;
    return db.rawQuery('''
      SELECT b.*, p.invoice_number
      FROM inventory_cost_batches b
      LEFT JOIN purchases p ON p.id = b.purchase_id
      WHERE b.product_id = ?
      ORDER BY b.received_at DESC, b.id DESC
    ''', [productId]);
  }
}
