import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class LoyaltyRewardRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getRewards({bool includeInactive = true}) async {
    AuthSession.instance.requireCashierOrAdmin('Akun ini tidak memiliki akses reward.');
    final db = await _db;
    return db.query(
      'loyalty_rewards',
      where: includeInactive ? null : 'is_active = 1',
      orderBy: 'points_cost ASC, name COLLATE NOCASE ASC',
    );
  }

  Future<List<Map<String, Object?>>> getCustomers() async {
    AuthSession.instance.requireCashierOrAdmin('Akun ini tidak memiliki akses pelanggan.');
    final db = await _db;
    return db.rawQuery('''
      SELECT c.id, c.name, c.phone,
        COALESCE((SELECT SUM(l.points) FROM loyalty_point_ledger l
          WHERE l.customer_id = c.id), 0) AS points
      FROM customers c
      ORDER BY c.name COLLATE NOCASE ASC
    ''');
  }

  Future<void> saveReward({
    int? id,
    required String name,
    required String type,
    required int pointsCost,
    String? description,
  }) async {
    if (!AuthSession.instance.isAdmin) {
      throw StateError('Hanya Admin yang dapat mengelola katalog reward.');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty || pointsCost <= 0) {
      throw ArgumentError('Nama reward dan biaya poin harus valid.');
    }
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final values = <String, Object?>{
      'name': cleanName,
      'reward_type': type,
      'points_cost': pointsCost,
      'description': description?.trim(),
      'updated_at': now,
    };
    if (id == null) {
      values['created_at'] = now;
      values['is_active'] = 1;
      await db.insert('loyalty_rewards', values);
    } else {
      await db.update('loyalty_rewards', values, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<void> setRewardActive(int id, bool active) async {
    if (!AuthSession.instance.isAdmin) {
      throw StateError('Hanya Admin yang dapat mengelola katalog reward.');
    }
    final db = await _db;
    await db.update('loyalty_rewards', {
      'is_active': active ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> redeem({
    required int customerId,
    required int rewardId,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Akun ini tidak memiliki akses penukaran reward.');
    final db = await _db;
    await db.transaction((txn) async {
      final rewards = await txn.query(
        'loyalty_rewards',
        where: 'id = ? AND is_active = 1',
        whereArgs: [rewardId],
        limit: 1,
      );
      if (rewards.isEmpty) throw StateError('Reward tidak tersedia atau sudah dinonaktifkan.');
      final reward = rewards.first;
      final cost = reward['points_cost'] as int;
      final customers = await txn.query(
        'customers',
        columns: ['id', 'name'],
        where: 'id = ?',
        whereArgs: [customerId],
        limit: 1,
      );
      if (customers.isEmpty) throw StateError('Pelanggan tidak ditemukan.');
      final balance = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COALESCE(SUM(points), 0) FROM loyalty_point_ledger WHERE customer_id = ?',
        [customerId],
      )) ?? 0;
      if (balance < cost) {
        throw StateError('Poin pelanggan tidak cukup. Saldo saat ini: $balance poin.');
      }

      final now = DateTime.now().toIso8601String();
      final redemptionId = await txn.insert('loyalty_redemptions', {
        'customer_id': customerId,
        'reward_id': rewardId,
        'reward_name': reward['name'],
        'points_spent': cost,
        'status': 'completed',
        'created_at': now,
      });
      await txn.insert('loyalty_point_ledger', {
        'customer_id': customerId,
        'reference_type': 'reward_redemption',
        'reference_id': redemptionId,
        'entry_type': 'redeem',
        'points': -cost,
        'eligible_amount': 0,
        'description': 'Penukaran reward: ${reward['name']}',
        'created_at': now,
      });
    });
  }

  Future<List<Map<String, Object?>>> getRedemptionHistory({int? customerId}) async {
    AuthSession.instance.requireCashierOrAdmin('Akun ini tidak memiliki akses riwayat reward.');
    final db = await _db;
    return db.query(
      'loyalty_redemptions',
      where: customerId == null ? null : 'customer_id = ?',
      whereArgs: customerId == null ? null : [customerId],
      orderBy: 'created_at DESC, id DESC',
      limit: 100,
    );
  }
}
