import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../../features/settings/data/business_settings_repository.dart';

class StockReminderNotificationService {
  StockReminderNotificationService._();

  static final StockReminderNotificationService instance =
      StockReminderNotificationService._();

  static const int _notificationId = 7811;
  static const String _channelId = 'bengkelku_stock_reminder';
  static const String _lastShownKey = 'stock_reminder_last_shown_date';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initializing;

  Future<void> _initialize() async {
    if (_initialized) return;
    if (_initializing != null) {
      await _initializing;
      return;
    }
    _initializing = _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    ).then((_) {});
    try {
      await _initializing;
      _initialized = true;
    } finally {
      _initializing = null;
    }
  }

  Future<bool> requestPermissionAndSync() async {
    try {
      await _initialize();
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      if (granted) await syncStockReminder();
      return granted;
    } catch (_) {
      return false;
    }
  }

  Future<int> _lowStockCount(Database db, StockReminderSettings settings) async {
    if (!settings.enabled) return 0;
    final condition = settings.checkAtMinimumStock
        ? 'stock <= minimum_stock'
        : 'stock <= 0';
    return Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(*)
      FROM products
      WHERE is_active = 1
        AND track_stock = 1
        AND $condition
    ''')) ?? 0;
  }

  Future<void> syncStockReminder() async {
    try {
      await _initialize();
      final settings = await BusinessSettingsRepository().getStockReminderSettings();
      final db = await AppDatabase.instance.database;
      final count = await _lowStockCount(db, settings);
      if (count == 0) {
        await _plugin.cancel(id: _notificationId);
        return;
      }

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final allowed = await android?.areNotificationsEnabled() ?? false;
      if (!allowed) return;

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Pengingat Stok BengkelKu',
          channelDescription: 'Pengingat produk yang stoknya menipis atau habis.',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      );
      final body =
          'Ada $count produk yang stoknya mencapai batas minimum. Buka BengkelKu POS untuk memeriksa dan mengisi ulang stok.';

      if (settings.repeatDaily) {
        await _plugin.periodicallyShow(
          id: _notificationId,
          title: 'Pengingat Stok BengkelKu',
          body: body,
          repeatInterval: RepeatInterval.daily,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } else {
        await _plugin.cancel(id: _notificationId);
        final today = DateTime.now();
        final dateKey =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        final rows = await db.query(
          'app_settings',
          columns: ['setting_value'],
          where: 'setting_key = ?',
          whereArgs: [_lastShownKey],
          limit: 1,
        );
        if (rows.isEmpty || rows.first['setting_value']?.toString() != dateKey) {
          await _plugin.show(
            id: _notificationId,
            title: 'Pengingat Stok BengkelKu',
            body: body,
            notificationDetails: details,
          );
          await db.insert('app_settings', {
            'setting_key': _lastShownKey,
            'setting_value': dateKey,
            'updated_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    } catch (_) {
      // Kegagalan notifikasi tidak boleh mengganggu transaksi atau operasi stok.
    }
  }

  Future<void> cancelStockReminder() async {
    try {
      await _initialize();
      await _plugin.cancel(id: _notificationId);
    } catch (_) {
      // Abaikan jika layanan notifikasi perangkat tidak tersedia.
    }
  }
}
