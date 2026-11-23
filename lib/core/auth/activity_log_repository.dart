import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import 'auth_session.dart';

class ActivityLogRepository {
  static Future<void> record(
    DatabaseExecutor executor, {
    required String action,
    required String description,
    String? entityType,
    int? entityId,
  }) async {
    final session = AuthSession.instance;
    await executor.insert('activity_logs', {
      'user_id': session.userId,
      'user_name': session.displayName ?? 'Tidak diketahui',
      'user_role': session.role ?? 'unknown',
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'description': description,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> getRecent({int limit = 300}) async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'activity_logs',
      orderBy: 'created_at DESC, id DESC',
      limit: limit.clamp(1, 1000).toInt(),
    );
  }
}
