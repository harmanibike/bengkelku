import 'package:sqflite/sqflite.dart';

import '../../../core/auth/activity_log_repository.dart';
import '../../../core/auth/auth_session.dart';
import '../../../core/database/app_database.dart';

class EquipmentRepository {
  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, Object?>>> getAssets({String keyword = '', String status = 'all'}) async {
    AuthSession.instance.requireCashierOrAdmin('Akses inventaris tidak tersedia untuk akun Mekanik.');
    final db = await _db;
    final filters = <String>[];
    final args = <Object?>[];
    if (keyword.trim().isNotEmpty) {
      filters.add('(asset_code LIKE ? OR name LIKE ? OR category LIKE ? OR brand LIKE ? OR serial_number LIKE ?)');
      final q = '%${keyword.trim()}%';
      args.addAll([q, q, q, q, q]);
    }
    if (status != 'all') {
      filters.add('status = ?');
      args.add(status);
    }
    return db.query('equipment_assets',
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: "CASE status WHEN 'active' THEN 0 WHEN 'repair' THEN 1 WHEN 'damaged' THEN 2 ELSE 3 END, name COLLATE NOCASE");
  }

  Future<int> saveAsset({
    int? id, required String code, required String name, String? category,
    String? brand, String? model, String? serialNumber, String? purchaseDate,
    String? supplierName, int purchaseCost = 0, String condition = 'Baik',
    String status = 'active', String? location, String? responsiblePerson,
    String? warrantyUntil, String? notes,
  }) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengelola inventaris peralatan.');
    if (code.trim().isEmpty || name.trim().isEmpty) throw ArgumentError('Kode aset dan nama peralatan wajib diisi.');
    if (purchaseCost < 0) throw ArgumentError('Harga perolehan tidak boleh negatif.');
    final db = await _db;
    return db.transaction((txn) async {
      final values = <String, Object?>{
        'asset_code': code.trim(), 'name': name.trim(), 'category': _clean(category),
        'brand': _clean(brand), 'model': _clean(model), 'serial_number': _clean(serialNumber),
        'purchase_date': _clean(purchaseDate), 'supplier_name': _clean(supplierName),
        'purchase_cost': purchaseCost, 'condition_label': condition, 'status': status,
        'location': _clean(location), 'responsible_person': _clean(responsiblePerson),
        'warranty_until': _clean(warrantyUntil), 'notes': _clean(notes),
        'updated_at': DateTime.now().toIso8601String(),
      };
      final assetId = id == null
        ? await txn.insert('equipment_assets', values)
        : (await txn.update('equipment_assets', values, where: 'id = ?', whereArgs: [id]) > 0 ? id : 0);
      if (assetId == 0) throw StateError('Data peralatan tidak ditemukan.');
      await ActivityLogRepository.record(txn,
        action: id == null ? 'equipment_created' : 'equipment_updated',
        description: id == null ? 'Menambahkan peralatan ${name.trim()}.' : 'Memperbarui data peralatan ${name.trim()}.',
        entityType: 'equipment_asset', entityId: assetId);
      return assetId;
    });
  }

  Future<int> updateStatus(int id, String status) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah status peralatan.');
    if (!['active', 'repair', 'damaged', 'retired'].contains(status)) throw ArgumentError('Status tidak valid.');
    final db = await _db;
    return db.transaction((txn) async {
      final rows = await txn.query('equipment_assets', columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isEmpty) return 0;
      final result = await txn.update('equipment_assets', {'status': status, 'updated_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
      await ActivityLogRepository.record(txn, action: 'equipment_status_changed',
        description: 'Mengubah status peralatan ${rows.first['name']} menjadi $status.',
        entityType: 'equipment_asset', entityId: id);
      return result;
    });
  }

  Future<List<Map<String, Object?>>> getMaintenanceLogs(int assetId) async {
    AuthSession.instance.requireCashierOrAdmin('Akses riwayat perawatan tidak tersedia untuk akun Mekanik.');
    final db = await _db;
    return db.query('equipment_maintenance_logs', where: 'asset_id = ?', whereArgs: [assetId], orderBy: 'maintenance_date DESC, id DESC');
  }

  Future<int> addMaintenance({
    required int assetId, required String date, required String type,
    required String description, int cost = 0, String? performedBy,
    String? nextDueDate, String? notes,
  }) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mencatat perawatan peralatan.');
    if (description.trim().isEmpty || type.trim().isEmpty) throw ArgumentError('Jenis dan keterangan perawatan wajib diisi.');
    if (cost < 0) throw ArgumentError('Biaya perawatan tidak boleh negatif.');
    final db = await _db;
    return db.transaction((txn) async {
      final asset = await txn.query('equipment_assets', columns: ['name'], where: 'id = ?', whereArgs: [assetId], limit: 1);
      if (asset.isEmpty) throw StateError('Peralatan tidak ditemukan.');
      final id = await txn.insert('equipment_maintenance_logs', {
        'asset_id': assetId, 'maintenance_date': date, 'maintenance_type': type.trim(),
        'description': description.trim(), 'cost': cost, 'performed_by': _clean(performedBy),
        'next_due_date': _clean(nextDueDate), 'notes': _clean(notes),
      });
      await ActivityLogRepository.record(txn, action: 'equipment_maintenance_added',
        description: 'Mencatat perawatan ${asset.first['name']}: ${type.trim()}.',
        entityType: 'equipment_asset', entityId: assetId);
      return id;
    });
  }

  String? _clean(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
}
