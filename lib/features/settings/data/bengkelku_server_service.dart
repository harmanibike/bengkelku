import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'local_api_server.dart';

/// Controls the Android foreground service that owns the LAN API listener.
/// The task isolate deliberately hosts health-check only; it does not open
/// the app database or process business transactions.
class BengkelKuServerService {
  BengkelKuServerService._();

  static final BengkelKuServerService instance = BengkelKuServerService._();
  static const int _serviceId = 8765;
  static bool _initialized = false;

  static void initialize() {
    if (_initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'bengkelku_server_service',
        channelName: 'Layanan Server BengkelKu',
        channelDescription:
            'Menampilkan status layanan Server BengkelKu saat aktif.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: false,
        allowWifiLock: false,
        stopWithTask: false,
      ),
    );
    _initialized = true;
  }

  Future<bool> get isRunning async {
    if (!Platform.isAndroid) return false;
    initialize();
    return FlutterForegroundTask.isRunningService;
  }

  Future<int> startServer() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Layanan Server hanya tersedia pada Android.');
    }
    initialize();

    if (await FlutterForegroundTask.isRunningService) {
      return LocalApiServer.defaultPort;
    }

    final started = Completer<int>();
    void onTaskData(Object data) {
      if (data is! Map) return;
      if (data['type'] == 'server_started' && !started.isCompleted) {
        started.complete(data['port'] as int? ?? LocalApiServer.defaultPort);
      } else if (data['type'] == 'server_start_failed' &&
          !started.isCompleted) {
        started.completeError(
          StateError(data['message']?.toString() ?? 'Gagal memulai Server.'),
        );
      }
    }

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      final requested =
          await FlutterForegroundTask.requestNotificationPermission();
      if (requested != NotificationPermission.granted) {
        throw StateError(
          'Izin notifikasi diperlukan agar status Server terlihat saat aktif.',
        );
      }
    }

    FlutterForegroundTask.addTaskDataCallback(onTaskData);
    try {
      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: 'BengkelKu Server aktif',
        notificationText: 'Layanan jaringan lokal sedang berjalan.',
        callback: startBengkelKuServerCallback,
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
      );
      return await started.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
          'Layanan Server belum memberi konfirmasi. Periksa notifikasi Android.',
        ),
      );
    } catch (_) {
      // Jangan tinggalkan foreground service aktif bila API gagal bind atau
      // tidak mengirim konfirmasi dalam batas waktu.
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      rethrow;
    } finally {
      FlutterForegroundTask.removeTaskDataCallback(onTaskData);
    }
  }

  Future<void> stopServer() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
  }
}

@pragma('vm:entry-point')
void startBengkelKuServerCallback() {
  FlutterForegroundTask.setTaskHandler(BengkelKuServerTaskHandler());
}

class BengkelKuServerTaskHandler extends TaskHandler {
  final LocalApiServer _server = LocalApiServer.instance;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      final port = await _server.start();
      FlutterForegroundTask.sendDataToMain({
        'type': 'server_started',
        'port': port,
      });
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'server_start_failed',
        'message': error.toString(),
      });
      // Hentikan notifikasi/service yang tidak memiliki listener aktif.
      await FlutterForegroundTask.stopService();
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _server.stop();
  }
}
