import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class SupplierRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getSuppliers({String keyword = ''}) async {
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
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pemasok wajib diisi.');
    final db = await _db;
    return db.insert('suppliers', {
      'name': cleanName, 'phone': _nullable(phone), 'address': _nullable(address),
      'email': _nullable(email), 'notes': _nullable(notes),
    });
  }

  Future<int> updateSupplier({required int id, required String name, String? phone, String? address, String? email, String? notes}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Nama pemasok wajib diisi.');
    final db = await _db;
    return db.update('suppliers', {
      'name': cleanName, 'phone': _nullable(phone), 'address': _nullable(address),
      'email': _nullable(email), 'notes': _nullable(notes),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countPurchases(int supplierId) async {
    final db = await _db;
    final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM purchases WHERE supplier_id = ?', [supplierId]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Future<Map<String, Object?>> getSupplierSummary(int supplierId) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS invoice_count,
        COALESCE(SUM(total), 0) AS total_amount,
        COALESCE(SUM(paid), 0) AS paid_amount,
        COALESCE(SUM(return_credit), 0) AS return_credit,
        COALESCE(SUM(MAX(total - paid - return_credit, 0)), 0) AS remaining_amount,
        COALESCE((SELECT SUM(pr.total_amount - pr.credit_applied - pr.refund_received)
          FROM purchase_returns pr JOIN purchases source ON source.id = pr.purchase_id
          WHERE source.supplier_id = purchases.supplier_id), 0) AS available_return_credit
      FROM purchases WHERE supplier_id = ?
    ''', [supplierId]);
    return rows.first;
  }

  Future<List<Map<String, Object?>>> getSuppliersWithDebt() async {
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
      WHERE p.total > p.paid + p.return_credit
      GROUP BY s.id, s.name, s.phone
      ORDER BY remaining_amount DESC, s.name COLLATE NOCASE ASC
    ''');
  }

  Future<List<Map<String, Object?>>> getPurchaseHistory(int supplierId) async {
    final db = await _db;
    return db.rawQuery('''
      SELECT p.id, p.invoice_number, p.purchase_date, p.subtotal, p.discount,
        p.total, p.paid, p.return_credit, p.payment_status,
        MAX(p.total - p.paid - p.return_credit, 0) AS remaining_amount,
        (SELECT COUNT(*) FROM purchase_items pi WHERE pi.purchase_id = p.id) AS item_count
      FROM purchases p
      WHERE p.supplier_id = ?
      ORDER BY p.purchase_date DESC, p.id DESC
    ''', [supplierId]);
  }

  Future<List<Map<String, Object?>>> getSupplierCreditApplications(int supplierId) async {
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
    final db = await _db;
    return db.rawQuery('''
      SELECT sp.*, p.invoice_number
      FROM supplier_payments sp
      LEFT JOIN purchases p ON p.id = sp.purchase_id
      WHERE sp.supplier_id = ?
      ORDER BY sp.payment_date DESC, sp.id DESC
    ''', [supplierId]);
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
