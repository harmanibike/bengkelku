import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class DevicePairingCode {
  const DevicePairingCode({
    required this.code,
    required this.expiresAt,
  });

  /// Kode mentah hanya ditampilkan sekali kepada Admin.
  final String code;
  final DateTime expiresAt;
}

class PairedDeviceCredential {
  const PairedDeviceCredential({
    required this.deviceId,
    required this.deviceName,
    required this.token,
  });

  /// Token mentah hanya dikembalikan saat pairing berhasil.
  final String token;
  final int deviceId;
  final String deviceName;
}

class PairedDeviceInfo {
  const PairedDeviceInfo({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    this.lastSeenAt,
  });

  final int id;
  final String deviceName;
  final String createdAt;
  final String? lastSeenAt;
}

/// Fondasi identitas perangkat Server-Client.
/// Kode pairing sekali pakai dan token perangkat tidak pernah disimpan mentah.
class DevicePairingRepository {
  DevicePairingRepository({
    Random? random,
    DateTime Function()? clock,
  })  : _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  Future<Database> get _db => AppDatabase.instance.database;

  String _sha256(String value) => sha256.convert(value.codeUnits).toString();

  String _randomToken() {
    final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<DevicePairingCode> createPairingCode({
    Duration lifetime = const Duration(minutes: 3),
  }) async {
    AuthSession.instance.requireAdmin(
      'Hanya Admin yang dapat membuat kode pairing perangkat.',
    );
    if (lifetime <= Duration.zero || lifetime > const Duration(minutes: 10)) {
      throw ArgumentError('Masa berlaku kode harus lebih dari 0 dan maksimal 10 menit.');
    }

    final db = await _db;
    final now = _clock().toUtc();
    final expiresAt = now.add(lifetime);
    await db.delete(
      'device_pairing_codes',
      where: 'expires_at <= ? OR consumed_at IS NOT NULL',
      whereArgs: [now.toIso8601String()],
    );

    // Kode 10 digit memberi ruang tebak yang jauh lebih besar dibanding PIN kasir.
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = '${_random.nextInt(9) + 1}' +
          List.generate(9, (_) => _random.nextInt(10)).join();
      try {
        await db.insert('device_pairing_codes', {
          'code_hash': _sha256(code),
          'expires_at': expiresAt.toIso8601String(),
          'created_at': now.toIso8601String(),
        });
        return DevicePairingCode(code: code, expiresAt: expiresAt);
      } on DatabaseException catch (error) {
        if (!error.isUniqueConstraintError() || attempt == 4) rethrow;
      }
    }
    throw StateError('Tidak dapat membuat kode pairing unik.');
  }

  /// Menukar kode pairing valid menjadi token perangkat sekali saja.
  /// Endpoint jaringan nantinya memanggil metode ini tanpa sesi Admin Client.
  Future<PairedDeviceCredential> pairDevice({
    required String code,
    required String deviceName,
  }) async {
    final normalizedCode = code.trim();
    final normalizedName = deviceName.trim();
    if (!RegExp(r'^\d{10}$').hasMatch(normalizedCode)) {
      throw ArgumentError('Kode pairing harus terdiri dari 10 angka.');
    }
    if (normalizedName.isEmpty || normalizedName.length > 60) {
      throw ArgumentError('Nama perangkat wajib diisi (maksimal 60 karakter).');
    }

    final db = await _db;
    final now = _clock().toUtc();
    final token = _randomToken();
    final tokenHash = _sha256(token);

    return db.transaction((txn) async {
      final rows = await txn.query(
        'device_pairing_codes',
        columns: ['id'],
        where: 'code_hash = ? AND consumed_at IS NULL AND expires_at > ?',
        whereArgs: [_sha256(normalizedCode), now.toIso8601String()],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Kode pairing salah, kedaluwarsa, atau sudah digunakan.');
      }

      final codeId = rows.single['id'] as int;
      final consumed = await txn.update(
        'device_pairing_codes',
        {'consumed_at': now.toIso8601String()},
        where: 'id = ? AND consumed_at IS NULL AND expires_at > ?',
        whereArgs: [codeId, now.toIso8601String()],
      );
      if (consumed != 1) {
        throw StateError('Kode pairing sudah digunakan oleh perangkat lain.');
      }

      final deviceId = await txn.insert('paired_devices', {
        'device_name': normalizedName,
        'token_hash': tokenHash,
        'created_at': now.toIso8601String(),
      });
      return PairedDeviceCredential(
        deviceId: deviceId,
        deviceName: normalizedName,
        token: token,
      );
    });
  }

  /// Memvalidasi token dan memperbarui waktu terakhir perangkat terlihat.
  Future<PairedDeviceInfo?> authenticateDevice(String token) async {
    final normalizedToken = token.trim();
    if (normalizedToken.length != 64 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(normalizedToken)) {
      return null;
    }

    final db = await _db;
    final now = _clock().toUtc().toIso8601String();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'paired_devices',
        columns: ['id', 'device_name', 'created_at'],
        where: 'token_hash = ? AND revoked_at IS NULL',
        whereArgs: [_sha256(normalizedToken.toLowerCase())],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      await txn.update(
        'paired_devices',
        {'last_seen_at': now},
        where: 'id = ? AND revoked_at IS NULL',
        whereArgs: [row['id']],
      );
      return PairedDeviceInfo(
        id: row['id'] as int,
        deviceName: row['device_name'] as String,
        createdAt: row['created_at'] as String,
        lastSeenAt: now,
      );
    });
  }

  Future<List<PairedDeviceInfo>> getPairedDevices() async {
    AuthSession.instance.requireAdmin(
      'Hanya Admin yang dapat melihat perangkat terhubung.',
    );
    final db = await _db;
    final rows = await db.query(
      'paired_devices',
      columns: ['id', 'device_name', 'created_at', 'last_seen_at'],
      where: 'revoked_at IS NULL',
      orderBy: 'created_at DESC, id DESC',
    );
    return rows
        .map((row) => PairedDeviceInfo(
              id: row['id'] as int,
              deviceName: row['device_name'] as String,
              createdAt: row['created_at'] as String,
              lastSeenAt: row['last_seen_at'] as String?,
            ))
        .toList(growable: false);
  }

  Future<void> revokeDevice(int deviceId) async {
    AuthSession.instance.requireAdmin(
      'Hanya Admin yang dapat memutus perangkat Client.',
    );
    if (deviceId < 1) throw ArgumentError.value(deviceId, 'deviceId');
    final db = await _db;
    final changed = await db.update(
      'paired_devices',
      {'revoked_at': _clock().toUtc().toIso8601String()},
      where: 'id = ? AND revoked_at IS NULL',
      whereArgs: [deviceId],
    );
    if (changed == 0) {
      throw StateError('Perangkat tidak ditemukan atau sudah diputus.');
    }
  }
}
