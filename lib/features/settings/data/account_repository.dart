import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class AccountRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  static const roles = ['admin', 'cashier', 'mechanic'];

  String _hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  String _newSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<bool> hasAccounts() async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM app_users');
    return Sqflite.firstIntValue(rows) != 0;
  }

  Future<int> createAccount({
    required String displayName,
    required String username,
    required String pin,
    required String role,
  }) async {
    final name = displayName.trim();
    final login = username.trim();
    if (name.isEmpty || login.isEmpty) throw ArgumentError('Nama dan username wajib diisi.');
    if (!roles.contains(role)) throw ArgumentError('Peran akun tidak valid.');
    if (!RegExp(r'^\d{6,8}).hasMatch(pin)) throw ArgumentError('PIN harus 6–8 digit.');
    final db = await _db;
    final salt = _newSalt();
    return db.insert('app_users', {
      'display_name': name,
      'username': login,
      'role': role,
      'pin_hash': '$salt:${_hashPin(pin, salt)}',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, Object?>?> authenticate({
    required String username,
    required String pin,
  }) async {
    final db = await _db;
    final rows = await db.query('app_users',
        where: 'username = ? COLLATE NOCASE AND is_active = 1',
        whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final user = rows.first;
    final stored = user['pin_hash']?.toString() ?? '';
    final separator = stored.indexOf(':');
    if (separator <= 0) return null;
    final salt = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    if (_hashPin(pin, salt) != expected) return null;
    return {
      'id': user['id'],
      'display_name': user['display_name'],
      'username': user['username'],
      'role': user['role'],
    };
  }

  Future<List<Map<String, Object?>>> getAccounts() async {
    final db = await _db;
    return db.query('app_users',
        columns: ['id', 'display_name', 'username', 'role', 'is_active', 'created_at'],
        orderBy: "CASE role WHEN 'admin' THEN 0 WHEN 'cashier' THEN 1 ELSE 2 END, display_name COLLATE NOCASE");
  }

  Future<int> setAccountActive({required int id, required bool active}) async {
    final db = await _db;
    if (!active) {
      final rows = await db.query('app_users', where: "id = ? AND role = 'admin' AND is_active = 1", whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) {
        final admins = await db.rawQuery("SELECT COUNT(*) AS total FROM app_users WHERE role = 'admin' AND is_active = 1");
        if ((Sqflite.firstIntValue(admins) ?? 0) <= 1) {
          throw StateError('Minimal satu akun Admin harus tetap aktif.');
        }
      }
    }
    return db.update('app_users', {
      'is_active': active ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> resetPin({required int id, required String newPin}) async {
    if (!RegExp(r'^\\d{6,8}$').hasMatch(newPin)) throw ArgumentError('PIN harus 6–8 digit.');
    final db = await _db;
    final salt = _newSalt();
    return db.update('app_users', {
      'pin_hash': '$salt:${_hashPin(newPin, salt)}',
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }
}
).hasMatch(pin)) throw ArgumentError('PIN harus 6–8 digit.');
    final db = await _db;
    final salt = _newSalt();
    return db.insert('app_users', {
      'display_name': name,
      'username': login,
      'role': role,
      'pin_hash': '$salt:${_hashPin(pin, salt)}',
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, Object?>?> authenticate({
    required String username,
    required String pin,
  }) async {
    final db = await _db;
    final rows = await db.query('app_users',
        where: 'username = ? COLLATE NOCASE AND is_active = 1',
        whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final user = rows.first;
    final stored = user['pin_hash']?.toString() ?? '';
    final separator = stored.indexOf(':');
    if (separator <= 0) return null;
    final salt = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    if (_hashPin(pin, salt) != expected) return null;
    return {
      'id': user['id'],
      'display_name': user['display_name'],
      'username': user['username'],
      'role': user['role'],
    };
  }

  Future<List<Map<String, Object?>>> getAccounts() async {
    final db = await _db;
    return db.query('app_users',
        columns: ['id', 'display_name', 'username', 'role', 'is_active', 'created_at'],
        orderBy: "CASE role WHEN 'admin' THEN 0 WHEN 'cashier' THEN 1 ELSE 2 END, display_name COLLATE NOCASE");
  }

  Future<int> setAccountActive({required int id, required bool active}) async {
    final db = await _db;
    if (!active) {
      final rows = await db.query('app_users', where: "id = ? AND role = 'admin' AND is_active = 1", whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) {
        final admins = await db.rawQuery("SELECT COUNT(*) AS total FROM app_users WHERE role = 'admin' AND is_active = 1");
        if ((Sqflite.firstIntValue(admins) ?? 0) <= 1) {
          throw StateError('Minimal satu akun Admin harus tetap aktif.');
        }
      }
    }
    return db.update('app_users', {
      'is_active': active ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> resetPin({required int id, required String newPin}) async {
    if (!RegExp(r'^\d{6,8}).hasMatch(newPin)) throw ArgumentError('PIN harus 6–8 digit.');
    final db = await _db;
    final salt = _newSalt();
    return db.update('app_users', {
      'pin_hash': '$salt:${_hashPin(newPin, salt)}',
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }
}
).hasMatch(newPin)) throw ArgumentError('PIN harus 6–8 digit.');
    final db = await _db;
    final salt = _newSalt();
    return db.update('app_users', {
      'pin_hash': '$salt:${_hashPin(newPin, salt)}',
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }
}
