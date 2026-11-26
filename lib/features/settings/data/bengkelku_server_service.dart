import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'local_api_server.dart';
import 'server_tls_identity_repository.dart';

/// Controls the Android foreground service that owns the LAN HTTPS listener.
///
/// The TLS identity is loaded on the UI isolate from encrypted storage. Only
/// the in-memory certificate/key material needed to configure the listener is
/// passed over the foreground-task isolate channel; it is never persisted by
/// that channel, logged, or included in pairing data.
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
        channelId: 'bike_pos_server_service',
        channelName: 'Layanan Server Bike POS',
        channelDescription:
            'Menampilkan status layanan Server Bike POS saat aktif.',
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
        allowWakeLock: true,
        allowWifiLock: true,
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

    // Load/create the identity on the main isolate where secure storage is
    // initialized. The foreground isolate must not open the business database
    // or independently generate a second server identity.
    final identity = await ServerTlsIdentityRepository(
      store: FlutterSecureValueStore(),
    ).loadOrCreate();

    // Replace an older listener from a previous app version. This ensures an
    // already-running plaintext health listener cannot be mistaken for TLS.
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    final started = Completer<int>();
    var identitySent = false;

    void onTaskData(Object data) {
      if (data is! Map) return;
      if (data['type'] == 'server_identity_required' && !identitySent) {
        identitySent = true;
        FlutterForegroundTask.sendDataToTask({
          'type': 'start_secure_server',
          'server_dns_name': identity.dnsName,
          'certificate_pem': identity.certificatePem,
          'private_key_pem': identity.privateKeyPem,
        });
      } else if (data['type'] == 'server_started' && !started.isCompleted) {
        started.complete(data['port'] as int? ?? LocalApiServer.defaultPort);
      } else if (data['type'] == 'server_start_failed' &&
          !started.isCompleted) {
        started.completeError(
          StateError(data['message']?.toString() ?? 'Gagal memulai Server HTTPS.'),
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
        notificationTitle: 'Bike POS Server aktif',
        notificationText: 'Menyiapkan koneksi HTTPS lokal...',
        callback: startBengkelKuServerCallback,
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
      );
      return await started.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Layanan Server HTTPS belum memberi konfirmasi. Periksa notifikasi Android.',
        ),
      );
    } catch (_) {
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
  bool _starting = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Wait for the main isolate to load the persistent TLS identity from
    // encrypted storage. Never fall back to plaintext HTTP.
    FlutterForegroundTask.updateService(
      notificationTitle: 'Bike POS Server',
      notificationText: 'Menunggu konfigurasi keamanan HTTPS...',
    );
    FlutterForegroundTask.sendDataToMain({
      'type': 'server_identity_required',
    });
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map || data['type'] != 'start_secure_server' || _starting) {
      return;
    }
    _starting = true;
    unawaited(_startSecureServer(data));
  }

  Future<void> _startSecureServer(Map data) async {
    try {
      final dnsName = data['server_dns_name']?.toString() ?? '';
      final certificatePem = data['certificate_pem']?.toString() ?? '';
      final privateKeyPem = data['private_key_pem']?.toString() ?? '';
      if (!RegExp(r'^bikepos-[a-f0-9]{32}\.invalid$').hasMatch(dnsName) ||
          !certificatePem.contains('-----BEGIN CERTIFICATE-----') ||
          !privateKeyPem.contains('PRIVATE KEY-----')) {
        throw StateError('Konfigurasi identitas TLS Server tidak valid.');
      }

      final securityContext = SecurityContext(withTrustedRoots: false)
        ..useCertificateChainBytes(utf8.encode(certificatePem))
        ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
      final port = await _server.startSecure(
        securityContext: securityContext,
        serverName: 'Bike POS Server',
      );
      FlutterForegroundTask.updateService(
        notificationTitle: 'Bike POS Server aktif',
        notificationText: 'HTTPS lokal aktif pada port $port.',
      );
      FlutterForegroundTask.sendDataToMain({
        'type': 'server_started',
        'port': port,
      });
    } catch (error) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'server_start_failed',
        'message': error.toString(),
      });
      await FlutterForegroundTask.stopService();
    } finally {
      _starting = false;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _server.stop();
  }
}
