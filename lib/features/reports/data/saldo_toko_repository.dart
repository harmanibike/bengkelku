import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class SaldoTokoRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  bool _isCash(Map<String, Object?> row) {
    final method = (row['payment_method']?.toString() ?? 'cash').toLowerCase();
    return method == 'cash' || method == 'tunai';
  }

  Future<Map<String, Object?>> getLedger({String filter = 'Semua'}) async {
    AuthSession.instance.requireCashierOrAdmin('Saldo Toko hanya dapat diakses Admin dan Kasir.');
    final db = await _db;
    final rows = await db.query('cash_transactions',
      where: "COALESCE(reference_type, '') NOT IN ('tip', 'tip_handover')",
      orderBy: 'datetime(transaction_date) ASC, id ASC');
    var balance = 0;
    final entries = <Map<String, Object?>>[];
    for (final row in rows) {
      final cash = _isCash(row);
      final income = row['transaction_type'] == 'income';
      final amount = (row['amount'] as num?)?.toInt() ?? 0;
      if (cash) balance += income ? amount : -amount;
      final category = row['category']?.toString() ?? '';
      final reference = row['reference_type']?.toString() ?? '';
      final label = _filterLabel(row, category, reference);
      if (filter == 'Semua' || filter == label ||
          (filter == 'Uang Masuk' && income) ||
          (filter == 'Uang Keluar' && !income)) {
        entries.add({...row, 'running_balance': balance, 'is_cash': cash});
      }
    }
    return {'balance': balance, 'entries': entries.reversed.toList(), 'count': entries.length};
  }

  String _filterLabel(Map<String, Object?> row, String category, String reference) {
    if (category == 'Modal Awal') return 'Modal Awal';
    if (category == 'Tarik Modal') return 'Uang Keluar';
    if (reference == 'sale' || reference == 'sale_payment') return 'Penjualan';
    if (reference == 'sale_return' || reference == 'sale_cancel' ||
        reference == 'service_order_cancellation') return 'Refund';
    if (reference == 'purchase_payment' || category.toLowerCase().contains('pembelian')) return 'Pembelian';
    if (category.toLowerCase().contains('pengeluaran') ||
        category.toLowerCase().contains('operasional')) return 'Pengeluaran';
    return row['transaction_type'] == 'income' ? 'Uang Masuk' : 'Uang Keluar';
  }

  Future<int> addCapitalMovement({
    required bool isDeposit,
    required int amount,
    required String paymentMethod,
    String? note,
  }) async {
    AuthSession.instance.requireAdmin('Tanam dan tarik modal hanya dapat dilakukan Admin.');
    if (amount <= 0) throw ArgumentError('Nominal harus lebih dari nol.');
    if (!['cash', 'bank_transfer'].contains(paymentMethod)) {
      throw ArgumentError('Metode pembayaran tidak valid.');
    }
    final db = await _db;
    return db.transaction((txn) async {
      if (!isDeposit && paymentMethod == 'cash') {
        final rows = await txn.rawQuery("""
          SELECT COALESCE(SUM(CASE WHEN transaction_type='income' THEN amount ELSE -amount END),0) AS balance
          FROM cash_transactions
          WHERE LOWER(COALESCE(payment_method,'cash')) IN ('cash','tunai')
            AND COALESCE(reference_type,'') NOT IN ('tip','tip_handover')
        """);
        final balance = (rows.first['balance'] as num?)?.toInt() ?? 0;
        if (amount > balance) {
          throw StateError('Tarik modal melebihi saldo tunai laci. Saldo tersedia Rp$balance.');
        }
      }
      final now = DateTime.now().toIso8601String();
      return txn.insert('cash_transactions', {
        'transaction_type': isDeposit ? 'income' : 'expense',
        'category': isDeposit ? 'Modal Awal' : 'Tarik Modal',
        'description': (note?.trim().isNotEmpty == true)
            ? note!.trim()
            : (isDeposit ? 'Tanam modal awal kas toko' : 'Tarik modal dari kas toko'),
        'amount': amount,
        'reference_type': 'manual_cash',
        'reference_id': null,
        'payment_method': paymentMethod,
        'transaction_date': now,
      });
    });
  }
}
