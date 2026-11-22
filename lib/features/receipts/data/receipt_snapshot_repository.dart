import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class ReceiptSnapshotRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<int> createSnapshot({
    required String documentType,
    required String sourceType,
    required int sourceId,
    required String documentNumber,
    required Map<String, Object?> payload,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    return db.insert('receipt_snapshots', {
      'document_type': documentType,
      'source_type': sourceType,
      'source_id': sourceId,
      'document_number': documentNumber,
      'snapshot_json': jsonEncode(payload),
      'issued_at': now,
      'created_at': now,
    });
  }

  Future<Map<String, Object?>?> getSnapshot(int id) async {
    final db = await _db;
    final rows = await db.query(
      'receipt_snapshots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final decoded = jsonDecode(row['snapshot_json'] as String);
    if (decoded is! Map) {
      throw const FormatException('Data snapshot nota tidak valid.');
    }
    return {
      ...row,
      'payload': Map<String, Object?>.from(decoded),
    };
  }

  Future<List<Map<String, Object?>>> getHistory({
    String? sourceType,
    int? sourceId,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (sourceType != null) {
      where.add('source_type = ?');
      args.add(sourceType);
    }
    if (sourceId != null) {
      where.add('source_id = ?');
      args.add(sourceId);
    }
    return db.query(
      'receipt_snapshots',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'issued_at DESC, id DESC',
      limit: 300,
    );
  }
}
