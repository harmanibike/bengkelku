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
      WHERE datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
    ''', [from, until]);

    final cashOpeningRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN transaction_type = 'income' THEN amount
          WHEN transaction_type = 'expense' THEN -amount
          ELSE 0
        END
      ), 0) AS balance
      FROM cash_transactions
      WHERE datetime(transaction_date) < datetime(?)
    ''', [from]);

    final sales = await db.rawQuery('''
      SELECT COUNT(*) AS total, COALESCE(SUM(total), 0) AS amount
      FROM sales
      WHERE datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
        AND COALESCE(payment_status, 'paid') != 'cancelled'
    ''', [from, until]);

    final saleReturns = await db.rawQuery('''
      SELECT COUNT(*) AS total, COALESCE(SUM(total_amount), 0) AS amount
      FROM sale_returns
      WHERE datetime(return_date) >= datetime(?) AND datetime(return_date) < datetime(?)
    ''', [from, until]);

    // HPP penjualan: gunakan alokasi batch FIFO jika tersedia.
    // Transaksi lama tanpa alokasi memakai harga modal yang tersimpan pada item.
    final soldCostRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE
          WHEN EXISTS (
            SELECT 1 FROM sale_batch_allocations sba
            WHERE sba.sale_item_id = si.id
          ) THEN (
            SELECT COALESCE(SUM(sba.quantity * sba.unit_cost), 0)
            FROM sale_batch_allocations sba
            WHERE sba.sale_item_id = si.id
          )
          ELSE si.quantity * COALESCE(si.purchase_price, 0)
        END
      ), 0) AS amount
      FROM sale_items si
      JOIN sales s ON s.id = si.sale_id
      WHERE datetime(s.transaction_date) >= datetime(?) AND datetime(s.transaction_date) < datetime(?)
        AND COALESCE(s.payment_status, 'paid') != 'cancelled'
    ''', [from, until]);

    // HPP barang retur dikurangkan dari HPP terjual karena barang kembali ke stok.
    final returnedCostRows = await db.rawQuery('''
      SELECT COALESCE(SUM(sri.quantity * COALESCE(sri.unit_cost, 0)), 0) AS amount
      FROM sale_return_items sri
      JOIN sale_returns sr ON sr.id = sri.sale_return_id
      WHERE datetime(sr.return_date) >= datetime(?) AND datetime(sr.return_date) < datetime(?)
    ''', [from, until]);

    final grossProfit = (sales.first['amount'] as int? ?? 0)
        - (saleReturns.first['amount'] as int? ?? 0)
        - (soldCostRows.first['amount'] as int? ?? 0)
        + (returnedCostRows.first['amount'] as int? ?? 0);

    final services = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM service_orders WHERE datetime(received_at) >= datetime(?) AND datetime(received_at) < datetime(?)
    ''', [from, until]);

    // Pendapatan servis diakui saat pekerjaan selesai, bukan saat DP diterima.
    // Penerimaan DP/pelunasan tetap hanya dihitung pada laporan arus kas.
    final serviceRevenueRows = await db.rawQuery('''
      SELECT COUNT(*) AS total, COALESCE(SUM(total_cost), 0) AS amount
      FROM service_orders
      WHERE service_status IN ('completed', 'delivered')
        AND completed_at IS NOT NULL
        AND datetime(completed_at) >= datetime(?)
        AND datetime(completed_at) < datetime(?)
    ''', [from, until]);

    // Biaya langsung servis dicatat terpisah dari nilai tagihan pelanggan.
    // Hanya nota selesai/diambil pada periode penyelesaian yang dihitung.
    final serviceDirectCostRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        COALESCE(direct_parts_cost, 0) + COALESCE(other_direct_cost, 0)
      ), 0) AS amount
      FROM service_orders
      WHERE service_status IN ('completed', 'delivered')
        AND completed_at IS NOT NULL
        AND datetime(completed_at) >= datetime(?)
        AND datetime(completed_at) < datetime(?)
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
      WHERE datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
      GROUP BY category, transaction_type
      ORDER BY amount DESC
    ''', [from, until]);

    final latest = await db.query(
      'cash_transactions',
      where: 'datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)',
      whereArgs: [from, until],
      orderBy: 'datetime(transaction_date) DESC, id DESC',
      limit: 20,
    );

    return {
      'opening_cash_balance': cashOpeningRows.first['balance'] as int? ?? 0,
      'income': cash.first['income'] as int? ?? 0,
      'net_cash_flow': (cash.first['income'] as int? ?? 0) - (cash.first['expense'] as int? ?? 0),
      'closing_cash_balance': (cashOpeningRows.first['balance'] as int? ?? 0)
          + (cash.first['income'] as int? ?? 0)
          - (cash.first['expense'] as int? ?? 0),
      'expense': cash.first['expense'] as int? ?? 0,
      'transaction_count': cash.first['transaction_count'] as int? ?? 0,
      'sales_count': sales.first['total'] as int? ?? 0,
      'sales_amount': sales.first['amount'] as int? ?? 0,
      'sales_return_count': saleReturns.first['total'] as int? ?? 0,
      'sales_return_amount': saleReturns.first['amount'] as int? ?? 0,
      'net_sales_amount': (sales.first['amount'] as int? ?? 0) - (saleReturns.first['amount'] as int? ?? 0),
      'sold_cogs_amount': soldCostRows.first['amount'] as int? ?? 0,
      'returned_cogs_amount': returnedCostRows.first['amount'] as int? ?? 0,
      'net_cogs_amount': (soldCostRows.first['amount'] as int? ?? 0) - (returnedCostRows.first['amount'] as int? ?? 0),
      'gross_profit_amount': grossProfit,
      'service_count': services.first['total'] as int? ?? 0,
      'completed_service_count': serviceRevenueRows.first['total'] as int? ?? 0,
      'service_revenue': serviceRevenueRows.first['amount'] as int? ?? 0,
      'service_direct_cost_amount': serviceDirectCostRows.first['amount'] as int? ?? 0,
      'service_gross_profit_amount': (serviceRevenueRows.first['amount'] as int? ?? 0) - (serviceDirectCostRows.first['amount'] as int? ?? 0),
      'combined_gross_profit_amount': grossProfit + (serviceRevenueRows.first['amount'] as int? ?? 0) - (serviceDirectCostRows.first['amount'] as int? ?? 0),
      'low_stock': lowStock.first['total'] as int? ?? 0,
      'categories': categories,
      'latest': latest,
    };
  }
}
