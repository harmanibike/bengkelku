import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class ReportRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, Object?>> getSummary({required DateTime start, required DateTime end}) async {
    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();

    final cash = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) AS expense,
        COUNT(*) AS transaction_count
      FROM cash_transactions
      WHERE transaction_date >= ? AND transaction_date < ?
    ''', [from, until]);

    final sales = await db.rawQuery('''
      SELECT COUNT(*) AS total, COALESCE(SUM(total), 0) AS amount
      FROM sales
      WHERE transaction_date >= ? AND transaction_date < ?
        AND COALESCE(payment_status, 'paid') != 'cancelled'
    ''', [from, until]);

    final saleReturns = await db.rawQuery('''
      SELECT COUNT(*) AS total, COALESCE(SUM(total_amount), 0) AS amount
      FROM sale_returns
      WHERE return_date >= ? AND return_date < ?
    ''', [from, until]);

    final services = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM service_orders WHERE received_at >= ? AND received_at < ?
    ''', [from, until]);

    final lowStock = await db.rawQuery('''
      SELECT COUNT(*) AS total FROM products
      WHERE is_active = 1 AND track_stock = 1 AND stock <= minimum_stock
    ''');

    final categories = await db.rawQuery('''
      SELECT COALESCE(category, 'Lainnya') AS category,
             SUM(amount) AS amount,
             transaction_type
      FROM cash_transactions
      WHERE transaction_date >= ? AND transaction_date < ?
      GROUP BY category, transaction_type
      ORDER BY amount DESC
    ''', [from, until]);

    final latest = await db.query(
      'cash_transactions',
      where: 'transaction_date >= ? AND transaction_date < ?',
      whereArgs: [from, until],
      orderBy: 'transaction_date DESC, id DESC',
      limit: 20,
    );

    return {
      'income': cash.first['income'] as int? ?? 0,
      'expense': cash.first['expense'] as int? ?? 0,
      'transaction_count': cash.first['transaction_count'] as int? ?? 0,
      'sales_count': sales.first['total'] as int? ?? 0,
      'sales_amount': sales.first['amount'] as int? ?? 0,\n      'sales_return_count': saleReturns.first['total'] as int? ?? 0,\n      'sales_return_amount': saleReturns.first['amount'] as int? ?? 0,\n      'net_sales_amount': (sales.first['amount'] as int? ?? 0) - (saleReturns.first['amount'] as int? ?? 0),
      'service_count': services.first['total'] as int? ?? 0,
      'low_stock': lowStock.first['total'] as int? ?? 0,
      'categories': categories,
      'latest': latest,
    };
  }
}
