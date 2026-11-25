import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';

class ReportRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, Object?>> getSummary({required DateTime start, required DateTime end}) async {
    AuthSession.instance.requireCashierOrAdmin('Laporan keuangan hanya dapat diakses Admin dan Kasir.');
    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();

    final cash = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN transaction_type = 'income' THEN amount ELSE 0 END), 0) AS income,
        COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount ELSE 0 END), 0) AS expense,
        COUNT(*) AS transaction_count
      FROM cash_transactions
      WHERE COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover')
        AND datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
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
      WHERE COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover')
        AND datetime(transaction_date) < datetime(?)
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

    // HPP memakai snapshot biaya per unit yang disimpan pada baris nota.
    // Pada metode rata-rata tertimbang, alokasi batch FIFO tetap dipakai untuk
    // mengembalikan stok ke batch asal, tetapi bukan sebagai HPP transaksi.
    // Pada metode per batch, snapshot purchase_price berisi rata-rata biaya
    // batch yang benar-benar terpakai saat nota dibuat.
    final soldCostRows = await db.rawQuery('''
      SELECT COALESCE(SUM(si.quantity * COALESCE(si.purchase_price, 0)), 0) AS amount
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

    // Biaya langsung servis menggunakan snapshot riwayat terakhir yang
    // berlaku saat pekerjaan selesai. Koreksi biaya yang dilakukan kemudian
    // tidak diam-diam mengubah laporan periode lama.
    // Nota lama tanpa riwayat yang cocok memakai nilai biaya tersimpan.
    final serviceDirectCostRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        COALESCE((
          SELECT COALESCE(h.new_direct_parts_cost, 0)
               + COALESCE(h.new_other_direct_cost, 0)
          FROM service_direct_cost_history h
          WHERE h.service_order_id = s.id
            AND datetime(h.changed_at) <= datetime(s.completed_at)
          ORDER BY datetime(h.changed_at) DESC, h.id DESC
          LIMIT 1
        ), COALESCE(s.direct_parts_cost, 0) + COALESCE(s.other_direct_cost, 0))
      ), 0) AS amount
      FROM service_orders s
      WHERE s.service_status IN ('completed', 'delivered')
        AND s.completed_at IS NOT NULL
        AND datetime(s.completed_at) >= datetime(?)
        AND datetime(s.completed_at) < datetime(?)
    ''', [from, until]);

    // Pengeluaran operasional manual dari buku kas. Pembayaran pembelian pemasok
    // dikecualikan karena merupakan arus kas persediaan dan HPP sudah dihitung terpisah.
    final manualOperatingExpenseRows = await db.rawQuery('''
      SELECT COALESCE(SUM(amount), 0) AS amount, COUNT(*) AS total
      FROM cash_transactions
      WHERE transaction_type = 'expense'
        AND reference_type = 'manual_cash'
        AND datetime(transaction_date) >= datetime(?)
        AND datetime(transaction_date) < datetime(?)
    ''', [from, until]);

    // Saldo piutang saat ini tidak dibatasi periode laporan.
    final serviceReceivableRows = await db.rawQuery('''
      SELECT COALESCE(SUM(remaining_payment), 0) AS amount, COUNT(*) AS total
      FROM service_orders
      WHERE remaining_payment > 0 AND service_status != 'cancelled'
    ''');

    final saleReceivableRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        s.total - COALESCE(ret.returned_amount, 0) - s.paid
        + COALESCE(ret.refunded_amount, 0)
      ), 0) AS amount, COUNT(*) AS total
      FROM sales s
      LEFT JOIN (
        SELECT sale_id, SUM(total_amount) AS returned_amount,
          SUM(refunded_amount) AS refunded_amount
        FROM sale_returns GROUP BY sale_id
      ) ret ON ret.sale_id = s.id
      WHERE s.payment_status != 'cancelled'
        AND (s.total - COALESCE(ret.returned_amount, 0) - s.paid
          + COALESCE(ret.refunded_amount, 0)) > 0
    ''');

    final customerWalletRows = await db.rawQuery('''
      SELECT COALESCE(SUM(balance_after), 0) AS amount,
             COUNT(*) AS customer_count
      FROM customer_wallet_ledger current
      WHERE current.id = (
        SELECT MAX(latest.id) FROM customer_wallet_ledger latest
        WHERE latest.customer_id = current.customer_id
      )
    ''');

    final supplierPayableRows = await db.rawQuery('''
      SELECT COALESCE(SUM(
        CASE WHEN p.total - p.paid - COALESCE(p.return_credit, 0) > 0
          THEN p.total - p.paid - COALESCE(p.return_credit, 0) ELSE 0 END
      ), 0) AS amount, COUNT(*) AS total
      FROM purchases p
      WHERE p.status = 'active'
        AND p.total > p.paid + COALESCE(p.return_credit, 0)
    ''');

    // Audit pengembalian uang retur: nilai refund pada nota retur harus
    // sama dengan kas keluar yang terhubung ke ID retur tersebut.
    // Periode diperiksa pada tanggal retur maupun tanggal kas agar transaksi
    // yang salah tanggal tetap terlihat. Pemeriksaan ini hanya-baca.
    final returnRefundAudit = await db.rawQuery('''
      SELECT
        sr.id AS return_id,
        sr.return_number,
        s.invoice_number,
        sr.refunded_amount AS recorded_refund,
        COALESCE(ct.cash_refund, 0) AS cash_refund,
        COALESCE(wr.wallet_refund, 0) AS wallet_refund,
        sr.refunded_amount - COALESCE(ct.cash_refund, 0) - COALESCE(wr.wallet_refund, 0) AS difference
      FROM sale_returns sr
      JOIN sales s ON s.id = sr.sale_id
      LEFT JOIN (
        SELECT reference_id AS return_id, SUM(amount) AS cash_refund
        FROM cash_transactions
        WHERE reference_type = 'sale_return'
          AND transaction_type = 'expense'
        GROUP BY reference_id
      ) ct ON ct.return_id = sr.id
      LEFT JOIN (
        SELECT reference_id AS return_id, SUM(amount) AS wallet_refund
        FROM customer_wallet_ledger
        WHERE reference_type = 'sale_return' AND entry_type = 'refund'
        GROUP BY reference_id
      ) wr ON wr.return_id = sr.id
      WHERE sr.refunded_amount != COALESCE(ct.cash_refund, 0) + COALESCE(wr.wallet_refund, 0)
        AND (
          (datetime(sr.return_date) >= datetime(?) AND datetime(sr.return_date) < datetime(?))
          OR EXISTS (
            SELECT 1 FROM cash_transactions cash_check
            WHERE cash_check.reference_type = 'sale_return'
              AND cash_check.reference_id = sr.id
              AND datetime(cash_check.transaction_date) >= datetime(?)
              AND datetime(cash_check.transaction_date) < datetime(?)
          )
          OR EXISTS (
            SELECT 1 FROM customer_wallet_ledger wallet_check
            WHERE wallet_check.reference_type = 'sale_return'
              AND wallet_check.reference_id = sr.id AND wallet_check.entry_type = 'refund'
              AND datetime(wallet_check.created_at) >= datetime(?)
              AND datetime(wallet_check.created_at) < datetime(?)
          )
        )
      ORDER BY sr.return_date DESC, sr.id DESC
      LIMIT 50
    ''', [from, until, from, until, from, until]);

    // Audit retur pembelian: cocokkan nilai item, kredit pemasok, refund kas,
    // dan kuantitas alokasi batch. Hanya-baca; tidak memperbaiki transaksi.
    final purchaseReturnAudit = await db.rawQuery('''
      SELECT
        pr.id AS return_id,
        pr.return_number,
        p.invoice_number,
        pr.total_amount,
        COALESCE(items.item_total, 0) AS item_total,
        pr.credit_applied,
        COALESCE(credits.applied_total, 0) AS applied_credit_total,
        pr.refund_received,
        COALESCE(refunds.cash_refund, 0) AS cash_refund,
        COALESCE(batch_issues.issue_count, 0) AS batch_issue_count
      FROM purchase_returns pr
      JOIN purchases p ON p.id = pr.purchase_id
      LEFT JOIN (
        SELECT purchase_return_id, SUM(subtotal) AS item_total
        FROM purchase_return_items
        GROUP BY purchase_return_id
      ) items ON items.purchase_return_id = pr.id
      LEFT JOIN (
        SELECT return_id, SUM(amount) AS applied_total
        FROM supplier_return_credit_applications
        GROUP BY return_id
      ) credits ON credits.return_id = pr.id
      LEFT JOIN (
        SELECT reference_id AS return_id, SUM(amount) AS cash_refund
        FROM cash_transactions
        WHERE reference_type = 'purchase_return_refund'
          AND transaction_type = 'income'
        GROUP BY reference_id
      ) refunds ON refunds.return_id = pr.id
      LEFT JOIN (
        SELECT pri.purchase_return_id,
          SUM(CASE WHEN prod.id IS NOT NULL AND COALESCE(prod.track_stock, 0) = 1
            AND COALESCE(alloc.allocated_quantity, 0) != pri.quantity
            THEN 1 ELSE 0 END) AS issue_count
        FROM purchase_return_items pri
        LEFT JOIN products prod ON prod.id = pri.product_id
        LEFT JOIN (
          SELECT return_item_id, SUM(quantity) AS allocated_quantity
          FROM purchase_return_batch_allocations
          GROUP BY return_item_id
        ) alloc ON alloc.return_item_id = pri.id
        GROUP BY pri.purchase_return_id
      ) batch_issues ON batch_issues.purchase_return_id = pr.id
      WHERE pr.status = 'active'
        AND (
          pr.total_amount != COALESCE(items.item_total, 0)
          OR pr.credit_applied != COALESCE(credits.applied_total, 0)
          OR pr.refund_received != COALESCE(refunds.cash_refund, 0)
          OR COALESCE(batch_issues.issue_count, 0) > 0
          OR pr.credit_applied + pr.refund_received > pr.total_amount
        )
        AND (
          (datetime(pr.return_date) >= datetime(?) AND datetime(pr.return_date) < datetime(?))
          OR EXISTS (
            SELECT 1 FROM cash_transactions cash_check
            WHERE cash_check.reference_type = 'purchase_return_refund'
              AND cash_check.reference_id = pr.id
              AND datetime(cash_check.transaction_date) >= datetime(?)
              AND datetime(cash_check.transaction_date) < datetime(?)
          )
        )
      ORDER BY pr.return_date DESC, pr.id DESC
      LIMIT 50
    ''', [from, until, from, until]);

    // Audit HPP retur: biaya yang dikembalikan ke laba-rugi harus sama
    // dengan snapshot biaya pada nota asal. Alokasi batch tetap diperiksa
    // terpisah untuk memastikan jumlah stok yang dipulihkan benar.
    final saleReturnCostAudit = await db.rawQuery('''
      SELECT
        sr.id AS return_id,
        sr.return_number,
        s.invoice_number,
        COUNT(CASE
          WHEN COALESCE(sri.unit_cost, 0) != COALESCE(si.purchase_price, 0)
          THEN 1 END) AS cost_issue_count,
        COUNT(CASE
          WHEN EXISTS (
            SELECT 1 FROM sale_batch_allocations original_alloc
            WHERE original_alloc.sale_item_id = sri.sale_item_id
          )
          AND COALESCE(return_alloc.allocated_quantity, 0) != sri.quantity
          THEN 1 END) AS batch_quantity_issue_count,
        SUM(CASE
          WHEN COALESCE(sri.unit_cost, 0) != COALESCE(si.purchase_price, 0)
          THEN 1 ELSE 0 END) AS cost_issue_items
      FROM sale_returns sr
      JOIN sales s ON s.id = sr.sale_id
      JOIN sale_return_items sri ON sri.sale_return_id = sr.id
      JOIN sale_items si ON si.id = sri.sale_item_id
      LEFT JOIN (
        SELECT sale_return_item_id, SUM(quantity) AS allocated_quantity
        FROM sale_return_batch_allocations
        GROUP BY sale_return_item_id
      ) return_alloc ON return_alloc.sale_return_item_id = sri.id
      WHERE (
        (datetime(sr.return_date) >= datetime(?) AND datetime(sr.return_date) < datetime(?))
        OR EXISTS (
          SELECT 1 FROM cash_transactions cash_check
          WHERE cash_check.reference_type = 'sale_return'
            AND cash_check.reference_id = sr.id
            AND datetime(cash_check.transaction_date) >= datetime(?)
            AND datetime(cash_check.transaction_date) < datetime(?)
        )
      )
      GROUP BY sr.id, sr.return_number, s.invoice_number
      HAVING cost_issue_count > 0 OR batch_quantity_issue_count > 0
      ORDER BY sr.return_date DESC, sr.id DESC
      LIMIT 50
    ''', [from, until, from, until]);

    final lowStock = await db.rawQuery('''
      SELECT COUNT(*) AS total FROM products
      WHERE is_active = 1 AND track_stock = 1 AND stock <= minimum_stock
    ''');

    final categories = await db.rawQuery('''
      SELECT COALESCE(category, 'Lainnya') AS category,
             SUM(amount) AS amount,
             transaction_type
      FROM cash_transactions
      WHERE COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover')
        AND datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)
      GROUP BY category, transaction_type
      ORDER BY amount DESC
    ''', [from, until]);

    final latest = await db.query(
      'cash_transactions',
      where: "COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover') AND datetime(transaction_date) >= datetime(?) AND datetime(transaction_date) < datetime(?)",
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
      'manual_operating_expense_amount': manualOperatingExpenseRows.first['amount'] as int? ?? 0,
      'manual_operating_expense_count': manualOperatingExpenseRows.first['total'] as int? ?? 0,
      'profit_after_recorded_operating_expense': grossProfit + (serviceRevenueRows.first['amount'] as int? ?? 0) - (serviceDirectCostRows.first['amount'] as int? ?? 0) - (manualOperatingExpenseRows.first['amount'] as int? ?? 0),
      'service_receivable_amount': serviceReceivableRows.first['amount'] as int? ?? 0,
      'service_receivable_count': serviceReceivableRows.first['total'] as int? ?? 0,
      'sale_receivable_amount': saleReceivableRows.first['amount'] as int? ?? 0,
      'sale_receivable_count': saleReceivableRows.first['total'] as int? ?? 0,
      'customer_receivable_amount': (serviceReceivableRows.first['amount'] as int? ?? 0) + (saleReceivableRows.first['amount'] as int? ?? 0),
      'customer_receivable_count': (serviceReceivableRows.first['total'] as int? ?? 0) + (saleReceivableRows.first['total'] as int? ?? 0),
      'customer_wallet_balance': customerWalletRows.first['amount'] as int? ?? 0,
      'customer_wallet_customer_count': customerWalletRows.first['customer_count'] as int? ?? 0,
      'supplier_payable_amount': supplierPayableRows.first['amount'] as int? ?? 0,
      'supplier_payable_count': supplierPayableRows.first['total'] as int? ?? 0,
      'return_refund_audit_issues': returnRefundAudit,
      'purchase_return_audit_issues': purchaseReturnAudit,
      'sale_return_cost_audit_issues': saleReturnCostAudit,
      'low_stock': lowStock.first['total'] as int? ?? 0,
      'categories': categories,
      'latest': latest,
    };
  }
}
