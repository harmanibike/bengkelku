import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/auth/auth_session.dart';

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
    this.footerNote = '',
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
  final String footerNote;
  final double fontScale;
  final double spacing;

  double get paperWidthPoints => paperWidthMm == 80 ? 226.8 : 164.4;
  double get marginPoints => paperWidthMm == 80 ? 14 : 12;

  Map<String, Object?> toJson() => {
    'paperWidthMm': paperWidthMm,
    'showLogo': showLogo,
    'showBusinessName': showBusinessName,
    'showBusinessAddress': showBusinessAddress,
    'showBusinessContact': showBusinessContact,
    'showCustomerDetails': showCustomerDetails,
    'showTransactionNotes': showTransactionNotes,
    'showFooter': showFooter,
    'footerNote': footerNote,
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
      footerNote: json['footerNote']?.toString() ?? '',
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
    String? footerNote,
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
    footerNote: footerNote ?? this.footerNote,
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
    Map<String, dynamic> decoded = {};
    if (rows.isNotEmpty) {
      try {
        final value = jsonDecode(rows.first['setting_value']?.toString() ?? '');
        if (value is Map<String, dynamic>) decoded = value;
      } catch (_) {
        // Pengaturan yang rusak diabaikan dan memakai nilai aman bawaan.
      }
    }
    // Migrasi halus: ambil catatan lama dari Profil Usaha jika pengaturan
    // struk belum memiliki footerNote. Nilai lama tidak langsung dihapus.
    if (!decoded.containsKey('footerNote')) {
      final legacy = await db.query(
        'app_settings',
        columns: ['setting_value'],
        where: 'setting_key = ?',
        whereArgs: ['business_footer_note'],
        limit: 1,
      );
      if (legacy.isNotEmpty) decoded['footerNote'] = legacy.first['setting_value']?.toString() ?? '';
    }
    return ReceiptPrintSettings.fromJson(decoded);
  }

  Future<void> saveReceiptSettings(ReceiptPrintSettings settings) async {
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah format dokumen nota.');
    final db = await _db;
    await db.insert('app_settings', {
      'setting_key': _receiptKey,
      'setting_value': jsonEncode(settings.toJson()),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static const _printerNameKey = 'receipt_printer_name';
  static const _printerAddressKey = 'receipt_printer_address';

  Future<Map<String, String>?> getSavedPrinter() async {
    final db = await _db;
    final rows = await db.query(
      'app_settings',
      columns: ['setting_key', 'setting_value'],
      where: 'setting_key IN (?, ?)',
      whereArgs: [_printerNameKey, _printerAddressKey],
    );
    final values = <String, String>{};
    for (final row in rows) {
      values[row['setting_key'].toString()] = row['setting_value']?.toString() ?? '';
    }
    final name = values[_printerNameKey] ?? '';
    final address = values[_printerAddressKey] ?? '';
    if (name.isEmpty || address.isEmpty) return null;
    return {'name': name, 'address': address};
  }

  Future<void> savePrinter({required String name, required String address}) async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengatur printer.');
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      await txn.insert('app_settings', {
        'setting_key': _printerNameKey,
        'setting_value': name,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('app_settings', {
        'setting_key': _printerAddressKey,
        'setting_value': address,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> clearSavedPrinter() async {
    AuthSession.instance.requireCashierOrAdmin('Hanya Admin dan Kasir yang dapat mengatur printer.');
    final db = await _db;
    await db.delete(
      'app_settings',
      where: 'setting_key IN (?, ?)',
      whereArgs: [_printerNameKey, _printerAddressKey],
    );
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
    AuthSession.instance.requireAdmin('Hanya Admin yang dapat mengubah pengaturan laci kas.');
    final db = await _db;
    await db.insert('app_settings', {
      'setting_key': _drawerKey,
      'setting_value': enabled ? '1' : '0',
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
