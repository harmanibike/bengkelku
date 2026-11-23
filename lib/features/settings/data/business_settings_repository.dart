import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';

class LoyaltySettings {
  const LoyaltySettings({
    this.enabled = false,
    this.spendAmountPerPoint = 10000,
    this.pointValue = 100,
    this.minimumRedeemPoints = 100,
  });

  final bool enabled;
  final int spendAmountPerPoint;
  final int pointValue;
  final int minimumRedeemPoints;

  LoyaltySettings copyWith({
    bool? enabled,
    int? spendAmountPerPoint,
    int? pointValue,
    int? minimumRedeemPoints,
  }) => LoyaltySettings(
    enabled: enabled ?? this.enabled,
    spendAmountPerPoint: spendAmountPerPoint ?? this.spendAmountPerPoint,
    pointValue: pointValue ?? this.pointValue,
    minimumRedeemPoints: minimumRedeemPoints ?? this.minimumRedeemPoints,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'spendAmountPerPoint': spendAmountPerPoint,
    'pointValue': pointValue,
    'minimumRedeemPoints': minimumRedeemPoints,
  };

  factory LoyaltySettings.fromJson(Map<String, dynamic> json) => LoyaltySettings(
    enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
    spendAmountPerPoint: _positiveInt(json['spendAmountPerPoint'], 10000),
    pointValue: _positiveInt(json['pointValue'], 100),
    minimumRedeemPoints: _positiveInt(json['minimumRedeemPoints'], 100),
  );
}

class StockReminderSettings {
  const StockReminderSettings({
    this.enabled = false,
    this.checkAtMinimumStock = true,
    this.repeatDaily = true,
  });

  final bool enabled;
  final bool checkAtMinimumStock;
  final bool repeatDaily;

  StockReminderSettings copyWith({
    bool? enabled,
    bool? checkAtMinimumStock,
    bool? repeatDaily,
  }) => StockReminderSettings(
    enabled: enabled ?? this.enabled,
    checkAtMinimumStock: checkAtMinimumStock ?? this.checkAtMinimumStock,
    repeatDaily: repeatDaily ?? this.repeatDaily,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'checkAtMinimumStock': checkAtMinimumStock,
    'repeatDaily': repeatDaily,
  };

  factory StockReminderSettings.fromJson(Map<String, dynamic> json) => StockReminderSettings(
    enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
    checkAtMinimumStock: json['checkAtMinimumStock'] is bool ? json['checkAtMinimumStock'] as bool : true,
    repeatDaily: json['repeatDaily'] is bool ? json['repeatDaily'] as bool : true,
  );
}

int _positiveInt(Object? value, int fallback) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  return fallback;
}

class BusinessSettingsRepository {
  static const _loyaltyKey = 'loyalty_program_settings';
  static const _stockReminderKey = 'stock_reminder_settings';

  Future<Database> get _db => AppDatabase.instance.database;

  Future<Map<String, dynamic>?> _read(String key) async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final decoded = jsonDecode(rows.first['setting_value']?.toString() ?? '');
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, Object?> value) async {
    final db = await _db;
    await db.insert('app_settings', {
      'setting_key': key,
      'setting_value': jsonEncode(value),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<LoyaltySettings> getLoyaltySettings() async =>
      LoyaltySettings.fromJson(await _read(_loyaltyKey) ?? {});

  Future<void> saveLoyaltySettings(LoyaltySettings settings) {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah pengaturan poin.');
    return _write(_loyaltyKey, settings.toJson());
  }

  Future<StockReminderSettings> getStockReminderSettings() async =>
      StockReminderSettings.fromJson(await _read(_stockReminderKey) ?? {});

  Future<void> saveStockReminderSettings(StockReminderSettings settings) {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah pengingat stok.');
    return _write(_stockReminderKey, settings.toJson());
  }
}
