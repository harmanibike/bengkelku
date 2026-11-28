import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// API jaringan lokal tahap awal. Hanya health-check dan metadata Server;
/// belum menyediakan akses transaksi atau database untuk perangkat Client.
class LocalApiBridgeRequest {
  const LocalApiBridgeRequest({required this.requestId, required this.operation, required this.remoteAddress, this.payload = const <String, Object?>{}});
  final String requestId;
  final String operation;
  final String remoteAddress;
  final Map<String, Object?> payload;
}

typedef LocalApiBridgeHandler = Future<Map<String, dynamic>> Function(
  LocalApiBridgeRequest request,
);

class LocalApiServer {
  static const int apiVersion = 1;
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
  static const String minimumClientVersion = '1.0.0';
  static const String maximumClientVersion = '1.0.99';
  static const int defaultPort = 8765;

  /// Instance condivisa a livello applicazione: non appartiene alla pagina UI.
  static final LocalApiServer instance = LocalApiServer();

  HttpServer? _server;
  Future<int>? _startFuture;
  Future<void>? _stopFuture;
  LocalApiBridgeHandler? _bridgeHandler;
  int _nextBridgeRequestId = 0;

  bool _isSecure = false;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Start idempotent: chiamate simultanee condividono lo stesso bind.
  Future<int> start({
    int port = defaultPort,
    String serverName = 'BengkelKu Server',
    LocalApiBridgeHandler? bridgeHandler,
  }) => _start(
        port: port,
        serverName: serverName,
        bridgeHandler: bridgeHandler,
      );

  /// Starts the same health API over TLS. The caller owns certificate
  /// loading and must keep the private key out of pairing responses/logs.
  Future<int> startSecure({
    required SecurityContext securityContext,
    int port = defaultPort,
    String serverName = 'BengkelKu Server',
    LocalApiBridgeHandler? bridgeHandler,
  }) => _start(
        port: port,
        serverName: serverName,
        securityContext: securityContext,
        bridgeHandler: bridgeHandler,
      );

