import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class PurchaseReportRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, Object?>> getReport({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    final purchases = await db.rawQuery('''
      SELECT COUNT(*) AS count,
        COALESCE(SUM(total), 0) AS total_amount,
        COALESCE(SUM(paid), 0) AS recorded_paid,
        COALESCE(SUM(total - paid), 0) AS outstanding
      FROM purchases
      WHERE purchase_date >= ? AND purchase_date < ?
    ''', [from, until]);
    final returns = await db.rawQuery('''
      SELECT COUNT(*) AS count, COALESCE(SUM(total_amount), 0) AS amount
      FROM purchase_returns
      WHERE return_date >= ? AND return_date < ?
    ''', [from, until]);
    final payments = await db.rawQuery('''
      SELECT COUNT(*) AS count, COALESCE(SUM(amount), 0) AS amount
      FROM supplier_payments
      WHERE payment_date >= ? AND payment_date < ?
    ''', [from, until]);
    final suppliers = await db.rawQuery('''
      SELECT s.id AS supplier_id, s.name AS supplier_name,
        COUNT(p.id) AS invoice_count, COALESCE(SUM(p.total), 0) AS total_amount,
        COALESCE(SUM(p.paid), 0) AS paid_amount,
        COALESCE(SUM(p.total - p.paid), 0) AS outstanding
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.purchase_date >= ? AND p.purchase_date < ?
      GROUP BY s.id, s.name
      ORDER BY total_amount DESC
      LIMIT 20
    ''', [from, until]);
    final latest = await db.rawQuery('''
      SELECT p.id, p.invoice_number, p.purchase_date, p.total, p.paid,
        (p.total - p.paid) AS outstanding, s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.purchase_date >= ? AND p.purchase_date < ?
      ORDER BY p.purchase_date DESC, p.id DESC
      LIMIT 20
    ''', [from, until]);
    return {
      'purchase_count': purchases.first['count'] ?? 0,
      'purchase_total': purchases.first['total_amount'] ?? 0,
      'recorded_paid': purchases.first['recorded_paid'] ?? 0,
      'outstanding': purchases.first['outstanding'] ?? 0,
      'return_count': returns.first['count'] ?? 0,
      'return_amount': returns.first['amount'] ?? 0,
      'payment_count': payments.first['count'] ?? 0,
      'payment_amount': payments.first['amount'] ?? 0,
      'suppliers': suppliers,
      'latest': latest,
    };
  }
}
