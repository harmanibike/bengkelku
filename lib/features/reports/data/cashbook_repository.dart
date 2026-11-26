import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';

import '../../../core/database/app_database.dart';

class CashbookRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, Object?>> getLedger({
    required DateTime start,
    required DateTime end,
    String type = 'all',
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Buku kas hanya dapat diakses Admin dan Kasir.');

    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    final openingRows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN transaction_type='income' THEN amount ELSE -amount END),0) AS balance,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(payment_method,'cash')) IN ('cash','tunai')
          THEN CASE WHEN transaction_type='income' THEN amount ELSE -amount END ELSE 0 END),0) AS cash_balance,
        COALESCE(SUM(CASE WHEN LOWER(COALESCE(payment_method,'cash')) NOT IN ('cash','tunai')
          THEN CASE WHEN transaction_type='income' THEN amount ELSE -amount END ELSE 0 END),0) AS non_cash_balance
      FROM cash_transactions WHERE COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover') AND datetime(transaction_date) < datetime(?)
    ''', [from]);
    final rows = await db.rawQuery('''
      SELECT * FROM cash_transactions
      WHERE COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover')
        AND datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
      ORDER BY datetime(transaction_date) ASC, id ASC
    ''', [from, until]);
    var balance = (openingRows.first['balance'] as num?)?.toInt() ?? 0;
    var income = 0;
    var expense = 0;
    var cashIncome = 0;
    var cashExpense = 0;
    var nonCashIncome = 0;
    var nonCashExpense = 0;
    final methodTotals = <String, int>{};
    final entries = <Map<String, Object?>>[];
    for (final row in rows) {
      final amount = (row['amount'] as num?)?.toInt() ?? 0;
      final isIncome = row['transaction_type'] == 'income';
      final method = (row['payment_method']?.toString().trim().isNotEmpty == true)
          ? row['payment_method'].toString().toLowerCase()
          : 'cash';
      final isCash = method == 'cash' || method == 'tunai';
      methodTotals[method] = (methodTotals[method] ?? 0) + (isIncome ? amount : -amount);
      if (isIncome) {
        income += amount;
        balance += amount;
        if (isCash) { cashIncome += amount; } else { nonCashIncome += amount; }
      } else {
        expense += amount;
        balance -= amount;
        if (isCash) { cashExpense += amount; } else { nonCashExpense += amount; }
      }
      if (type == 'all' || row['transaction_type'] == type) {
        entries.add({...row, 'running_balance': balance});
      }
    }
    final openingCash = (openingRows.first['cash_balance'] as num?)?.toInt() ?? 0;
    final openingNonCash = (openingRows.first['non_cash_balance'] as num?)?.toInt() ?? 0;
    return {
      'opening_balance': (openingRows.first['balance'] as num?)?.toInt() ?? 0,
      'income': income,
      'expense': expense,
      'closing_balance': balance,
      'cash_opening_balance': openingCash,
      'cash_income': cashIncome,
      'cash_expense': cashExpense,
      'cash_closing_balance': openingCash + cashIncome - cashExpense,
      'non_cash_opening_balance': openingNonCash,
      'non_cash_income': nonCashIncome,
      'non_cash_expense': nonCashExpense,
      'non_cash_closing_balance': openingNonCash + nonCashIncome - nonCashExpense,
      'payment_method_totals': methodTotals,
      'entries': entries.reversed.toList(),
      'count': entries.length,
    };
  }

  /// Pemeriksaan referensi buku kas tanpa mengubah transaksi.
  /// Audit referensi dan arah transaksi kas. Tidak mengubah data.
  Future<List<Map<String, Object?>>> getReconciliationIssues({
    required DateTime start,
    required DateTime end,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Buku kas hanya dapat diakses Admin dan Kasir.');

    final db = await _db;
    return db.rawQuery('''
      SELECT audit_rows.*
      FROM (
        SELECT c.*,
          CASE
            WHEN c.amount <= 0 THEN 'Nominal harus lebih dari nol'
            WHEN c.transaction_type NOT IN ('income', 'expense') THEN 'Jenis kas tidak valid'
            WHEN c.reference_type IN ('sale', 'sale_payment', 'service_order', 'purchase_return_refund', 'customer_deposit', 'tip')
              AND c.transaction_type != 'income' THEN 'Arah transaksi seharusnya kas masuk'
            WHEN c.reference_type IN ('sale_cancel', 'service_order_cancellation', 'purchase_payment', 'purchase_cancel', 'tip_handover', 'sale_return', 'customer_wallet_withdrawal')
              AND c.transaction_type != 'expense' THEN 'Arah transaksi seharusnya kas keluar'
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
            WHEN c.reference_type = 'purchase_return_refund'
              AND c.transaction_type != 'income'
              THEN 'Pengembalian uang retur seharusnya kas masuk'
            WHEN c.reference_type = 'purchase_return_refund'
              AND COALESCE((
                SELECT SUM(refund.amount)
                FROM cash_transactions refund
                WHERE refund.reference_type = 'purchase_return_refund'
                  AND refund.reference_id = c.reference_id
                  AND refund.transaction_type = 'income'
              ), 0) != COALESCE((
                SELECT r.refund_received FROM purchase_returns r
                WHERE r.id = c.reference_id
              ), 0)
              THEN 'Total refund kas tidak cocok dengan catatan penyelesaian retur'
            WHEN c.reference_type = 'sale_return'
              AND NOT EXISTS (SELECT 1 FROM sale_returns r WHERE r.id = c.reference_id)
              THEN 'Dokumen retur penjualan tidak ditemukan'
            WHEN c.reference_type = 'customer_deposit'
              AND NOT EXISTS (
                SELECT 1 FROM customer_wallet_ledger w
                WHERE w.id = c.reference_id AND w.entry_type = 'deposit'
                  AND w.amount = c.amount
              ) THEN 'Catatan deposit pelanggan tidak ditemukan atau nominal tidak cocok'
            WHEN c.reference_type = 'customer_wallet_withdrawal'
              AND NOT EXISTS (
                SELECT 1 FROM customer_wallet_ledger w
                WHERE w.id = c.reference_id AND w.entry_type = 'adjustment'
                  AND w.reference_type = 'customer_wallet_withdrawal'
                  AND w.amount = c.amount
              ) THEN 'Catatan penarikan saldo pelanggan tidak ditemukan atau nominal tidak cocok'
            WHEN c.reference_type IN ('tip', 'tip_handover')
              AND NOT EXISTS (SELECT 1 FROM tip_transactions t WHERE t.id = c.reference_id)
              THEN 'Catatan uang tip tidak ditemukan'
            WHEN c.reference_type NOT IN (
              'manual_cash', 'sale', 'sale_payment', 'sale_cancel',
              'service_order', 'service_order_cancellation',
              'purchase_payment', 'purchase_cancel', 'purchase_return_refund',
              'customer_deposit', 'tip', 'tip_handover', 'sale_return', 'customer_wallet_withdrawal'
            ) THEN 'Jenis sumber transaksi belum dikenali'
            ELSE NULL
          END AS audit_issue
        FROM cash_transactions c
        WHERE datetime(c.transaction_date) >= datetime(?)
          AND datetime(c.transaction_date) < datetime(?)
      ) audit_rows
      WHERE audit_issue IS NOT NULL
      ORDER BY datetime(transaction_date) DESC, id DESC
    ''', [start.toIso8601String(), end.toIso8601String()]);
  }

  /// Membandingkan riwayat pembayaran pemasok dengan kas keluar per faktur.
  /// Hanya membaca data; tidak melakukan koreksi otomatis.
  Future<List<Map<String, Object?>>> getSupplierPaymentMismatches({
    required DateTime start,
    required DateTime end,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Buku kas hanya dapat diakses Admin dan Kasir.');

    final db = await _db;
    return db.rawQuery('''
      SELECT p.id AS purchase_id, p.invoice_number, s.name AS supplier_name,
        COALESCE(p.paid, 0) AS stored_paid_total,
        COALESCE(pay.payment_total, 0) AS payment_history_total,
        COALESCE(cash.cash_total, 0) AS cash_out_total,
        COALESCE(p.paid, 0) - COALESCE(pay.payment_total, 0) AS stored_paid_difference,
        COALESCE(pay.payment_total, 0) - COALESCE(cash.cash_total, 0) AS difference
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      LEFT JOIN (
        SELECT purchase_id, SUM(amount) AS payment_total
        FROM supplier_payments
        GROUP BY purchase_id
      ) pay ON pay.purchase_id = p.id
      LEFT JOIN (
        SELECT reference_id AS purchase_id, SUM(amount) AS cash_total
        FROM cash_transactions
        WHERE reference_type = 'purchase_payment'
          AND transaction_type = 'expense'
        GROUP BY reference_id
      ) cash ON cash.purchase_id = p.id
      WHERE (
        COALESCE(pay.payment_total, 0) != COALESCE(cash.cash_total, 0)
        OR COALESCE(p.paid, 0) != COALESCE(pay.payment_total, 0)
      )
      AND (
        EXISTS (
          SELECT 1 FROM supplier_payments sp
          WHERE sp.purchase_id = p.id
            AND datetime(sp.payment_date) >= datetime(?)
            AND datetime(sp.payment_date) < datetime(?)
        )
        OR EXISTS (
          SELECT 1 FROM cash_transactions ct
          WHERE ct.reference_type = 'purchase_payment'
            AND ct.reference_id = p.id
            AND datetime(ct.transaction_date) >= datetime(?)
            AND datetime(ct.transaction_date) < datetime(?)
        )
      )
      ORDER BY p.purchase_date DESC, p.id DESC
    ''', [
      start.toIso8601String(), end.toIso8601String(),
      start.toIso8601String(), end.toIso8601String(),
    ]);
  }

  /// Membandingkan nilai pembayaran tersimpan dengan seluruh kas masuk terkait.
  /// Audit penjualan dan servis bersifat baca-saja; transaksi batal tetap diperiksa
  /// terhadap pembayaran asal, sementara refund pembatalan tidak dihitung sebagai kas masuk.
  Future<List<Map<String, Object?>>> getCustomerPaymentMismatches({
    required DateTime start,
    required DateTime end,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Buku kas hanya dapat diakses Admin dan Kasir.');

    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    return db.rawQuery('''
      SELECT * FROM (
        SELECT
          'Penjualan' AS document_type,
          s.id AS record_id,
          s.invoice_number AS document_number,
          COALESCE(c.name, '-') AS customer_name,
          s.paid AS stored_paid_total,
          COALESCE(pay.payment_total, 0) AS payment_history_total,
          s.paid - COALESCE(pay.payment_total, 0) AS difference
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
        LEFT JOIN (
          SELECT reference_id AS sale_id, SUM(amount) AS payment_total
          FROM (
            SELECT reference_id, amount FROM cash_transactions
            WHERE reference_type IN ('sale', 'sale_payment') AND transaction_type = 'income'
            UNION ALL
            SELECT reference_id, amount FROM customer_wallet_ledger
            WHERE reference_type = 'sale' AND entry_type = 'sale_payment'
          )
          GROUP BY reference_id
        ) pay ON pay.sale_id = s.id
        WHERE s.paid != COALESCE(pay.payment_total, 0)
          AND (
            (datetime(s.transaction_date) >= datetime(?) AND datetime(s.transaction_date) < datetime(?))
            OR EXISTS (
              SELECT 1 FROM cash_transactions ct
              WHERE ct.reference_id = s.id
                AND ct.reference_type IN ('sale', 'sale_payment')
                AND datetime(ct.transaction_date) >= datetime(?)
                AND datetime(ct.transaction_date) < datetime(?)
            )
            OR EXISTS (
              SELECT 1 FROM customer_wallet_ledger w
              WHERE w.reference_id = s.id AND w.reference_type = 'sale'
                AND w.entry_type = 'sale_payment'
                AND datetime(w.created_at) >= datetime(?) AND datetime(w.created_at) < datetime(?)
            )
          )

        UNION ALL

        SELECT
          'Servis' AS document_type,
          s.id AS record_id,
          s.order_number AS document_number,
          COALESCE(c.name, '-') AS customer_name,
          (s.total_cost - s.remaining_payment) AS stored_paid_total,
          COALESCE(pay.payment_total, 0) AS payment_history_total,
          (s.total_cost - s.remaining_payment) - COALESCE(pay.payment_total, 0) AS difference
        FROM service_orders s
        LEFT JOIN customers c ON c.id = s.customer_id
        LEFT JOIN (
          SELECT reference_id AS service_order_id, SUM(amount) AS payment_total
          FROM (
            SELECT reference_id, amount FROM cash_transactions
            WHERE reference_type = 'service_order' AND transaction_type = 'income'
            UNION ALL
            SELECT reference_id, amount FROM customer_wallet_ledger
            WHERE reference_type = 'service_order' AND entry_type = 'service_payment'
          )
          GROUP BY reference_id
        ) pay ON pay.service_order_id = s.id
        WHERE (s.total_cost - s.remaining_payment) != COALESCE(pay.payment_total, 0)
          AND (
            (datetime(s.received_at) >= datetime(?) AND datetime(s.received_at) < datetime(?))
            OR EXISTS (
              SELECT 1 FROM cash_transactions ct
              WHERE ct.reference_id = s.id
                AND ct.reference_type = 'service_order'
                AND datetime(ct.transaction_date) >= datetime(?)
                AND datetime(ct.transaction_date) < datetime(?)
            )
            OR EXISTS (
              SELECT 1 FROM customer_wallet_ledger w
              WHERE w.reference_id = s.id AND w.reference_type = 'service_order'
                AND w.entry_type = 'service_payment'
                AND datetime(w.created_at) >= datetime(?) AND datetime(w.created_at) < datetime(?)
            )
          )
      ) mismatches
      ORDER BY document_type ASC, record_id DESC
    ''', [from, until, from, until, from, until, from, until, from, until, from, until]);
  }


  Future<List<Map<String, Object?>>> getManualExpenses({
    required DateTime start,
    required DateTime end,
  }) async {
    AuthSession.instance.requireAdmin('Menu pengeluaran hanya dapat diakses Admin.');
    final db = await _db;
    return db.query(
      'cash_transactions',
      where: "reference_type = 'manual_cash' AND transaction_type = 'expense' AND datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)",
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'datetime(transaction_date) DESC, id DESC',
    );
  }

  Future<int> addManualTransaction({
    required String type,
    required String category,
    required String description,
    required int amount,
    String paymentMethod = 'cash',
    DateTime? date,
  }) async {
    AuthSession.instance.requireAdmin('Pencatatan transaksi kas manual hanya dapat dilakukan Admin.');

    if (!['income', 'expense'].contains(type)) {
      throw ArgumentError('Jenis transaksi tidak valid.');
    }
    if (type == 'expense' && !['cash', 'bank_transfer'].contains(paymentMethod)) {
      throw ArgumentError('Metode pengeluaran harus Tunai atau Transfer Bank.');
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
      'payment_method': paymentMethod,
      'reference_type': 'manual_cash',
      'reference_id': null,
      'transaction_date': (date ?? DateTime.now()).toIso8601String(),
    });
  }
}
