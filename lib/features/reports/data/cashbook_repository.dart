import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class CashbookRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, Object?>> getLedger({
    required DateTime start,
    required DateTime end,
    String type = 'all',
  }) async {
    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    final openingRows = await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN transaction_type='income' THEN amount ELSE -amount END),0) AS balance
      FROM cash_transactions WHERE transaction_date < ?
    ''', [from]);
    final rows = await db.rawQuery('''
      SELECT * FROM cash_transactions
      WHERE transaction_date >= ? AND transaction_date < ?
        AND (?='all' OR transaction_type=?)
      ORDER BY transaction_date ASC, id ASC
    ''', [from, until, type, type]);
    var balance = (openingRows.first['balance'] as num?)?.toInt() ?? 0;
    var income = 0;
    var expense = 0;
    final entries = <Map<String, Object?>>[];
    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toInt() ?? 0;
      final isIncome = row['transaction_type'] == 'income';
      if (isIncome) {
        income += amount;
        balance += amount;
      } else {
        expense += amount;
        balance -= amount;
      }
      entries.add({...row, 'running_balance': balance});
    }
    return {
      'opening_balance': (openingRows.first['balance'] as num?)?.toInt() ?? 0,
      'income': income,
      'expense': expense,
      'closing_balance': balance,
      'entries': entries.reversed.toList(),
      'count': entries.length,
    };
  }

  Future<int> addManualTransaction({
    required String type,
    required String category,
    required String description,
    required int amount,
    DateTime? date,
  }) async {
    if (!['income', 'expense'].contains(type)) {
      throw ArgumentError('Jenis transaksi tidak valid.');
    }
    final cleanCategory = category.trim();
    final cleanDescription = description.trim();
    if (cleanCategory.isEmpty || cleanDescription.isEmpty || amount <= 0) {
      throw ArgumentError('Kategori, keterangan, dan nominal wajib diisi dengan benar.');
    }
    final db = await _db;
    return db.insert('cash_transactions', {
      'transaction_type': type,
      'category': cleanCategory,
      'description': cleanDescription,
      'amount': amount,
      'reference_type': 'manual_cash',
      'reference_id': null,
      'transaction_date': (date ?? DateTime.now()).toIso8601String(),
    });
  }
}
