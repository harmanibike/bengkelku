import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class DeviceModeRepository {
  static const settingKey = 'device_mode';
  static const localMode = 'local';
  static const defaultClientPort = 8765;
  static const clientHostKey = 'client_server_host';
  static const clientPortKey = 'client_server_port';

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

  Future<Map<String, String>> getClientConfig() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_key', 'setting_value'],
      where: 'setting_key IN (?, ?)',
      whereArgs: [clientHostKey, clientPortKey],
    );
    final values = <String, String>{};
    for (final row in rows) {
      final key = row['setting_key']?.toString();
      final value = row['setting_value']?.toString();
      if (key != null && value != null) values[key] = value;
    }
    return {
      'host': values[clientHostKey] ?? '',
      'port': values[clientPortKey] ?? defaultClientPort.toString(),
    };
  }

  Future<void> saveClientConfig({
    required String host,
    required int port,
  }) async {
    final normalizedHost = host.trim();
    if (normalizedHost.isEmpty || normalizedHost.contains('/') ||
        normalizedHost.contains('://') || normalizedHost.contains(' ')) {
      throw ArgumentError('Masukkan alamat IP atau nama host server yang valid.');
    }
    if (port < 1 || port > 65535) {
      throw ArgumentError('Port harus berada pada rentang 1 sampai 65535.');
    }

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(
        'app_settings',
        {
          'setting_key': clientHostKey,
          'setting_value': normalizedHost,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'app_settings',
        {
          'setting_key': clientPortKey,
          'setting_value': port.toString(),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
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
