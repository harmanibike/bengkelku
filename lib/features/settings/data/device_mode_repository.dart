import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class DeviceModeRepository {
  static const settingKey = 'device_mode';
  static const localMode = 'local';

  Future<Database> get _db => AppDatabase.instance.database;

  Future<String> getMode() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [settingKey],
      limit: 1,
    );

    if (rows.isEmpty) return localMode;
    final value = rows.first['setting_value']?.toString();
    // Mode yang belum didukung tidak boleh mengalihkan aplikasi dari database lokal.
    return value == localMode ? value! : localMode;
  }

  Future<void> saveMode(String mode) async {
    if (mode != localMode) {
      throw ArgumentError('Mode Server dan Client belum tersedia.');
    }

    final db = await _db;
    await db.insert(
      'app_settings',
      {
        'setting_key': settingKey,
        'setting_value': localMode,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
