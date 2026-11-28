import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

/// Durable, idempotent outbox for changes created on a Client device.
///
/// The caller must enqueue through the same [DatabaseExecutor] transaction
/// that writes the business record. This keeps the business change and its
/// sync event atomic.
class SyncOutboxRepository {
  SyncOutboxRepository({
    DateTime Function()? clock,
    this.leaseDuration = const Duration(minutes: 2),
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration leaseDuration;

  Future<Database> get _db => AppDatabase.instance.database;

  Future<int> enqueue(
    DatabaseExecutor executor, {
    required String eventId,
    required String entityType,
    required int entityId,
    required String operation,
    required Map<String, Object?> payload,
  }) async {
    final normalizedEventId = eventId.trim();
    final normalizedEntityType = entityType.trim();
    final normalizedOperation = operation.trim();
    if (normalizedEventId.isEmpty || normalizedEventId.length > 160) {
      throw ArgumentError('ID event sinkronisasi tidak valid.');
    }
    if (normalizedEntityType.isEmpty || normalizedEntityType.length > 60) {
      throw ArgumentError('Jenis data sinkronisasi tidak valid.');
    }
    if (entityId < 1) throw ArgumentError.value(entityId, 'entityId');
    if (normalizedOperation.isEmpty || normalizedOperation.length > 40) {
      throw ArgumentError('Operasi sinkronisasi tidak valid.');
    }

    final now = _clock().toUtc().toIso8601String();
    final payloadJson = jsonEncode(payload);
    await executor.insert(
      'sync_outbox',
      {
        'event_id': normalizedEventId,
        'entity_type': normalizedEntityType,
        'entity_id': entityId,
        'operation': normalizedOperation,
        'payload_json': payloadJson,
        'status': 'pending',
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    final rows = await executor.query(
      'sync_outbox',
      columns: ['id', 'payload_json', 'entity_type', 'entity_id', 'operation'],
      where: 'event_id = ?',
      whereArgs: [normalizedEventId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Event sinkronisasi gagal disimpan.');
    final saved = rows.single;
    if (saved['payload_json'] != payloadJson ||
        saved['entity_type'] != normalizedEntityType ||
        saved['entity_id'] != entityId ||
        saved['operation'] != normalizedOperation) {
      throw StateError('ID event sinkronisasi sudah dipakai untuk data berbeda.');
    }
    return saved['id'] as int;
  }

  /// Atomically leases a batch so concurrent workers cannot send it twice.
  /// Expired leases are returned to pending after an interrupted process.
  Future<List<Map<String, Object?>>> claimPending({int limit = 20}) async {
    if (limit < 1 || limit > 100) {
      throw ArgumentError.value(limit, 'limit', 'Harus 1 sampai 100.');
    }
    final db = await _db;
    final now = _clock().toUtc();
    final nowText = now.toIso8601String();
    final leaseUntil = now.add(leaseDuration).toIso8601String();

    return db.transaction((txn) async {
      await txn.update(
        'sync_outbox',
        {
          'status': 'pending',
          'lease_until': null,
          'updated_at': nowText,
        },
        where: "status = 'in_flight' AND lease_until <= ?",
        whereArgs: [nowText],
      );

      final rows = await txn.query(
        'sync_outbox',
        where: "status IN ('pending', 'failed') AND "
            "(next_attempt_at IS NULL OR next_attempt_at <= ?)",
        whereArgs: [nowText],
        orderBy: 'id ASC',
        limit: limit,
      );

      final claimed = <Map<String, Object?>>[];
      for (final row in rows) {
        final id = row['id'] as int;
        final changed = await txn.update(
          'sync_outbox',
          {
            'status': 'in_flight',
            'attempt_count': (row['attempt_count'] as int? ?? 0) + 1,
            'lease_until': leaseUntil,
            'updated_at': nowText,
          },
          where: "id = ? AND status IN ('pending', 'failed')",
          whereArgs: [id],
        );
        if (changed == 1) {
          claimed.add({
            ...row,
            'status': 'in_flight',
            'attempt_count': (row['attempt_count'] as int? ?? 0) + 1,
            'lease_until': leaseUntil,
            'updated_at': nowText,
          });
        }
      }
      return claimed;
    });
  }

  Future<void> markSynced(
    String eventId, {
    String? serverAckId,
  }) async {
    final db = await _db;
    final now = _clock().toUtc().toIso8601String();
    final changed = await db.update(
      'sync_outbox',
      {
        'status': 'synced',
        'server_ack_id': serverAckId,
        'lease_until': null,
        'last_error': null,
        'next_attempt_at': null,
        'synced_at': now,
        'updated_at': now,
      },
      where: "event_id = ? AND status = 'in_flight'",
      whereArgs: [eventId],
    );
    if (changed != 1) {
      throw StateError('Event tidak sedang diproses atau tidak ditemukan.');
    }
  }

  Future<void> markFailed(String eventId, String error) async {
    final db = await _db;
    final rows = await db.query(
      'sync_outbox',
      columns: ['attempt_count'],
      where: "event_id = ? AND status = 'in_flight'",
      whereArgs: [eventId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Event tidak sedang diproses atau tidak ditemukan.');
    }
    final attempts = rows.single['attempt_count'] as int? ?? 1;
    final exponent = (attempts - 1).clamp(0, 10).toInt();
    final delaySeconds = (5 * (1 << exponent)).clamp(5, 3600).toInt();
    final now = _clock().toUtc();
    final nextAttempt = now.add(Duration(seconds: delaySeconds));
    final normalizedError = error.trim();
    final changed = await db.update(
      'sync_outbox',
      {
        'status': 'failed',
        'lease_until': null,
        'last_error': normalizedError.isEmpty
            ? 'Kesalahan sinkronisasi tidak diketahui.'
            : normalizedError.substring(
                0,
                normalizedError.length > 500 ? 500 : normalizedError.length,
              ),
        'next_attempt_at': nextAttempt.toIso8601String(),
        'updated_at': now.toIso8601String(),
      },
      where: "event_id = ? AND status = 'in_flight'",
      whereArgs: [eventId],
    );
    if (changed != 1) {
      throw StateError('Status event berubah sebelum kegagalan disimpan.');
    }
  }

  Future<Map<String, int>> getCounts() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS total FROM sync_outbox GROUP BY status',
    );
    final counts = <String, int>{
      'pending': 0,
      'in_flight': 0,
      'failed': 0,
      'synced': 0,
    };
    for (final row in rows) {
      final status = row['status']?.toString();
      if (status != null && counts.containsKey(status)) {
        counts[status] = (row['total'] as num?)?.toInt() ?? 0;
      }
    }
    return counts;
  }
}
