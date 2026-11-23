import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/activity_log_repository.dart';

class StockOpnameRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getSessions() async {
    final db = await _db;
    return db.rawQuery('''
      SELECT s.*, COUNT(i.id) item_count,
        SUM(CASE WHEN i.counted_quantity IS NOT NULL THEN 1 ELSE 0 END) counted_count,
        SUM(CASE WHEN i.counted_quantity IS NOT NULL THEN i.variance ELSE 0 END) total_variance
      FROM stock_opname_sessions s
      LEFT JOIN stock_opname_items i ON i.session_id=s.id
      GROUP BY s.id ORDER BY s.id DESC
    ''');
  }

  Future<int> createSession() async {
    final db = await _db;
    return db.transaction((txn) async {
      final id = await txn.insert('stock_opname_sessions', {
        'opname_number': 'OPN-${DateTime.now().millisecondsSinceEpoch}',
        'status': 'draft',
        'created_at': DateTime.now().toIso8601String(),
      });
      await txn.execute('''
        INSERT INTO stock_opname_items
          (session_id,product_id,product_name,sku,unit,system_quantity)
        SELECT ?,id,name,sku,unit,stock FROM products
        WHERE is_active=1 AND track_stock=1 ORDER BY name COLLATE NOCASE
      ''', [id]);
      final count = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM stock_opname_items WHERE session_id=?', [id])) ?? 0;
      if (count == 0) throw StateError('Tidak ada produk aktif yang melacak stok.');
      await ActivityLogRepository.record(
        txn,
        action: 'stock_opname_created',
        description: 'Membuat sesi stok opname dengan $count produk.',
        entityType: 'stock_opname',
        entityId: id,
      );
      return id;
    });
  }

  Future<List<Map<String, Object?>>> getItems(int id) async {
    final db = await _db;
    return db.query('stock_opname_items', where: 'session_id=?',
      whereArgs: [id], orderBy: 'product_name COLLATE NOCASE');
  }

  Future<void> setCount(int itemId, int quantity) async {
    if (quantity < 0) throw ArgumentError('Jumlah fisik tidak boleh negatif.');
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.rawQuery('''
        SELECT i.system_quantity,s.status FROM stock_opname_items i
        JOIN stock_opname_sessions s ON s.id=i.session_id WHERE i.id=?
      ''', [itemId]);
      if (rows.isEmpty || rows.first['status'] != 'draft') {
        throw StateError('Sesi opname tidak ditemukan atau sudah diterapkan.');
      }
      final system = rows.first['system_quantity'] as int? ?? 0;
      await txn.update('stock_opname_items', {
        'counted_quantity': quantity, 'variance': quantity-system,
        'counted_at': DateTime.now().toIso8601String(),
      }, where: 'id=?', whereArgs: [itemId]);
    });
  }

  Future<void> applySession(int sessionId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final sessions = await txn.query('stock_opname_sessions',
        where: 'id=?', whereArgs: [sessionId], limit: 1);
      if (sessions.isEmpty || sessions.first['status'] != 'draft') {
        throw StateError('Sesi opname tidak tersedia atau sudah diterapkan.');
      }
      final items = await txn.query('stock_opname_items',
        where: 'session_id=?', whereArgs: [sessionId]);
      if (items.isEmpty || items.any((i) => i['counted_quantity'] == null)) {
        throw StateError('Hitung semua produk sebelum menerapkan hasil opname.');
      }
      final now = DateTime.now().toIso8601String();
      for (final item in items) {
        final pid = item['product_id'] as int?;
        if (pid == null) continue;
        final product = await txn.query('products',
          columns: ['stock','purchase_price','track_stock'],
          where: 'id=?', whereArgs: [pid], limit: 1);
        if (product.isEmpty || (product.first['track_stock'] as int? ?? 1) != 1) {
          throw StateError('Produk ${item['product_name']} tidak lagi melacak stok.');
        }
        final before = product.first['stock'] as int? ?? 0;
        final snapshotStock = item['system_quantity'] as int? ?? 0;
        if (before != snapshotStock) {
          throw StateError('Stok ${item['product_name']} berubah sejak sesi dibuat (awal $snapshotStock, sekarang $before). Buat sesi opname baru agar transaksi selama penghitungan tidak tertimpa.');
        }
        final counted = item['counted_quantity'] as int;
        final delta = counted-before;
        if (delta == 0) continue;
        if (delta > 0) {
          await txn.insert('inventory_cost_batches', {
            'product_id': pid, 'batch_code': 'OPN-$sessionId-$pid',
            'quantity_received': delta, 'quantity_remaining': delta,
            'unit_cost': product.first['purchase_price'] as int? ?? 0,
            'received_at': now, 'notes': 'Penyesuaian stok opname',
          });
        } else {
          var remaining = -delta;
          final batches = await txn.query('inventory_cost_batches',
            where: 'product_id=? AND quantity_remaining>0', whereArgs: [pid],
            orderBy: 'received_at ASC,id ASC');
          for (final batch in batches) {
            if (remaining == 0) break;
            final available = batch['quantity_remaining'] as int? ?? 0;
            final take = available < remaining ? available : remaining;
            if (take <= 0) continue;
            await txn.update('inventory_cost_batches',
              {'quantity_remaining': available-take},
              where: 'id=?', whereArgs: [batch['id']]);
            remaining -= take;
          }
          if (remaining > 0) {
            throw StateError('Saldo batch biaya ${item['product_name']} tidak cukup. Penyesuaian dibatalkan agar nilai persediaan tetap konsisten.');
          }
        }
        await txn.update('products', {'stock': counted,'updated_at': now},
          where: 'id=?', whereArgs: [pid]);
        await txn.insert('stock_movements', {
          'product_id': pid, 'movement_type': delta > 0 ? 'in' : 'out',
          'quantity': delta.abs(), 'stock_before': before,'stock_after': counted,
          'reference_type': 'stock_opname','reference_id': sessionId,
          'notes': 'Penyesuaian hasil stok opname ${sessions.first['opname_number']}',
        });
      }
      await txn.update('stock_opname_sessions',
        {'status':'applied','applied_at':now},
        where:'id=?',whereArgs:[sessionId]);
      final changedCount = items.where((item) =>
        (item['counted_quantity'] as int? ?? item['system_quantity'] as int? ?? 0) !=
        (item['system_quantity'] as int? ?? 0)).length;
      await ActivityLogRepository.record(
        txn,
        action: 'stock_opname_applied',
        description: 'Menerapkan stok opname ${sessions.first['opname_number']} dengan $changedCount produk mengalami perubahan stok.',
        entityType: 'stock_opname',
        entityId: sessionId,
      );
    });
  }
}
