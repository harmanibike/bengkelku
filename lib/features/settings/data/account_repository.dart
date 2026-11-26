import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/auth/activity_log_repository.dart';

class AccountRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  static const roles = ['admin', 'cashier', 'mechanic'];

  static const int _pinHashIterations = 120000;

  String _hashLegacyPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  String _hashPin(String pin, String salt, {int iterations = _pinHashIterations}) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    var block = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
    final derived = List<int>.from(block);
    for (var round = 1; round < iterations; round++) {
      block = hmac.convert(block).bytes;
      for (var index = 0; index < derived.length; index++) {
        derived[index] ^= block[index];
      }
    }
    return base64Url.encode(derived).replaceAll('=', '');
  }

  String _encodePinHash(String pin, String salt) =>
      'pbkdf2_sha256:$_pinHashIterations:$salt:${_hashPin(pin, salt)}';

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }

  String _newSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  bool _validPin(String pin) => RegExp(r'^[0-9]{6,8}$').hasMatch(pin);

  Future<bool> hasAccounts() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM app_users');
    return (Sqflite.firstIntValue(rows) ?? 0) > 0;
  }

  Future<int> createAccount({
    required String displayName,
    required String username,
    required String pin,
    required String role,
  }) async {
    final name = displayName.trim();
    final login = username.trim();
    if (name.isEmpty || login.isEmpty) {
      throw ArgumentError('Nama dan username wajib diisi.');
    }
    if (!roles.contains(role)) {
      throw ArgumentError('Peran akun tidak valid.');
    }
    if (!_validPin(pin)) {
      throw ArgumentError('PIN harus 6–8 digit.');
    }

    final db = await _db;
    return db.transaction((txn) async {
      final count = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM app_users')) ?? 0;
      if (count == 0 && role != 'admin') {
        throw StateError('Akun pertama harus Admin.');
      }
      if (count > 0 && !AuthSession.instance.isAdmin) {
        throw StateError('Hanya Admin yang dapat membuat akun baru.');
      }
      final salt = _newSalt();
      final id = await txn.insert('app_users', {
        'display_name': name,
        'username': login,
        'role': role,
        'pin_hash': _encodePinHash(pin, salt),
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      await ActivityLogRepository.record(
        txn,
        action: 'account_created',
        description: 'Membuat akun $role untuk $name ($login).',
        entityType: 'app_user',
        entityId: id,
      );
      return id;
    });
  }

  Future<Map<String, Object?>?> authenticate({
    required String username,
    required String pin,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'app_users',
      where: 'username = ? COLLATE NOCASE AND is_active = 1',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final user = rows.first;
    final stored = user['pin_hash']?.toString() ?? '';
    if (stored.startsWith('pbkdf2_sha256:')) {
      final parts = stored.split(':');
      if (parts.length != 4) return null;
      final iterations = int.tryParse(parts[1]);
      if (iterations == null || iterations < 10000 || iterations > 500000) {
        return null;
      }
      final actual = _hashPin(pin, parts[2], iterations: iterations);
      if (!_constantTimeEquals(actual, parts[3])) return null;
    } else {
      // Hash SHA-256 lama tetap diterima agar pengguna tidak terkunci setelah
      // pembaruan. Setelah PIN benar, hash langsung ditingkatkan.
      final separator = stored.indexOf(':');
      if (separator <= 0) return null;
      final salt = stored.substring(0, separator);
      final expected = stored.substring(separator + 1);
      if (!_constantTimeEquals(_hashLegacyPin(pin, salt), expected)) {
        return null;
      }
      await db.update(
        'app_users',
        {
          'pin_hash': _encodePinHash(pin, _newSalt()),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [user['id']],
      );
    }

    return {
      'id': user['id'],
      'display_name': user['display_name'],
      'username': user['username'],
      'role': user['role'],
      'phone': user['phone'],
      'profile_photo_path': user['profile_photo_path'],
    };
  }

  /// Memulihkan sesi hanya untuk akun yang masih aktif.
  /// PIN tidak disimpan; profil dan peran dibaca ulang dari database.
  Future<Map<String, Object?>?> getActiveAccountById(int id) async {
    final db = await _db;
    final rows = await db.query(
      'app_users',
      columns: ['id', 'display_name', 'username', 'role', 'phone', 'profile_photo_path'],
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>> getCurrentProfile() async {
    final id = AuthSession.instance.userId;
    if (id == null) throw StateError('Tidak ada akun yang sedang login.');
    final db = await _db;
    final rows = await db.query(
      'app_users',
      columns: ['id', 'display_name', 'username', 'role', 'phone', 'profile_photo_path'],
      where: 'id = ? AND is_active = 1',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Akun tidak ditemukan atau sudah nonaktif.');
    return rows.first;
  }

  Future<void> updateOwnProfile({
    required String displayName,
    required String username,
    required String phone,
    required String profilePhotoPath,
  }) async {
    final id = AuthSession.instance.userId;
    if (id == null) throw StateError('Tidak ada akun yang sedang login.');
    final name = displayName.trim();
    final login = username.trim();
    if (name.isEmpty || login.isEmpty) {
      throw ArgumentError('Nama dan username wajib diisi.');
    }
    final db = await _db;
    await db.transaction((txn) async {
      final changed = await txn.update(
        'app_users',
        {
          'display_name': name,
          'username': login,
          'phone': phone.trim(),
          'profile_photo_path': profilePhotoPath.trim(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ? AND is_active = 1',
        whereArgs: [id],
      );
      if (changed == 0) throw StateError('Akun tidak ditemukan atau nonaktif.');
      await ActivityLogRepository.record(
        txn,
        action: 'account_profile_updated',
        description: 'Memperbarui profil akun $name ($login).',
        entityType: 'app_user',
        entityId: id,
      );
    });
    final profile = await getCurrentProfile();
    AuthSession.instance.signIn(profile);
  }

  Future<void> changeOwnPin({
    required String currentPin,
    required String newPin,
  }) async {
    final id = AuthSession.instance.userId;
    final username = AuthSession.instance.user?['username']?.toString() ?? '';
    if (id == null || username.isEmpty) {
      throw StateError('Tidak ada akun yang sedang login.');
    }
    if (!_validPin(newPin)) throw ArgumentError('PIN baru harus 6–8 digit.');
    final verified = await authenticate(username: username, pin: currentPin);
    if (verified == null || verified['id'] != id) {
      throw StateError('PIN saat ini salah.');
    }
    final db = await _db;
    final salt = _newSalt();
    await db.transaction((txn) async {
      await txn.update(
        'app_users',
        {
          'pin_hash': _encodePinHash(newPin, salt),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await ActivityLogRepository.record(
        txn,
        action: 'account_pin_changed',
        description: 'Mengganti PIN akun sendiri.',
        entityType: 'app_user',
        entityId: id,
      );
    });
  }

  Future<List<Map<String, Object?>>> getAccounts() async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat melihat daftar akun.');
    final db = await _db;
    return db.query(
      'app_users',
      columns: [
        'id',
        'display_name',
        'username',
        'role',
        'is_active',
        'created_at',
      ],
      orderBy:
          "CASE role WHEN 'admin' THEN 0 WHEN 'cashier' THEN 1 ELSE 2 END, display_name COLLATE NOCASE",
    );
  }

  /// Daftar akun mekanik aktif untuk penugasan servis.
  /// Kasir boleh membaca nama mekanik, tetapi tidak dapat mengelola akun.
  Future<List<Map<String, Object?>>> getActiveMechanics() async {
    AuthSession.instance.requireCashierOrAdmin(
      'Hanya Admin dan Kasir yang dapat melihat daftar mekanik.',
    );
    final db = await _db;
    return db.query(
      'app_users',
      columns: ['id', 'display_name', 'role', 'is_active'],
      where: 'role = ? AND is_active = ?',
      whereArgs: ['mechanic', 1],
      orderBy: 'display_name COLLATE NOCASE',
    );
  }

  Future<int> setAccountActive({
    required int id,
    required bool active,
  }) async {
    if (!AuthSession.instance.isAdmin) {
      throw StateError('Hanya Admin yang dapat mengubah status akun.');
    }
    if (!active && AuthSession.instance.userId == id) {
      throw StateError('Admin yang sedang login tidak dapat menonaktifkan akunnya sendiri.');
    }
    final db = await _db;
    if (!active) {
      final rows = await db.query(
        'app_users',
        where: "id = ? AND role = 'admin' AND is_active = 1",
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final admins = await db.rawQuery(
          "SELECT COUNT(*) AS total FROM app_users WHERE role = 'admin' AND is_active = 1",
        );
        if ((Sqflite.firstIntValue(admins) ?? 0) <= 1) {
          throw StateError('Minimal satu akun Admin harus tetap aktif.');
        }
      }
    }

    return db.transaction((txn) async {
      final accountRows = await txn.query('app_users',
        columns: ['display_name', 'username', 'role'],
        where: 'id = ?', whereArgs: [id], limit: 1);
      final changed = await txn.update(
        'app_users',
        {
          'is_active': active ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed > 0) {
        final account = accountRows.isEmpty ? null : accountRows.first;
        await ActivityLogRepository.record(
          txn,
          action: active ? 'account_activated' : 'account_deactivated',
          description: '${active ? 'Mengaktifkan' : 'Menonaktifkan'} akun ${account?['display_name'] ?? '#$id'} (${account?['username'] ?? '-'}) dengan peran ${account?['role'] ?? '-'}.' ,
          entityType: 'app_user',
          entityId: id,
        );
      }
      return changed;
    });
  }

  Future<int> resetPin({
    required int id,
    required String newPin,
  }) async {
    if (!AuthSession.instance.isAdmin) {
      throw StateError('Hanya Admin yang dapat mengatur ulang PIN akun.');
    }
    if (!_validPin(newPin)) {
      throw ArgumentError('PIN harus 6–8 digit.');
    }
    final db = await _db;
    final salt = _newSalt();
    return db.transaction((txn) async {
      final rows = await txn.query('app_users',
        columns: ['display_name', 'username'],
        where: 'id = ?', whereArgs: [id], limit: 1);
      final changed = await txn.update(
        'app_users',
        {
          'pin_hash': _encodePinHash(newPin, salt),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed > 0) {
        await ActivityLogRepository.record(
          txn,
          action: 'account_pin_reset',
          description: 'Mereset PIN akun ${rows.isEmpty ? '#$id' : rows.first['display_name']} (${rows.isEmpty ? '-' : rows.first['username']}).',
          entityType: 'app_user',
          entityId: id,
        );
      }
      return changed;
    });
  }
}
