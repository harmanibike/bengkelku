import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'local_api_server.dart';
import 'server_tls_identity_repository.dart';
import 'device_pairing_repository.dart';
import 'device_pairing_rate_limiter.dart';

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
  static bool _callbackRegistered = false;
  static bool _identitySent = false;
  static int? _activePort;
  static int _bridgeRequestsInFlight = 0;
  static ServerTlsIdentity? _activeIdentity;
  static Completer<int>? _startupCompleter;
  static Future<void> _lifecycle = Future<void>.value();
  static final ServerTlsIdentityRepository _identityRepository =
      ServerTlsIdentityRepository(store: FlutterSecureValueStore());

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
    if (!_callbackRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
      _callbackRegistered = true;
    }
    _initialized = true;
  }

  static void _onTaskData(Object data) {
    if (data is! Map) return;
    final type = data['type'];
    if (type == 'server_identity_required') {
      final identity = _activeIdentity;
      if (identity == null || _identitySent) return;
      _identitySent = true;
      FlutterForegroundTask.sendDataToTask({
        'type': 'start_secure_server',
        'server_dns_name': identity.dnsName,
        'certificate_pem': identity.certificatePem,
        'private_key_pem': identity.privateKeyPem,
      });
    } else if (type == 'server_started') {
      final completer = _startupCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(data['port'] as int? ?? LocalApiServer.defaultPort);
      }
    } else if (type == 'server_start_failed') {
      final completer = _startupCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.completeError(
          StateError(data['message']?.toString() ?? 'Gagal memulai Server HTTPS.'),
        );
      }
    } else if (type == 'bridge_request') {
      unawaited(_respondToBridgeRequest(data));
    }
  }

  static Future<void> _respondToBridgeRequest(Map data) async {
    final requestId = data['request_id'];
    if (requestId is! String || requestId.isEmpty || requestId.length > 80) {
      return;
    }
    if (_bridgeRequestsInFlight >= 8) {
      FlutterForegroundTask.sendDataToTask({
        'type': 'bridge_response',
        'request_id': requestId,
        'ok': false,
        'error': 'busy',
      });
      return;
    }
    _bridgeRequestsInFlight++;
    try {
      final operation = data['operation'];
      if (operation == 'server_info') {
        final identity = _activeIdentity;
        if (identity == null) {
          FlutterForegroundTask.sendDataToTask({
            'type': 'bridge_response',
            'request_id': requestId,
            'ok': false,
            'error': 'server_not_ready',
          });
          return;
        }
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {
            'server_id': identity.serverId,
            'server_name': 'Bike POS Server',
            'app_version': LocalApiServer.appVersion,
            'api_version': LocalApiServer.apiVersion,
            'certificate_fingerprint': identity.fingerprint,
            'read_only': true,
          },
        });
        return;
      }
      if (operation == 'authenticate_device') {
        final payload = data['payload'];
        if (payload is! Map ||
            payload.keys.toSet().difference({'token'}).isNotEmpty ||
            payload['token'] is! String ||
            !RegExp(r'^[a-fA-F0-9]{64}$')
                .hasMatch(payload['token'] as String)) {
          FlutterForegroundTask.sendDataToTask({
            'type': 'bridge_response',
            'request_id': requestId,
            'ok': true,
            'data': {'status': 'rejected'},
          });
          return;
        }
        final device = await DevicePairingRepository().authenticateDevice(
          payload['token'] as String,
        );
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': device == null
              ? {'status': 'rejected'}
              : {
                  'status': 'authenticated',
                  'device_id': device.id,
                  'device_name': device.deviceName,
                  'created_at': device.createdAt,
                  'last_seen_at': device.lastSeenAt,
                },
        });
        return;
      }
      if (operation != 'pair_device') {
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': false,
          'error': 'operation_not_allowed',
        });
        return;
      }

      // Database dan rate limiter hanya diakses dari main isolate.
      final remoteAddress = data['remote_address']?.toString() ?? '';
      final payload = data['payload'];
      if (payload is! Map ||
          payload.keys.toSet().difference({'code', 'device_name'}).isNotEmpty ||
          payload['code'] is! String ||
          payload['device_name'] is! String) {
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {'status': 'invalid_code'},
        });
        return;
      }
      final limiter = DevicePairingRateLimiter();
      if (!await limiter.isAllowed(remoteAddress)) {
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {'status': 'rate_limited'},
        });
        return;
      }
      try {
        final credential = await DevicePairingRepository().pairDevice(
          code: payload['code'] as String,
          deviceName: payload['device_name'] as String,
        );
        await limiter.clearAfterSuccess(remoteAddress);
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {
            'status': 'paired',
            'device_id': credential.deviceId,
            'device_name': credential.deviceName,
            'token': credential.token,
          },
        });
      } on StateError {
        await limiter.recordFailure(remoteAddress);
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {'status': 'invalid_code'},
        });
      } on ArgumentError {
        await limiter.recordFailure(remoteAddress);
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {'status': 'invalid_code'},
        });
      } on Object {
        FlutterForegroundTask.sendDataToTask({
          'type': 'bridge_response',
          'request_id': requestId,
          'ok': true,
          'data': {'status': 'pairing_unavailable'},
        });
      }
    } finally {
      _bridgeRequestsInFlight--;
    }
  }

  Future<bool> get isRunning async {
    if (!Platform.isAndroid) return false;
    initialize();
    return FlutterForegroundTask.isRunningService;
  }

  Future<int> startServer() => _serializeLifecycle(_startServer);

  Future<int> _startServer() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Layanan Server hanya tersedia pada Android.');
    }
    initialize();
    if (await FlutterForegroundTask.isRunningService && _activePort != null) {
      return _activePort!;
    }

    // Load/create the identity on the main isolate where secure storage is
    // initialized. The foreground isolate must not open the business database
    // or independently generate a second server identity.
    final identity = await _identityRepository.loadOrCreate();

    // Replace an older listener from a previous app version. This ensures an
    // already-running plaintext health listener cannot be mistaken for TLS.
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    final started = Completer<int>();
    try {
      _activeIdentity = identity;
      _identitySent = false;
      _startupCompleter = started;
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

      await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: 'Bike POS Server aktif',
        notificationText: 'Menyiapkan koneksi HTTPS lokal...',
        callback: startBengkelKuServerCallback,
        serviceTypes: [ForegroundServiceTypes.connectedDevice],
      );
      final port = await started.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => throw TimeoutException(
          'Layanan Server HTTPS belum memberi konfirmasi. Periksa notifikasi Android.',
        ),
      );
      _activePort = port;
      return port;
    } catch (_) {
      _activePort = null;
      _activeIdentity = null;
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      rethrow;
    } finally {
      _startupCompleter = null;
    }
  }

  Future<void> stopServer() => _serializeLifecycle(_stopServer);

  Future<void> _stopServer() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
    _activePort = null;
    _activeIdentity = null;
  }

  /// Serializes start/stop requests so rapid taps cannot race service lifecycle.
  Future<T> _serializeLifecycle<T>(Future<T> Function() operation) {
    final result = _lifecycle.then((_) => operation());
    _lifecycle = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
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

  final Map<String, Completer<Map<String, dynamic>>> _pendingBridgeRequests = {};
  int _nextBridgeRequestId = 0;

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['type'] == 'bridge_response') {
      final requestId = data['request_id'];
      if (requestId is String) {
        final completer = _pendingBridgeRequests[requestId];
        if (completer != null && !completer.isCompleted) {
          if (data['ok'] == true && data['data'] is Map) {
            completer.complete(Map<String, dynamic>.from(data['data'] as Map));
          } else {
            completer.completeError(
              StateError(data['error']?.toString() ?? 'Permintaan bridge ditolak.'),
            );
          }
        }
      }
      return;
    }
    if (data is! Map || data['type'] != 'start_secure_server' || _starting) {
      return;
    }
    _starting = true;
    unawaited(_startSecureServer(data));
  }

  Future<Map<String, dynamic>> _requestMainIsolate(LocalApiBridgeRequest request) async {
    final isServerInfo = request.operation == 'server_info' && request.payload.isEmpty;
    final isAuthentication =
        request.operation == 'authenticate_device' &&
        request.payload.keys.toSet().difference({'token'}).isEmpty &&
        request.payload['token'] is String &&
        RegExp(r'^[a-fA-F0-9]{64}$')
            .hasMatch(request.payload['token'] as String);
    final isPairing = request.operation == 'pair_device' &&
        request.payload.keys.toSet().difference({'code', 'device_name'}).isEmpty &&
        request.payload['code'] is String &&
        request.payload['device_name'] is String;
    if (!isServerInfo && !isPairing && !isAuthentication) {
      throw StateError('Operasi bridge tidak diizinkan.');
    }
    if (_pendingBridgeRequests.length >= 8) {
      throw StateError('Antrean komunikasi Server sedang penuh.');
    }
    final requestId = request.requestId + '-rpc-' + (_nextBridgeRequestId++).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pendingBridgeRequests[requestId] = completer;
    try {
      FlutterForegroundTask.sendDataToMain({
        'type': 'bridge_request',
        'request_id': requestId,
        'operation': request.operation,
        'remote_address': request.remoteAddress,
        'payload': request.payload,
      });
      return await completer.future.timeout(const Duration(seconds: 4));
    } finally {
      _pendingBridgeRequests.remove(requestId);
    }
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
        bridgeHandler: _requestMainIsolate,
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
    for (final completer in _pendingBridgeRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Layanan Server dihentikan.'));
      }
    }
    _pendingBridgeRequests.clear();
    await _server.stop();
  }
}
