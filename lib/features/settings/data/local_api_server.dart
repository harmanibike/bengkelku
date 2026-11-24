import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// API jaringan lokal tahap awal. Endpoint ini hanya untuk health-check;
/// belum menyediakan akses transaksi atau database untuk perangkat Client.
class LocalApiServer {
  static const int apiVersion = 1;
  static const String appVersion = '1.0.0';
  static const String minimumClientVersion = '1.0.0';
  static const String maximumClientVersion = '1.0.99';
  static const int defaultPort = 8765;

  /// Instance condivisa a livello applicazione: non appartiene alla pagina UI.
  static final LocalApiServer instance = LocalApiServer();

  HttpServer? _server;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  Future<int> start({
    int port = defaultPort,
    String serverName = 'BengkelKu Server',
  }) async {
    if (_server != null) return _server!.port;
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Port harus 0 sampai 65535.');
    }

    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server = server;
    unawaited(_handleRequests(server, serverName));
    return server.port;
  }

  Future<void> _handleRequests(HttpServer server, String serverName) async {
    try {
      await for (final request in server) {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');

        if (request.method == 'GET' && request.uri.path == '/api/v1/health') {
          request.response.statusCode = HttpStatus.ok;
          request.response.write(jsonEncode({
            'app': 'bengkelku_pos',
            'status': 'ok',
            'server_name': serverName,
            'app_version': appVersion,
            'api_version': apiVersion,
            'min_client_version': minimumClientVersion,
            'max_client_version': maximumClientVersion,
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
      }
    } on HttpException {
      // Server mungkin sedang dihentikan saat koneksi terputus.
    } on SocketException {
      // Abaikan koneksi yang terputus dari perangkat Client.
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }
}
