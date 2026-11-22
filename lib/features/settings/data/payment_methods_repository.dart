import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class PaymentMethodsRepository {
  static const settingKey = 'payment_methods';

  static const defaultMethods = <Map<String, String>>[
    {'code': 'cash', 'name': 'Tunai'},
    {'code': 'bank_transfer', 'name': 'Transfer Bank'},
    {'code': 'qris', 'name': 'QRIS'},
    {'code': 'debit_card', 'name': 'Kartu Debit'},
    {'code': 'credit_card', 'name': 'Kartu Kredit'},
  ];

  Future<Database> get _db => AppDatabase.instance.database;

  Future<List<Map<String, String>>> getMethods() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [settingKey],
      limit: 1,
    );
    if (rows.isEmpty) return defaultMethods.map(Map<String, String>.from).toList();

    try {
      final decoded = jsonDecode(rows.first['setting_value']?.toString() ?? '');
      if (decoded is! List) return defaultMethods.map(Map<String, String>.from).toList();
      final enabled = decoded
          .whereType<String>()
          .toSet();
      final result = defaultMethods
          .where((method) => enabled.contains(method['code']))
          .map(Map<String, String>.from)
          .toList();
      return result.isEmpty ? defaultMethods.where((m) => m['code'] == 'cash').map(Map<String, String>.from).toList() : result;
    } catch (_) {
      return defaultMethods.map(Map<String, String>.from).toList();
    }
  }

  Future<Set<String>> getEnabledCodes() async {
    final methods = await getMethods();
    return methods.map((method) => method['code']!).toSet();
  }

  Future<void> saveEnabledCodes(Set<String> codes) async {
    final known = defaultMethods.map((method) => method['code']!).toSet();
    final valid = codes.intersection(known);
    if (valid.isEmpty) {
      throw ArgumentError('Minimal satu metode pembayaran harus diaktifkan.');
    }
    final db = await _db;
    await db.insert(
      'app_settings',
      {
        'setting_key': settingKey,
        'setting_value': jsonEncode(defaultMethods
            .map((method) => method['code']!)
            .where(valid.contains)
            .toList()),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
