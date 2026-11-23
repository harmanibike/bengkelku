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
      FROM cash_transactions WHERE datetime(transaction_date) < datetime(?)
    ''', [from]);
    final rows = await db.rawQuery('''
      SELECT * FROM cash_transactions
      WHERE datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
      ORDER BY datetime(transaction_date) ASC, id ASC
    ''', [from, until]);
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
      if (type == 'all' || row['transaction_type'] == type) {
        entries.add({...row, 'running_balance': balance});
      }
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

  /// Pemeriksaan referensi buku kas tanpa mengubah transaksi.
  Future<List<Map<String, Object?>>> getReconciliationIssues({
    required DateTime start,
    required DateTime end,
  }) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT * FROM (\n      SELECT c.*,
        CASE
          WHEN c.amount <= 0 THEN 'Nominal harus lebih dari nol'
          WHEN c.transaction_type NOT IN ('income', 'expense') THEN 'Jenis kas tidak valid'
          WHEN c.reference_type IS NULL OR c.reference_type = '' THEN 'Sumber transaksi tidak tercatat'
          WHEN c.reference_type = 'manual_cash' AND c.reference_id IS NOT NULL THEN 'Transaksi manual memiliki ID referensi'
          WHEN c.reference_type IN ('sale', 'sale_payment', 'sale_cancel')
            AND NOT EXISTS (SELECT 1 FROM sales s WHERE s.id = c.reference_id)
            THEN 'Nota penjualan tidak ditemukan'
          WHEN c.reference_type IN ('service_order', 'service_order_cancellation')
            AND NOT EXISTS (SELECT 1 FROM service_orders s WHERE s.id = c.reference_id)
            THEN 'Nota servis tidak ditemukan'
          WHEN c.reference_type IN ('purchase_payment', 'purchase_cancel')
            AND NOT EXISTS (SELECT 1 FROM purchases p WHERE p.id = c.reference_id)
            THEN 'Faktur pembelian tidak ditemukan'
          WHEN c.reference_type = 'purchase_return_refund'
            AND NOT EXISTS (SELECT 1 FROM purchase_returns r WHERE r.id = c.reference_id)
            THEN 'Dokumen retur pembelian tidak ditemukan'
          WHEN c.reference_type NOT IN (
            'manual_cash', 'sale', 'sale_payment', 'sale_cancel',
            'service_order', 'service_order_cancellation',
            'purchase_payment', 'purchase_cancel', 'purchase_return_refund'
          ) THEN 'Jenis sumber transaksi belum dikenali'
          ELSE NULL
        END AS audit_issue
      FROM cash_transactions c
      WHERE datetime(c.transaction_date) >= datetime(?)
        AND datetime(c.transaction_date) < datetime(?)
      HAVING audit_issue IS NOT NULL
      ORDER BY datetime(c.transaction_date) DESC, c.id DESC
    ''', [start.toIso8601String(), end.toIso8601String()]);
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
