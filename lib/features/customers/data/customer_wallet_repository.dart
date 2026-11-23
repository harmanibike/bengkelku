import 'package:sqflite/sqflite.dart';

import '../../../core/auth/activity_log_repository.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class CustomerWalletRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<int> getBalance(int customerId) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat saldo pelanggan.');
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
      [customerId],
    );
    return rows.isEmpty ? 0 : (rows.first['balance_after'] as num?)?.toInt() ?? 0;
  }

  Future<List<Map<String, Object?>>> getLedger(int customerId) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat riwayat saldo pelanggan.');
    final db = await _db;
    return db.query('customer_wallet_ledger', where: 'customer_id = ?', whereArgs: [customerId], orderBy: 'created_at DESC, id DESC');
  }

  Future<int> addDeposit({
    required int customerId,
    required int amount,
    required String paymentMethod,
    String? note,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat menerima deposit pelanggan.');
    if (amount <= 0) throw ArgumentError('Nominal deposit harus lebih dari nol.');
    final db = await _db;
    return db.transaction((txn) async {
      final customer = await txn.query('customers', where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw StateError('Pelanggan tidak ditemukan.');
      final balanceRows = await txn.rawQuery(
        'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
        [customerId],
      );
      final balance = balanceRows.isEmpty ? 0 : (balanceRows.first['balance_after'] as num?)?.toInt() ?? 0;
      final nextBalance = balance + amount;
      final now = DateTime.now().toIso8601String();
      final ledgerId = await txn.insert('customer_wallet_ledger', {
        'customer_id': customerId, 'entry_type': 'deposit', 'amount': amount,
        'balance_after': nextBalance,
        'description': note?.trim().isNotEmpty == true ? note!.trim() : 'Deposit saldo pelanggan',
        'payment_method': paymentMethod, 'created_by_id': AuthSession.instance.userId,
        'created_by_name': AuthSession.instance.displayName, 'created_at': now,
      });
      await txn.insert('cash_transactions', {
        'transaction_type': 'income', 'category': 'Deposit Pelanggan',
        'description': 'Deposit ${customer.first['name']}', 'amount': amount,
        'reference_type': 'customer_deposit', 'reference_id': ledgerId, 'transaction_date': now,
      });
      await ActivityLogRepository.record(txn, action: 'customer_wallet_deposit',
        description: 'Menerima deposit Rp$amount dari ${customer.first['name']}.',
        entityType: 'customer', entityId: customerId);
      return ledgerId;
    });
  }

  Future<int> withdrawCash({
    required int customerId,
    required int amount,
    String? note,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat memproses penarikan saldo pelanggan.');
    if (amount <= 0) throw ArgumentError('Nominal penarikan harus lebih dari nol.');
    final db = await _db;
    return db.transaction((txn) async {
      final customer = await txn.query('customers', columns: ['id', 'name'], where: 'id = ?', whereArgs: [customerId], limit: 1);
      if (customer.isEmpty) throw StateError('Pelanggan tidak ditemukan.');
      final balanceRows = await txn.rawQuery(
        'SELECT balance_after FROM customer_wallet_ledger WHERE customer_id = ? ORDER BY id DESC LIMIT 1',
        [customerId],
      );
      final balance = balanceRows.isEmpty ? 0 : (balanceRows.first['balance_after'] as num?)?.toInt() ?? 0;
      if (amount > balance) throw StateError('Saldo tidak mencukupi. Saldo tersedia Rp$balance.');
      final now = DateTime.now().toIso8601String();
      final nextBalance = balance - amount;
      final ledgerId = await txn.insert('customer_wallet_ledger', {
        'customer_id': customerId,
        'entry_type': 'adjustment',
        'amount': amount,
        'balance_after': nextBalance,
        'description': note?.trim().isNotEmpty == true ? 'Penarikan tunai: ${note!.trim()}' : 'Penarikan tunai oleh pelanggan',
        'reference_type': 'customer_wallet_withdrawal',
        'reference_id': customerId,
        'payment_method': 'cash',
        'created_by_id': AuthSession.instance.userId,
        'created_by_name': AuthSession.instance.displayName,
        'created_at': now,
      });
      await txn.insert('cash_transactions', {
        'transaction_type': 'expense',
        'category': 'Penarikan Saldo Pelanggan',
        'description': 'Penarikan tunai saldo ${customer.first['name']}',
        'amount': amount,
        'reference_type': 'customer_wallet_withdrawal',
        'reference_id': ledgerId,
        'transaction_date': now,
        'created_at': now,
      });
      await ActivityLogRepository.record(
        txn,
        action: 'customer_wallet_withdrawal',
        description: 'Penarikan tunai saldo Rp$amount oleh ${customer.first['name']}.',
        entityType: 'customer',
        entityId: customerId,
      );
      return ledgerId;
    });
  }

  Future<int> recordTip({
    required int amount,
    required String sourceType,
    int? sourceId,
    String? recipientName,
    int? recipientAccountId,
    String? paymentMethod,
    String? note,
  }) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mencatat uang tip.');
    if (amount <= 0) throw ArgumentError('Nominal tip harus lebih dari nol.');
    if (!const ['service_order', 'sale', 'manual'].contains(sourceType)) throw ArgumentError('Sumber tip tidak valid.');
    final db = await _db;
    return db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final tipId = await txn.insert('tip_transactions', {
        'amount': amount, 'source_type': sourceType, 'source_id': sourceId,
        'recipient_account_id': recipientAccountId, 'recipient_name': recipientName?.trim(),
        'payment_method': paymentMethod ?? 'cash', 'status': 'held', 'note': note?.trim(),
        'received_by_id': AuthSession.instance.userId, 'received_by_name': AuthSession.instance.displayName,
        'received_at': now,
      });
      final recipient = recipientName?.trim();
      await txn.insert('cash_transactions', {
        'transaction_type': 'income', 'category': 'Uang Tip',
        'description': recipient == null || recipient.isEmpty ? 'Penerimaan uang tip' : 'Penerimaan uang tip untuk $recipient',
        'amount': amount, 'reference_type': 'tip', 'reference_id': tipId, 'transaction_date': now,
      });
      await ActivityLogRepository.record(txn, action: 'tip_received',
        description: 'Mencatat uang tip Rp$amount.', entityType: 'tip', entityId: tipId);
      return tipId;
    });
  }

  Future<int> handOverTip({required int tipId, String? note}) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengonfirmasi penyerahan uang tip.');
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('tip_transactions', where: 'id = ?', whereArgs: [tipId], limit: 1);
      if (rows.isEmpty) throw StateError('Catatan tip tidak ditemukan.');
      final tip = rows.first;
      if (tip['status'] != 'held') throw StateError('Tip ini sudah diserahkan atau dibatalkan.');
      final now = DateTime.now().toIso8601String();
      final amount = (tip['amount'] as num?)?.toInt() ?? 0;
      await txn.update('tip_transactions', {
        'status': 'handed_over', 'handed_over_by_id': AuthSession.instance.userId,
        'handed_over_by_name': AuthSession.instance.displayName, 'handed_over_at': now,
        if (note?.trim().isNotEmpty == true) 'note': note!.trim(),
      }, where: 'id = ?', whereArgs: [tipId]);
      await txn.insert('cash_transactions', {
        'transaction_type': 'expense', 'category': 'Penyerahan Uang Tip',
        'description': 'Penyerahan uang tip #$tipId', 'amount': amount,
        'reference_type': 'tip_handover', 'reference_id': tipId, 'transaction_date': now,
      });
      await ActivityLogRepository.record(txn, action: 'tip_handed_over',
        description: 'Menyerahkan uang tip #$tipId sebesar Rp$amount.',
        entityType: 'tip', entityId: tipId);
      return 1;
    });
  }

  Future<Map<String, Object?>> getTipReport({required DateTime start, required DateTime end}) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat melihat laporan tip.');
    final db = await _db;
    final from = start.toIso8601String();
    final until = end.toIso8601String();
    final rows = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN status != 'cancelled' THEN amount ELSE 0 END), 0) AS received,
        COALESCE(SUM(CASE WHEN status = 'held' THEN amount ELSE 0 END), 0) AS held,
        COALESCE(SUM(CASE WHEN status = 'handed_over' THEN amount ELSE 0 END), 0) AS handed_over,
        COUNT(CASE WHEN status != 'cancelled' THEN 1 END) AS count
      FROM tip_transactions
      WHERE datetime(received_at) >= datetime(?) AND datetime(received_at) < datetime(?)
    ''', [from, until]);
    final entries = await db.rawQuery('''
      SELECT * FROM tip_transactions
      WHERE datetime(received_at) >= datetime(?) AND datetime(received_at) < datetime(?)
      ORDER BY datetime(received_at) DESC, id DESC
    ''', [from, until]);
    final byRecipient = await db.rawQuery('''
      SELECT COALESCE(NULLIF(TRIM(recipient_name), ''), 'Belum ditentukan') AS recipient,
        SUM(CASE WHEN status != 'cancelled' THEN amount ELSE 0 END) AS received,
        SUM(CASE WHEN status = 'held' THEN amount ELSE 0 END) AS held,
        SUM(CASE WHEN status = 'handed_over' THEN amount ELSE 0 END) AS handed_over
      FROM tip_transactions
      WHERE datetime(received_at) >= datetime(?) AND datetime(received_at) < datetime(?)
      GROUP BY COALESCE(NULLIF(TRIM(recipient_name), ''), 'Belum ditentukan')
      ORDER BY received DESC, recipient COLLATE NOCASE
    ''', [from, until]);
    return {...rows.first, 'entries': entries, 'by_recipient': byRecipient};
  }
}