  Future<int> _start({
    required int port,
    required String serverName,
    SecurityContext? securityContext,
    LocalApiBridgeHandler? bridgeHandler,
  }) {
    final runningServer = _server;
    if (runningServer != null) return Future<int>.value(runningServer.port);
    // Jangan bind ulang ketika listener lama masih dalam proses ditutup.
    // Ini mencegah dua lifecycle start/stop saling mendahului.
    final pendingStop = _stopFuture;
    if (pendingStop != null) {
      return pendingStop.then(
        (_) => _start(
          port: port,
          serverName: serverName,
          securityContext: securityContext,
          bridgeHandler: bridgeHandler,
        ),
      );
    }

    final pendingStart = _startFuture;
    if (pendingStart != null) return pendingStart;

    final future = _startInternal(
      port: port,
      serverName: serverName,
      securityContext: securityContext,
      bridgeHandler: bridgeHandler,
    );
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) _startFuture = null;
    });
  }

  Future<int> _startInternal({
    required int port,
    required String serverName,
    SecurityContext? securityContext,
    LocalApiBridgeHandler? bridgeHandler,
  }) async {
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Port harus 0 sampai 65535.');
    }

    final server = securityContext == null
        ? await HttpServer.bind(
            InternetAddress.anyIPv4,
            port,
            shared: true,
          )
        : await HttpServer.bindSecure(
            InternetAddress.anyIPv4,
            port,
            securityContext,
            shared: true,
          );
    _server = server;
    _isSecure = securityContext != null;
    _bridgeHandler = bridgeHandler;
    unawaited(_handleRequests(server, serverName));
    return server.port;
  }

  Future<void> _handleRequests(HttpServer server, String serverName) async {
    try {
      await for (final request in server) {
        // Kesalahan pada satu koneksi tidak boleh menghentikan listener untuk
        // semua perangkat lain yang sedang memakai Server.
        try {
          request.response.headers.contentType = ContentType.json;
          request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
          request.response.headers.set('X-Content-Type-Options', 'nosniff');
          // Tutup respons setelah satu permintaan agar klien LAN dan pengujian
          // tidak menunggu koneksi keep-alive yang tidak diperlukan.
          request.response.persistentConnection = false;

          if (request.method == 'GET' && request.uri.path == '/api/v1/health') {
            request.response.statusCode = HttpStatus.ok;
            final payload = jsonEncode({
              'app': 'bengkelku_pos',
              'status': 'ok',
              'server_name': serverName,
              'app_version': appVersion,
              'api_version': apiVersion,
              'min_client_version': minimumClientVersion,
              'max_client_version': maximumClientVersion,
            });
            request.response.contentLength = utf8.encode(payload).length;
            request.response.write(payload);
          } else if (request.method == 'GET' &&
              request.uri.path == '/api/v1/server-info') {
            final handler = _bridgeHandler;
            if (handler == null) {
              request.response.statusCode = HttpStatus.serviceUnavailable;
              request.response.write(jsonEncode({
                'app': 'bengkelku_pos',
                'status': 'bridge_unavailable',
              }));
            } else {
              try {
                // This allowlisted, read-only operation is executed by the
                // main isolate through the foreground-task message bridge.
                final bridgeRequest = LocalApiBridgeRequest(
                  requestId: 'api-' + DateTime.now().microsecondsSinceEpoch.toString() + '-' + (_nextBridgeRequestId++).toString(),
                  operation: 'server_info',
                  remoteAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
                );
                final data = await handler(bridgeRequest);
                final payload = jsonEncode({
                  'app': 'bengkelku_pos',
                  'status': 'ok',
                  'data': data,
                });
                request.response.statusCode = HttpStatus.ok;
                request.response.contentLength = utf8.encode(payload).length;
                request.response.write(payload);
              } on Object {
                request.response.statusCode = HttpStatus.serviceUnavailable;
                request.response.write(jsonEncode({
                  'app': 'bengkelku_pos',
                  'status': 'bridge_timeout_or_error',
                }));
              }
            }
          } else if (request.method == 'GET' &&
              request.uri.path == '/api/v1/device/me') {
            await _handleDeviceIdentityRequest(request);
          } else if (request.method == 'POST' &&
              request.uri.path == '/api/v1/pair') {
            await _handlePairingRequest(request);
          } else if (request.uri.path == '/api/v1/pair') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
            request.response.headers.set(HttpHeaders.allowHeader, 'POST');
            request.response.write(jsonEncode({
              'app': 'bengkelku_pos',
              'status': 'method_not_allowed',
            }));
          } else if (request.uri.path == '/api/v1/health' ||
              request.uri.path == '/api/v1/server-info') {
            request.response.statusCode = HttpStatus.methodNotAllowed;
            request.response.headers.set(HttpHeaders.allowHeader, 'GET');
            request.response.write(jsonEncode({
              'app': 'bengkelku_pos',
              'status': 'method_not_allowed',
              'message': 'Endpoint pemeriksaan hanya menerima GET.',
            }));
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(jsonEncode({
              'app': 'bengkelku_pos',
              'status': 'not_found',
              'message': 'Endpoint BengkelKu tidak ditemukan.',
            }));
          }
          await request.response.close();
        } catch (_) {
          // Klien dapat memutus koneksi kapan saja. Kegagalan satu respons
          // tidak boleh menghentikan listener untuk permintaan berikutnya.
        }
      }
    } on HttpException {
      // Server mungkin sedang dihentikan saat koneksi terputus.
    } on SocketException {
      // Abaikan koneksi yang terputus dari perangkat Client.
    }
  }


  Future<void> _handleDeviceIdentityRequest(HttpRequest request) async {
    if (!_isSecure) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      request.response.write(jsonEncode({'app': 'bengkelku_pos', 'status': 'https_required'}));
      return;
    }
    final handler = _bridgeHandler;
    if (handler == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write(jsonEncode({'app': 'bengkelku_pos', 'status': 'bridge_unavailable'}));
      return;
    }
    final authorization = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final match = RegExp(r'^Bearer ([a-fA-F0-9]{64})

  Future<void> _handlePairingRequest(HttpRequest request) async {
    // Tolak HTTP sebelum membaca body agar endpoint tidak memproses data
    // pairing atau menghabiskan resource untuk permintaan plaintext.
    if (!_isSecure) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'https_required',
      }));
      return;
    }

    final handler = _bridgeHandler;
    if (handler == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'bridge_unavailable',
      }));
      return;
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      request.response.statusCode = HttpStatus.unsupportedMediaType;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'json_required',
      }));
      return;
    }
    if (request.contentLength > _maxPairingBodyBytes) {
      request.response.statusCode = 413;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'payload_too_large',
      }));
      return;
    }

    final bytes = <int>[];
    try {
      await for (final chunk in request) {
        if (bytes.length + chunk.length > _maxPairingBodyBytes) {
          request.response.statusCode = 413;
          request.response.write(jsonEncode({
            'app': 'bengkelku_pos',
            'status': 'payload_too_large',
          }));
          return;
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference({'code', 'device_name'}).isNotEmpty ||
          decoded['code'] is! String ||
          decoded['device_name'] is! String) {
        throw const FormatException('Invalid pairing body.');
      }
      final code = (decoded['code'] as String).trim();
      final deviceName = (decoded['device_name'] as String).trim();
      if (deviceName.isEmpty || deviceName.length > 60) {
        throw const FormatException('Invalid pairing fields.');
      }

      final result = await handler(LocalApiBridgeRequest(
        requestId: 'pair-' +
            DateTime.now().microsecondsSinceEpoch.toString() +
            '-' +
            (_nextBridgeRequestId++).toString(),
        operation: 'pair_device',
        remoteAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
        payload: {'code': code, 'device_name': deviceName},
      ));
      final status = result['status'];
      if (status == 'paired') {
        final payload = jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'paired',
          'device_id': result['device_id'],
          'device_name': result['device_name'],
          'token': result['token'],
        });
        request.response.statusCode = HttpStatus.created;
        request.response.contentLength = utf8.encode(payload).length;
        request.response.write(payload);
      } else if (status == 'rate_limited') {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.write(jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'rate_limited',
        }));
      } else if (status == 'invalid_code') {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'pairing_rejected',
        }));
      } else {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'pairing_unavailable',
        }));
      }
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'invalid_request',
      }));
    } on Object {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'pairing_unavailable',
      }));
    }
  }

  Future<void> stop() {
    final pendingStop = _stopFuture;
    if (pendingStop != null) return pendingStop;

    final future = _stopInternal();
    _stopFuture = future;
    return future.whenComplete(() {
      if (identical(_stopFuture, future)) _stopFuture = null;
    });
  }

  Future<void> _stopInternal() async {
    // Bila Stop ditekan ketika bind masih berlangsung, tunggu hasilnya agar
    // server tidak tertinggal aktif tanpa kendali UI.
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        return;
      }
    }
    final server = _server;
    _server = null;
    _isSecure = false;
    _bridgeHandler = null;
    await server?.close(force: true);
  }
}
).firstMatch(authorization);
    if (match == null) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write(jsonEncode({'app': 'bengkelku_pos', 'status': 'authentication_required'}));
      return;
    }
    try {
      final result = await handler(LocalApiBridgeRequest(
        requestId: 'device-' + DateTime.now().microsecondsSinceEpoch.toString() + '-' + (_nextBridgeRequestId++).toString(),
        operation: 'authenticate_device',
        remoteAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
        payload: {'token': match.group(1)!},
      ));
      if (result['status'] != 'authenticated') {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(jsonEncode({'app': 'bengkelku_pos', 'status': 'authentication_rejected'}));
        return;
      }
      final payload = jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'authenticated',
        'device': {
          'device_id': result['device_id'],
          'device_name': result['device_name'],
          'created_at': result['created_at'],
          'last_seen_at': result['last_seen_at'],
        },
      });
      request.response.statusCode = HttpStatus.ok;
      request.response.contentLength = utf8.encode(payload).length;
      request.response.write(payload);
    } on Object {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write(jsonEncode({'app': 'bengkelku_pos', 'status': 'authentication_unavailable'}));
    }
  }

  static const int _maxPairingBodyBytes = 4096;

  Future<void> _handlePairingRequest(HttpRequest request) async {
    // Tolak HTTP sebelum membaca body agar endpoint tidak memproses data
    // pairing atau menghabiskan resource untuk permintaan plaintext.
    if (!_isSecure) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'https_required',
      }));
      return;
    }

    final handler = _bridgeHandler;
    if (handler == null) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'bridge_unavailable',
      }));
      return;
    }
    if (request.headers.contentType?.mimeType != 'application/json') {
      request.response.statusCode = HttpStatus.unsupportedMediaType;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'json_required',
      }));
      return;
    }
    if (request.contentLength > _maxPairingBodyBytes) {
      request.response.statusCode = 413;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'payload_too_large',
      }));
      return;
    }

    final bytes = <int>[];
    try {
      await for (final chunk in request) {
        if (bytes.length + chunk.length > _maxPairingBodyBytes) {
          request.response.statusCode = 413;
          request.response.write(jsonEncode({
            'app': 'bengkelku_pos',
            'status': 'payload_too_large',
          }));
          return;
        }
        bytes.addAll(chunk);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded.keys.toSet().difference({'code', 'device_name'}).isNotEmpty ||
          decoded['code'] is! String ||
          decoded['device_name'] is! String) {
        throw const FormatException('Invalid pairing body.');
      }
      final code = (decoded['code'] as String).trim();
      final deviceName = (decoded['device_name'] as String).trim();
      if (deviceName.isEmpty || deviceName.length > 60) {
        throw const FormatException('Invalid pairing fields.');
      }

      final result = await handler(LocalApiBridgeRequest(
        requestId: 'pair-' +
            DateTime.now().microsecondsSinceEpoch.toString() +
            '-' +
            (_nextBridgeRequestId++).toString(),
        operation: 'pair_device',
        remoteAddress: request.connectionInfo?.remoteAddress.address ?? 'unknown',
        payload: {'code': code, 'device_name': deviceName},
      ));
      final status = result['status'];
      if (status == 'paired') {
        final payload = jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'paired',
          'device_id': result['device_id'],
          'device_name': result['device_name'],
          'token': result['token'],
        });
        request.response.statusCode = HttpStatus.created;
        request.response.contentLength = utf8.encode(payload).length;
        request.response.write(payload);
      } else if (status == 'rate_limited') {
        request.response.statusCode = HttpStatus.tooManyRequests;
        request.response.write(jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'rate_limited',
        }));
      } else if (status == 'invalid_code') {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.write(jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'pairing_rejected',
        }));
      } else {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write(jsonEncode({
          'app': 'bengkelku_pos',
          'status': 'pairing_unavailable',
        }));
      }
    } on FormatException {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'invalid_request',
      }));
    } on Object {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'status': 'pairing_unavailable',
      }));
    }
  }

  Future<void> stop() {
    final pendingStop = _stopFuture;
    if (pendingStop != null) return pendingStop;

    final future = _stopInternal();
    _stopFuture = future;
    return future.whenComplete(() {
      if (identical(_stopFuture, future)) _stopFuture = null;
    });
  }

  Future<void> _stopInternal() async {
    // Bila Stop ditekan ketika bind masih berlangsung, tunggu hasilnya agar
    // server tidak tertinggal aktif tanpa kendali UI.
    final pendingStart = _startFuture;
    if (pendingStart != null) {
      try {
        await pendingStart;
      } catch (_) {
        return;
      }
    }
    final server = _server;
    _server = null;
    _isSecure = false;
    _bridgeHandler = null;
    await server?.close(force: true);
  }
}
