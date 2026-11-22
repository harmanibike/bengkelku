import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class ReceivableRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getReceivables({
    String type = 'all',
    String keyword = '',
  }) async {
    final db = await _db;
    final term = keyword.trim();
    final rows = <Map<String, Object?>>[];

    if (type == 'all' || type == 'service') {
      rows.addAll(await db.rawQuery('''
        SELECT
          'service' AS receivable_type,
          s.id AS record_id,
          s.order_number AS invoice_number,
          s.received_at AS transaction_date,
          s.total_cost AS total_amount,
          s.down_payment AS paid_amount,
          s.remaining_payment AS remaining_amount,
          s.service_status AS record_status,
          c.name AS customer_name,
          c.phone AS customer_phone
        FROM service_orders s
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE s.remaining_payment > 0
          AND s.service_status != 'cancelled'
          AND (? = '' OR s.order_number LIKE ? OR COALESCE(c.name, '') LIKE ? OR COALESCE(c.phone, '') LIKE ?)
        ORDER BY s.received_at ASC, s.id ASC
      ''', [term, '%$term%', '%$term%', '%$term%']));
    }

    if (type == 'sale' || type == 'all') {
      rows.addAll(await db.rawQuery('''
        SELECT
          'sale' AS receivable_type,
          s.id AS record_id,
          s.invoice_number AS invoice_number,
          s.transaction_date AS transaction_date,
          s.total AS total_amount,
          s.paid AS paid_amount,
          (s.total - COALESCE(ret.returned_amount, 0) - s.paid + COALESCE(ret.refunded_amount, 0)) AS remaining_amount,
          s.payment_status AS record_status,
          c.name AS customer_name,
          c.phone AS customer_phone
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
        LEFT JOIN (
          SELECT sale_id,
                 SUM(total_amount) AS returned_amount,
                 SUM(refunded_amount) AS refunded_amount
          FROM sale_returns
          GROUP BY sale_id
        ) ret ON ret.sale_id = s.id
        WHERE (s.total - COALESCE(ret.returned_amount, 0) - s.paid + COALESCE(ret.refunded_amount, 0)) > 0
          AND s.payment_status != 'cancelled'
          AND (? = '' OR s.invoice_number LIKE ? OR COALESCE(c.name, '') LIKE ? OR COALESCE(c.phone, '') LIKE ?)
        ORDER BY s.transaction_date ASC, s.id ASC
      ''', [term, '%$term%', '%$term%', '%$term%']));
    }

    rows.sort((a, b) => (a['transaction_date']?.toString() ?? '')
        .compareTo(b['transaction_date']?.toString() ?? ''));
    return rows;
  }

  Future<Map<String, Object?>> getReceivableDetail({
    required String type,
    required int recordId,
  }) async {
    final db = await _db;
    if (type == 'service') {
      final rows = await db.rawQuery('''
        SELECT s.*, c.name AS customer_name, c.phone AS customer_phone
        FROM service_orders s
        LEFT JOIN customers c ON c.id = s.customer_id
        WHERE s.id = ? LIMIT 1
      ''', [recordId]);
      if (rows.isEmpty) throw StateError('Nota servis tidak ditemukan.');
      final payments = await db.query(
        'cash_transactions',
        where: "reference_type = 'service_order' AND reference_id = ? AND transaction_type = 'income'",
        whereArgs: [recordId],
        orderBy: 'datetime(transaction_date) ASC, id ASC',
      );
      return {'record': rows.first, 'payments': payments, 'returns': <Map<String, Object?>>[]};
    }
    if (type == 'sale') {
      final rows = await db.rawQuery('''
        SELECT s.*, c.name AS customer_name, c.phone AS customer_phone,
          COALESCE(ret.returned_amount, 0) AS returned_amount,
          COALESCE(ret.refunded_amount, 0) AS refunded_amount
        FROM sales s
        LEFT JOIN customers c ON c.id = s.customer_id
        LEFT JOIN (
          SELECT sale_id, SUM(total_amount) AS returned_amount,
            SUM(refunded_amount) AS refunded_amount
          FROM sale_returns GROUP BY sale_id
        ) ret ON ret.sale_id = s.id
        WHERE s.id = ? LIMIT 1
      ''', [recordId]);
      if (rows.isEmpty) throw StateError('Nota penjualan tidak ditemukan.');
      final payments = await db.query(
        'cash_transactions',
        where: "reference_type IN ('sale', 'sale_payment') AND reference_id = ? AND transaction_type = 'income'",
        whereArgs: [recordId],
        orderBy: 'datetime(transaction_date) ASC, id ASC',
      );
      final returns = await db.query(
        'sale_returns',
        where: 'sale_id = ?',
        whereArgs: [recordId],
        orderBy: 'datetime(return_date) ASC, id ASC',
      );
      return {'record': rows.first, 'payments': payments, 'returns': returns};
    }
    throw ArgumentError('Jenis piutang tidak valid.');
  }

  Future<String> getTemplate() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['whatsapp_receivable_template'],
      limit: 1,
    );
    return rows.isEmpty || rows.first['setting_value'] == null
        ? 'Halo {nama}, kami ingin mengingatkan bahwa tagihan {jenis} dengan nomor nota {nota} pada tanggal {tanggal} masih tersisa {sisa}. Mohon konfirmasi pembayaran. Terima kasih.'
        : rows.first['setting_value'].toString();
  }

  Future<void> saveTemplate(String value) async {
    final db = await _db;
    await db.insert(
      'app_settings',
      {
        'setting_key': 'whatsapp_receivable_template',
        'setting_value': value,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> recordReminder({
    required String type,
    required int recordId,
    required String phone,
  }) async {
    final db = await _db;
    await db.insert('receivable_reminder_logs', {
      'receivable_type': type,
      'record_id': recordId,
      'phone': phone,
      'opened_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, Object?>?> getLastReminder(String type, int recordId) async {
    final db = await _db;
    final rows = await db.query(
      'receivable_reminder_logs',
      where: 'receivable_type = ? AND record_id = ?',
      whereArgs: [type, recordId],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }
}
