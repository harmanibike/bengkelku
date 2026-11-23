import 'dart:convert';
import 'dart:io';

class ClientConnectionResult {
  const ClientConnectionResult({
    required this.isApiReady,
    required this.message,
    this.serverName,
    this.apiVersion,
  });

  final bool isApiReady;
  final String message;
  final String? serverName;
  final int? apiVersion;
}

class ClientConnectionService {
  static const int supportedApiVersion = 1;
  static const String expectedApplicationId = 'bengkelku_pos';

  Future<ClientConnectionResult> checkServer({
    required String host,
    required int port,
  }) async {
    final normalizedHost = host.trim();
    if (normalizedHost.isEmpty) {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Alamat Server belum diisi.',
      );
    }
    if (port < 1 || port > 65535) {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Port Server tidak valid.',
      );
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..idleTimeout = const Duration(seconds: 4);

    try {
      final uri = Uri(
        scheme: 'http',
        host: normalizedHost,
        port: port,
        path: '/api/v1/health',
      );
      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 5),
          );
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
            const Duration(seconds: 5),
          );

      final body = await utf8.decoder.bind(response).join().timeout(
            const Duration(seconds: 3),
          );

      if (response.statusCode == HttpStatus.notFound) {
        return const ClientConnectionResult(
          isApiReady: false,
          message:
              'HP dapat dijangkau, tetapi API BengkelKu Server belum tersedia pada alamat tersebut.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        return ClientConnectionResult(
          isApiReady: false,
          message:
              'Server merespons, tetapi mengembalikan HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const ClientConnectionResult(
          isApiReady: false,
          message: 'Respons Server tidak sesuai format BengkelKu.',
        );
      }

      final appId = decoded['app']?.toString();
      final apiVersion = decoded['api_version'];
      final status = decoded['status']?.toString();
      final serverName = decoded['server_name']?.toString();

      if (appId != expectedApplicationId || status != 'ok') {
        return const ClientConnectionResult(
          isApiReady: false,
          message:
              'Alamat merespons, tetapi bukan layanan BengkelKu Server yang valid.',
        );
      }
      if (apiVersion is! num ||
          apiVersion.toInt() != supportedApiVersion) {
        return ClientConnectionResult(
          isApiReady: false,
          message:
              'Versi API Server tidak cocok. Client mendukung API versi $supportedApiVersion.',
          serverName: serverName,
          apiVersion: apiVersion is num ? apiVersion.toInt() : null,
        );
      }

      return ClientConnectionResult(
        isApiReady: true,
        message: 'API BengkelKu Server siap dihubungi.',
        serverName: serverName,
        apiVersion: apiVersion.toInt(),
      );
    } on SocketException {
      return const ClientConnectionResult(
        isApiReady: false,
        message:
            'Tidak dapat menjangkau Server. Periksa Wi-Fi, alamat IP, port, dan pastikan layanan Server aktif.',
      );
    } on HttpException {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Respons jaringan Server tidak dapat dibaca.',
      );
    } on FormatException {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Server mengirim data yang bukan JSON valid.',
      );
    } on HandshakeException {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Koneksi ke Server gagal saat negosiasi jaringan.',
      );
    } catch (error) {
      return ClientConnectionResult(
        isApiReady: false,
        message: 'Gagal memeriksa Server: $error',
      );
    } finally {
      client.close(force: true);
    }
  }
}
