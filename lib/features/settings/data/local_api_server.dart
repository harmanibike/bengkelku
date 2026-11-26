import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// API jaringan lokal tahap awal. Hanya health-check dan metadata Server;
/// belum menyediakan akses transaksi atau database untuk perangkat Client.
typedef LocalApiBridgeHandler = Future<Map<String, dynamic>> Function(
  String operation,
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

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Start idempotent: chiamate simultanee condividono lo stesso bind.
  Future<int> start({
    int port = defaultPort,
    String serverName = 'BengkelKu Server',
  }) => _start(
        port: port,
        serverName: serverName,
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
                final data = await handler('server_info');
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
    _bridgeHandler = null;
    await server?.close(force: true);
  }
}
