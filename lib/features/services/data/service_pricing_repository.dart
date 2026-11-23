import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/activity_log_repository.dart';

class ServicePricingRepository {
  Future<Database> get _db => AppDatabase.instance.database;
  static const String modeBoth = 'both';

  Future<bool> hasAdminPin() async {
    AuthSession.instance.requireAdmin('Pengaturan harga jasa hanya dapat diakses Admin.');
    final db = await _db;
    final rows = await db.query('app_settings', columns: ['setting_value'], where: "setting_key = 'service_admin_pin_hash'", limit: 1);
    return rows.isNotEmpty && (rows.first['setting_value']?.toString().isNotEmpty ?? false);
  }

  Future<void> setupAdminPin(String pin) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengatur PIN harga jasa.');
    if (!RegExp(r'^\d{6,8}$').hasMatch(pin)) throw ArgumentError('PIN admin harus 6–8 angka.');
    final db = await _db;
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final saltText = base64.encode(salt);
    final hash = sha256.convert(utf8.encode('$saltText:$pin')).toString();
    await db.transaction((txn) async {
      final rows = await txn.query('app_settings', columns: ['id'], where: "setting_key = 'service_admin_pin_hash'", limit: 1);
      if (rows.isNotEmpty) throw StateError('PIN admin sudah dibuat.');
      await txn.insert('app_settings', {'setting_key': 'service_admin_pin_salt', 'setting_value': saltText});
      await txn.insert('app_settings', {'setting_key': 'service_admin_pin_hash', 'setting_value': hash});
    });
  }

  Future<bool> verifyAdminPin(String pin) async {
    AuthSession.instance.requireAdmin('Verifikasi PIN harga jasa hanya untuk Admin.');
    final db = await _db;
    final rows = await db.query('app_settings', columns: ['setting_key', 'setting_value'], where: "setting_key IN ('service_admin_pin_salt','service_admin_pin_hash')");
    final values = {for (final row in rows) row['setting_key'].toString(): row['setting_value']?.toString() ?? ''};
    final salt = values['service_admin_pin_salt'] ?? '';
    final expected = values['service_admin_pin_hash'] ?? '';
    if (salt.isEmpty || expected.isEmpty) return false;
    return sha256.convert(utf8.encode('$salt:$pin')).toString() == expected;
  }

  Future<List<Map<String, Object?>>> getServices({bool activeOnly = false, String keyword = ''}) async {
    AuthSession.instance.requireCashierOrAdmin('Daftar harga jasa hanya dapat diakses Admin dan Kasir.');
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (activeOnly) where.add('is_active = 1');
    if (keyword.trim().isNotEmpty) {
      where.add('(name LIKE ? OR category LIKE ? OR description LIKE ?)');
      final q = '%\${keyword.trim()}%';
      args.addAll([q, q, q]);
    }
    return db.query('service_catalog', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args.isEmpty ? null : args, orderBy: 'sort_order ASC, name COLLATE NOCASE ASC');
  }

  Future<int> saveService({int? id, required String name, String? category, String? description, required int standardPrice, required String reason}) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengelola harga jasa.');
    if (name.trim().isEmpty) throw ArgumentError('Nama jasa wajib diisi.');
    if (standardPrice < 0) throw ArgumentError('Harga tidak boleh negatif.');
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      if (id == null) {
        final newId = await txn.insert('service_catalog', {'name': name.trim(), 'category': _clean(category), 'description': _clean(description), 'standard_price': standardPrice, 'is_active': 1, 'created_at': now, 'updated_at': now});
        await ActivityLogRepository.record(
          txn,
          action: 'service_catalog_created',
          description: 'Menambahkan master jasa ${name.trim()} dengan harga Rp$standardPrice.',
          entityType: 'service_catalog',
          entityId: newId,
        );
        return newId;
      }
      final old = await txn.query('service_catalog', columns: ['standard_price', 'name'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (old.isEmpty) throw StateError('Master jasa tidak ditemukan.');
      final oldPrice = old.first['standard_price'] as int? ?? 0;
      if (oldPrice != standardPrice && reason.trim().isEmpty) throw ArgumentError('Alasan perubahan harga wajib diisi.');
      await txn.update('service_catalog', {'name': name.trim(), 'category': _clean(category), 'description': _clean(description), 'standard_price': standardPrice, 'updated_at': now}, where: 'id = ?', whereArgs: [id]);
      if (oldPrice != standardPrice) {
        await txn.insert('service_price_history', {'service_id': id, 'old_price': oldPrice, 'new_price': standardPrice, 'change_reason': _clean(reason), 'changed_by': 'Admin', 'changed_at': now});
        await ActivityLogRepository.record(
          txn,
          action: 'service_price_changed',
          description: 'Mengubah harga jasa ${old.first['name']} dari Rp$oldPrice menjadi Rp$standardPrice. Alasan: ${reason.trim()}.',
          entityType: 'service_catalog',
          entityId: id,
        );
      } else {
        await ActivityLogRepository.record(
          txn,
          action: 'service_catalog_updated',
          description: 'Memperbarui master jasa ${name.trim()}.',
          entityType: 'service_catalog',
          entityId: id,
        );
      }
      return id;
    });
  }

  Future<void> deleteService(int id) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat menghapus master jasa.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'service_catalog',
        columns: ['id', 'name'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      // Hapus riwayat harga terkait agar foreign key RESTRICT tidak menghalangi.
      // Rincian nota servis lama tersimpan di service_order_items secara terpisah.
      await txn.delete(
        'service_price_history',
        where: 'service_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'service_catalog',
        where: 'id = ?',
        whereArgs: [id],
      );
      await ActivityLogRepository.record(
        txn,
        action: 'service_catalog_deleted',
        description: 'Menghapus master jasa ${rows.first['name']}.',
        entityType: 'service_catalog',
        entityId: id,
      );
    });
  }

  Future<void> setActive(int id, bool active) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah status master jasa.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query('service_catalog', columns: ['name'],
        where: 'id = ?', whereArgs: [id], limit: 1);
      final changed = await txn.update('service_catalog',
        {'is_active': active ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
      if (changed > 0) {
        await ActivityLogRepository.record(
          txn,
          action: active ? 'service_catalog_activated' : 'service_catalog_deactivated',
          description: '${active ? 'Mengaktifkan' : 'Menonaktifkan'} master jasa ${rows.isEmpty ? '#$id' : rows.first['name']}.',
          entityType: 'service_catalog',
          entityId: id,
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> getPriceHistory() async {
    AuthSession.instance.requireAdmin('Riwayat harga jasa hanya dapat diakses Admin.');
    final db = await _db;
    return db.rawQuery('SELECT h.*, s.name AS service_name FROM service_price_history h JOIN service_catalog s ON s.id = h.service_id ORDER BY h.id DESC LIMIT 300');
  }

  String? _clean(String? value) {
    final v = value?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}
