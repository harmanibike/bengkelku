import '../../../core/database/app_database.dart';

class BusinessStoryRepository {
  Future<int> save({
    required String kind,
    required String title,
    required String message,
    required String dateLabel,
    required String returnDateLabel,
    required String template,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.insert('business_story_history', {
      'kind': kind,
      'title': title.trim(),
      'message': message.trim(),
      'date_label': dateLabel.trim(),
      'return_date_label': returnDateLabel.trim(),
      'template': template,
    });
  }

  Future<List<Map<String, Object?>>> getAll() async {
    final db = await AppDatabase.instance.database;
    return db.query(
      'business_story_history',
      orderBy: 'created_at DESC, id DESC',
      limit: 100,
    );
  }

  Future<void> delete(int id) async {
    final db = await AppDatabase.instance.database;
    await db.delete(
      'business_story_history',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
