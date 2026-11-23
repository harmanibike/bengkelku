import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_session.dart';

import '../../../core/database/app_database.dart';

class SupplierRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getSuppliers({String keyword = ''}) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    final term = keyword.trim();
    return db.query(
      'suppliers',
      where: term.isEmpty ? null : '(name LIKE ? OR phone LIKE ? OR email LIKE ?)',
      whereArgs: term.isEmpty ? null : ['%$term%', '%$term%', '%$term%'],
      orderBy: 'name COLLATE NOCASE ASC',
    );
  }

  Future<int> addSupplier({required String name, String? phone, String? address, String? email, String? notes}) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pemasok wajib diisi.');
    final db = await _db;
    return db.insert('suppliers', {
      'name': cleanName, 'phone': _nullable(phone), 'address': _nullable(address),
      'email': _nullable(email), 'notes': _nullable(notes),
    });
  }

  Future<int> updateSupplier({required int id, required String name, String? phone, String? address, String? email, String? notes}) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pemasok wajib diisi.');
    final db = await _db;
    return db.update('suppliers', {
      'name': cleanName, 'phone': _nullable(phone), 'address': _nullable(address),
      'email': _nullable(email), 'notes': _nullable(notes),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countPurchases(int supplierId) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    final rows = await db.rawQuery("SELECT COUNT(*) AS total FROM purchases WHERE supplier_id = ? AND status = 'active'", [supplierId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<Map<String, Object?>> getSupplierSummary(int supplierId) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS invoice_count,
        COALESCE(SUM(total), 0) AS total_amount,
        COALESCE(SUM(paid), 0) AS paid_amount,
        COALESCE(SUM(return_credit), 0) AS return_credit,
        COALESCE(SUM(MAX(total - paid - return_credit, 0)), 0) AS remaining_amount,
        COALESCE((SELECT SUM(pr.total_amount - pr.credit_applied - pr.refund_received)
          FROM purchase_returns pr JOIN purchases source ON source.id = pr.purchase_id
          WHERE source.supplier_id = purchases.supplier_id AND pr.status = 'active'), 0) AS available_return_credit
      FROM purchases WHERE supplier_id = ? AND status = 'active'
    ''', [supplierId]);
    return rows.first;
  }

  Future<List<Map<String, Object?>>> getSuppliersWithDebt() async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    return db.rawQuery('''
      SELECT s.id AS supplier_id, s.name AS supplier_name, s.phone,
        COUNT(p.id) AS invoice_count,
        COALESCE(SUM(p.total), 0) AS total_amount,
        COALESCE(SUM(p.paid), 0) AS paid_amount,
        COALESCE(SUM(p.return_credit), 0) AS return_credit,
        COALESCE(SUM(MAX(p.total - p.paid - p.return_credit, 0)), 0) AS remaining_amount
      FROM suppliers s
      JOIN purchases p ON p.supplier_id = s.id
      WHERE p.status = 'active' AND p.total > p.paid + p.return_credit
      GROUP BY s.id, s.name, s.phone
      ORDER BY remaining_amount DESC, s.name COLLATE NOCASE ASC
    ''');
  }

  Future<List<Map<String, Object?>>> getPurchaseHistory(int supplierId) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    return db.rawQuery('''
      SELECT p.id, p.invoice_number, p.purchase_date, p.subtotal, p.discount,
        p.total, p.paid, p.return_credit, p.payment_status, p.status,
        CASE WHEN p.status = 'active'
          THEN MAX(p.total - p.paid - p.return_credit, 0)
          ELSE 0 END AS remaining_amount,
        COALESCE((SELECT SUM(pr.total_amount) FROM purchase_returns pr
          WHERE pr.purchase_id = p.id AND pr.status = 'active'), 0) AS returned_amount,
        COALESCE((SELECT SUM(sp.amount) FROM supplier_payments sp
          WHERE sp.purchase_id = p.id), 0) AS payment_history_amount,
        COALESCE((SELECT SUM(a.amount) FROM supplier_return_credit_applications a
          WHERE a.purchase_id = p.id), 0) AS credit_application_amount,
        (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = p.id) AS item_count
      FROM purchases p
      WHERE p.supplier_id = ?
      ORDER BY p.purchase_date DESC, p.id DESC
    ''', [supplierId]);
  }

  Future<List<Map<String, Object?>>> getSupplierCreditApplications(int supplierId) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    return db.rawQuery('''
      SELECT a.id, a.amount, a.created_at, pr.return_number,
        target.invoice_number AS target_invoice
      FROM supplier_return_credit_applications a
      JOIN purchase_returns pr ON pr.id = a.return_id
      JOIN purchases target ON target.id = a.purchase_id
      WHERE a.supplier_id = ?
      ORDER BY a.created_at DESC, a.id DESC
    ''', [supplierId]);
  }

  Future<List<Map<String, Object?>>> getSupplierPayments(int supplierId) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    return db.rawQuery('''
      SELECT sp.*, p.invoice_number
      FROM supplier_payments sp
      LEFT JOIN purchases p ON p.id = sp.purchase_id
      WHERE sp.supplier_id = ?
      ORDER BY sp.payment_date DESC, sp.id DESC
    ''', [supplierId]);
  }


  /// Rincian ledger satu faktur: item, pembayaran, retur, dan pemakaian kredit.
  Future<Map<String, Object?>> getPurchaseLedgerDetail(int purchaseId) async {
    AuthSession.instance.requireAdmin('Data pemasok dan pembelian hanya dapat diakses Admin.');

    final db = await _db;
    final invoices = await db.rawQuery('''
      SELECT p.*, s.name AS supplier_name
      FROM purchases p
      LEFT JOIN suppliers s ON s.id = p.supplier_id
      WHERE p.id = ?
      LIMIT 1
    ''', [purchaseId]);
    if (invoices.isEmpty) throw StateError('Faktur pembelian tidak ditemukan.');

    final items = await db.query(
      'purchase_items',
      where: 'purchase_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'id ASC',
    );
    final payments = await db.query(
      'supplier_payments',
      where: 'purchase_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'datetime(payment_date) ASC, id ASC',
    );
    final returns = await db.rawQuery('''
      SELECT pr.*,
        COALESCE((SELECT SUM(pri.quantity) FROM purchase_return_items pri
          WHERE pri.purchase_return_id = pr.id), 0) AS item_count
      FROM purchase_returns pr
      WHERE pr.purchase_id = ?
      ORDER BY datetime(pr.return_date) ASC, pr.id ASC
    ''', [purchaseId]);
    final creditApplications = await db.rawQuery('''
      SELECT a.amount, a.created_at, pr.return_number,
        target.invoice_number AS target_invoice
      FROM supplier_return_credit_applications a
      JOIN purchase_returns pr ON pr.id = a.return_id
      JOIN purchases target ON target.id = a.purchase_id
      WHERE a.purchase_id = ?
      ORDER BY datetime(a.created_at) ASC, a.id ASC
    ''', [purchaseId]);

    return {
      'invoice': invoices.first,
      'items': items,
      'payments': payments,
      'returns': returns,
      'credit_applications': creditApplications,
    };
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
