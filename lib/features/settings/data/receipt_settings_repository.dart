import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';

class ReceiptPrintSettings {
  const ReceiptPrintSettings({
    this.paperWidthMm = 58,
    this.showLogo = true,
    this.showBusinessName = true,
    this.showBusinessAddress = true,
    this.showBusinessContact = true,
    this.showCustomerDetails = true,
    this.showTransactionNotes = true,
    this.showFooter = true,
    this.fontScale = 1,
    this.spacing = 1,
  });

  final int paperWidthMm;
  final bool showLogo;
  final bool showBusinessName;
  final bool showBusinessAddress;
  final bool showBusinessContact;
  final bool showCustomerDetails;
  final bool showTransactionNotes;
  final bool showFooter;
  final double fontScale;
  final double spacing;

  double get paperWidthPoints => paperWidthMm == 80 ? 226.8 : 164.4;
  double get marginPoints => paperWidthMm == 80 ? 10 : 8;

  Map<String, Object?> toJson() => {
    'paperWidthMm': paperWidthMm,
    'showLogo': showLogo,
    'showBusinessName': showBusinessName,
    'showBusinessAddress': showBusinessAddress,
    'showBusinessContact': showBusinessContact,
    'showCustomerDetails': showCustomerDetails,
    'showTransactionNotes': showTransactionNotes,
    'showFooter': showFooter,
    'fontScale': fontScale,
    'spacing': spacing,
  };

  factory ReceiptPrintSettings.fromJson(Map<String, dynamic> json) {
    bool flag(String key, bool fallback) => json[key] is bool ? json[key] as bool : fallback;
    double number(String key, double fallback) => json[key] is num ? (json[key] as num).toDouble() : fallback;
    return ReceiptPrintSettings(
      paperWidthMm: json['paperWidthMm'] == 80 ? 80 : 58,
      showLogo: flag('showLogo', true),
      showBusinessName: flag('showBusinessName', true),
      showBusinessAddress: flag('showBusinessAddress', true),
      showBusinessContact: flag('showBusinessContact', true),
      showCustomerDetails: flag('showCustomerDetails', true),
      showTransactionNotes: flag('showTransactionNotes', true),
      showFooter: flag('showFooter', true),
      fontScale: number('fontScale', 1).clamp(0.85, 1.25).toDouble(),
      spacing: number('spacing', 1).clamp(0.7, 1.6).toDouble(),
    );
  }

  ReceiptPrintSettings copyWith({
    int? paperWidthMm,
    bool? showLogo,
    bool? showBusinessName,
    bool? showBusinessAddress,
    bool? showBusinessContact,
    bool? showCustomerDetails,
    bool? showTransactionNotes,
    bool? showFooter,
    double? fontScale,
    double? spacing,
  }) => ReceiptPrintSettings(
    paperWidthMm: paperWidthMm ?? this.paperWidthMm,
    showLogo: showLogo ?? this.showLogo,
    showBusinessName: showBusinessName ?? this.showBusinessName,
    showBusinessAddress: showBusinessAddress ?? this.showBusinessAddress,
    showBusinessContact: showBusinessContact ?? this.showBusinessContact,
    showCustomerDetails: showCustomerDetails ?? this.showCustomerDetails,
    showTransactionNotes: showTransactionNotes ?? this.showTransactionNotes,
    showFooter: showFooter ?? this.showFooter,
    fontScale: fontScale ?? this.fontScale,
    spacing: spacing ?? this.spacing,
  );
}

class ReceiptSettingsRepository {
  static const _receiptKey = 'receipt_print_settings';
  static const _drawerKey = 'cash_drawer_auto_open';

  Future<Database> get _db => AppDatabase.instance.database;

  Future<ReceiptPrintSettings> getReceiptSettings() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [_receiptKey],
      limit: 1,
    );
    if (rows.isEmpty) return const ReceiptPrintSettings();
    try {
      final decoded = jsonDecode(rows.first['setting_value']?.toString() ?? '');
      if (decoded is Map<String, dynamic>) return ReceiptPrintSettings.fromJson(decoded);
    } catch (_) {
      // Pengaturan yang rusak diabaikan dan memakai nilai aman bawaan.
    }
    return const ReceiptPrintSettings();
  }

  Future<void> saveReceiptSettings(ReceiptPrintSettings settings) async {
    final db = await _db;
    await db.insert('app_settings', {
      'setting_key': _receiptKey,
      'setting_value': jsonEncode(settings.toJson()),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> getCashDrawerAutoOpen() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: [_drawerKey],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['setting_value']?.toString() == '1';
  }

  Future<void> saveCashDrawerAutoOpen(bool enabled) async {
    final db = await _db;
    await db.insert('app_settings', {
      'setting_key': _drawerKey,
      'setting_value': enabled ? '1' : '0',
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
