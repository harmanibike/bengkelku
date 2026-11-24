import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';

class BusinessProfileRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  static const fields = <String, String>{
    'business_name': 'Nama usaha',
    'business_address': 'Alamat',
    'business_phone': 'Nomor telepon',
    'business_whatsapp': 'WhatsApp',
    'business_email': 'Email',
    'business_website': 'Website',
    'business_tax_number': 'Nomor pajak',
    'business_logo_path': 'Logo',
  };

  Future<Map<String, String>> getProfile() async {
    AuthSession.instance.requireCashierOrAdmin('Profil usaha hanya dapat dilihat Admin dan Kasir.');
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_key', 'setting_value'],
      where: 'setting_key LIKE ?',
      whereArgs: ['business_%'],
    );
    final result = <String, String>{};
    for (final row in rows) {
      result[row['setting_key'].toString()] =
          row['setting_value']?.toString() ?? '';
    }
    return result;
  }

  Future<void> saveProfile(Map<String, String> values) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah profil usaha.');
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        if (!fields.containsKey(entry.key)) continue;
        await txn.insert(
          'app_settings',
          {
            'setting_key': entry.key,
            'setting_value': entry.value.trim(),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
