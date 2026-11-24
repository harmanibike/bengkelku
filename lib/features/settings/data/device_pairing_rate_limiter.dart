import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

/// Pembatasan percobaan pairing berbasis alamat IP sumber koneksi.
/// Panggil [isAllowed] sebelum memproses pairing, [recordFailure] hanya
/// setelah pertukaran kode gagal, dan [clearAfterSuccess] setelah berhasil.
class DevicePairingRateLimiter {
  DevicePairingRateLimiter({
    DateTime Function()? clock,
    this.maxFailures = 5,
    this.window = const Duration(minutes: 15),
    this.lockout = const Duration(minutes: 15),
  }) : _clock = clock ?? DateTime.now {
    if (maxFailures < 1 || window <= Duration.zero || lockout <= Duration.zero) {
      throw ArgumentError('Konfigurasi rate limit harus bernilai positif.');
    }
  }

  final DateTime Function() _clock;
  final int maxFailures;
  final Duration window;
  final Duration lockout;

  Future<Database> get _db => AppDatabase.instance.database;

  String _normalizeAddress(String value) {
    final address = InternetAddress.tryParse(value.trim());
    if (address == null) {
      throw ArgumentError.value(value, 'clientAddress', 'Alamat IP tidak valid.');
    }
    return address.address;
  }

  /// False berarti alamat IP masih dalam masa pemblokiran.
  Future<bool> isAllowed(String clientAddress) async {
    final address = _normalizeAddress(clientAddress);
    final db = await _db;
    final now = _clock().toUtc();
    final rows = await db.query(
      'device_pairing_attempt_limits',
      columns: ['blocked_until'],
      where: 'client_address = ?',
      whereArgs: [address],
      limit: 1,
    );
    if (rows.isEmpty) return true;
    final blockedUntil = rows.single['blocked_until'] as String?;
    if (blockedUntil == null) return true;
    return !DateTime.parse(blockedUntil).isAfter(now);
  }

  /// Catat kegagalan. Percobaan ke-[maxFailures] memulai masa lockout.
  Future<void> recordFailure(String clientAddress) async {
    final address = _normalizeAddress(clientAddress);
    final db = await _db;
    final now = _clock().toUtc();
    final nowIso = now.toIso8601String();

    await db.transaction((txn) async {
      final rows = await txn.query(
        'device_pairing_attempt_limits',
        where: 'client_address = ?',
        whereArgs: [address],
        limit: 1,
      );

      if (rows.isEmpty) {
        await txn.insert('device_pairing_attempt_limits', {
          'client_address': address,
          'window_started_at': nowIso,
          'failed_attempts': 1,
        });
        return;
      }

      final row = rows.single;
      final windowStartedAt = DateTime.parse(row['window_started_at'] as String);
      final blockedUntil = row['blocked_until'] as String?;
      final windowExpired = !now.isBefore(windowStartedAt.add(window));
      final lockoutExpired = blockedUntil != null &&
          !DateTime.parse(blockedUntil).isAfter(now);

      if (windowExpired || lockoutExpired) {
        await txn.update(
          'device_pairing_attempt_limits',
          {
            'window_started_at': nowIso,
            'failed_attempts': 1,
            'blocked_until': null,
          },
          where: 'client_address = ?',
          whereArgs: [address],
        );
        return;
      }

      final failures = (row['failed_attempts'] as int) + 1;
      await txn.update(
        'device_pairing_attempt_limits',
        {
          'failed_attempts': failures,
          if (failures >= maxFailures)
            'blocked_until': now.add(lockout).toIso8601String(),
        },
        where: 'client_address = ?',
        whereArgs: [address],
      );
    });
  }

  /// Hapus hitungan setelah pairing valid agar perangkat tidak ikut terkunci.
  Future<void> clearAfterSuccess(String clientAddress) async {
    final address = _normalizeAddress(clientAddress);
    final db = await _db;
    await db.delete(
      'device_pairing_attempt_limits',
      where: 'client_address = ?',
      whereArgs: [address],
    );
  }
}
