import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';

class PaymentMethodsRepository {
  static const settingKey = 'payment_methods';

  static const defaultMethods = <Map<String, String>>[
    {'code': 'cash', 'name': 'Tunai'},
    {'code': 'bank_transfer', 'name': 'Transfer Bank'},
    {'code': 'qris', 'name': 'QRIS'},
    {'code': 'debit_card', 'name': 'Kartu Debit'},
    {'code': 'credit_card', 'name': 'Kartu Kredit'},
    {'code': 'e_wallet', 'name': 'E-Wallet'},
  ];

  Future<Database> get _db => AppDatabase.instance.database;

  static const detailKeys = <String>[
    'qris_image_path',
    'bank_name',
    'bank_account_number',
    'bank_account_holder',
  ];

  Future<Map<String, String>> getPaymentDetails() async {
    AuthSession.instance.requireCashierOrAdmin('Detail pembayaran hanya dapat diakses Admin dan Kasir.');
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_key', 'setting_value'],
      where: 'setting_key IN (?, ?, ?, ?)',
      whereArgs: detailKeys,
    );
    return {
      for (final row in rows)
        row['setting_key'].toString(): row['setting_value']?.toString() ?? '',
    };
  }

  Future<void> savePaymentDetails(Map<String, String> details) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah detail pembayaran.');
    final db = await _db;
    final batch = db.batch();
    for (final key in detailKeys) {
      batch.insert(
        'app_settings',
        {
          'setting_key': key,
          'setting_value': details[key] ?? '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, String>>> getMethods() async {
    AuthSession.instance.requireCashierOrAdmin('Metode pembayaran hanya dapat diakses Admin dan Kasir.');
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
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengatur metode pembayaran.');
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
