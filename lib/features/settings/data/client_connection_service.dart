import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'pinned_lan_tls_connector.dart';

class ClientConnectionResult {
  const ClientConnectionResult({
    required this.isApiReady,
    required this.message,
    this.serverName,
    this.serverAppVersion,
    this.apiVersion,
    this.versionCompatibilityKnown = false,
  });

  final bool isApiReady;
  final String message;
  final String? serverName;
  final String? serverAppVersion;
  final int? apiVersion;
  final bool versionCompatibilityKnown;
}

class ClientConnectionService {
  ClientConnectionService({
    PinnedLanTlsConnector tlsConnector = const PinnedLanTlsConnector(),
  }) : _tlsConnector = tlsConnector;

  final PinnedLanTlsConnector _tlsConnector;

  static const int supportedApiVersion = 1;
  static const String expectedApplicationId = 'bengkelku_pos';

  // Injected by the release workflow from pubspec.yaml.
  static const String clientAppVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map(int.tryParse).toList();
    final rightParts = right.split('.').map(int.tryParse).toList();
    if (leftParts.any((part) => part == null) ||
        rightParts.any((part) => part == null)) {
      throw const FormatException('Format versi aplikasi tidak valid.');
    }

    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var i = 0; i < length; i++) {
      final l = i < leftParts.length ? leftParts[i]! : 0;
      final r = i < rightParts.length ? rightParts[i]! : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }

  /// Legacy plaintext connectivity checks are deliberately disabled.
  ///
  /// Client connections must use [checkSecureServer] with the certificate
  /// identity obtained from the trusted pairing flow. This method remains
  /// temporarily to provide a clear failure to older callers; it never opens
  /// an HTTP socket and never falls back from TLS.
  @Deprecated('Use checkSecureServer with a paired TLS identity.')
  Future<ClientConnectionResult> checkServer({
    required String host,
    required int port,
  }) async {
    return const ClientConnectionResult(
      isApiReady: false,
      message:
          'Koneksi HTTP tanpa enkripsi dinonaktifkan. Pasangkan perangkat dan gunakan koneksi HTTPS terverifikasi.',
    );
  }

  /// Checks the health endpoint through certificate-pinned TLS.
  ///
  /// [host] is only the LAN routing address. TLS hostname verification uses
  /// [serverDnsName], which must come from the trusted pairing record.
  /// This method never falls back to plaintext HTTP.
  Future<ClientConnectionResult> checkSecureServer({
    required String host,
    required int port,
    required String serverDnsName,
    required String certificatePem,
  }) async {
    SecureSocket? socket;
    try {
      socket = await _tlsConnector.connect(
        address: host,
        port: port,
        serverDnsName: serverDnsName,
        certificatePem: certificatePem,
      );
      socket.write(
        'GET /api/v1/health HTTP/1.1\r\n'
        'Host: $serverDnsName\r\n'
        'Accept: application/json\r\n'
        'Connection: close\r\n\r\n',
      );
      final responseText = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 8));
      final headerEnd = responseText.indexOf('\r\n\r\n');
      if (headerEnd < 0) {
        throw const FormatException('Respons HTTPS Server tidak lengkap.');
      }

      final headerText = responseText.substring(0, headerEnd);
      final statusLine = headerText.split('\r\n').first;
      final statusMatch =
          RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(statusLine);
      if (statusMatch == null) {
        throw const FormatException('Status HTTP Server tidak valid.');
      }
      final statusCode = int.parse(statusMatch.group(1)!);
      if (statusCode != HttpStatus.ok) {
        return ClientConnectionResult(
          isApiReady: false,
          message: 'Server TLS merespons HTTP $statusCode.',
        );
      }

      final body = responseText.substring(headerEnd + 4);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return const ClientConnectionResult(
          isApiReady: false,
          message: 'Respons Server TLS tidak sesuai format JSON.',
        );
      }

      final appId = decoded['app']?.toString();
      final apiVersion = decoded['api_version'];
      final status = decoded['status']?.toString();
      final serverName = decoded['server_name']?.toString();
      final serverAppVersion = decoded['app_version']?.toString();

      if (appId != expectedApplicationId || status != 'ok') {
        return const ClientConnectionResult(
          isApiReady: false,
          message: 'Endpoint TLS bukan layanan Bike POS Server yang valid.',
        );
      }
      if (apiVersion is! num ||
          apiVersion.toInt() != supportedApiVersion) {
        return ClientConnectionResult(
          isApiReady: false,
          message:
              'Versi API Server tidak cocok. Client mendukung API versi $supportedApiVersion.',
          serverName: serverName,
          serverAppVersion: serverAppVersion,
          apiVersion: apiVersion is num ? apiVersion.toInt() : null,
        );
      }

      final minClientVersion = decoded['min_client_version']?.toString();
      final maxClientVersion = decoded['max_client_version']?.toString();
      final hasVersionPolicy =
          minClientVersion != null || maxClientVersion != null;
      if (hasVersionPolicy) {
        try {
          if (minClientVersion != null &&
              _compareVersions(clientAppVersion, minClientVersion) < 0) {
            return ClientConnectionResult(
              isApiReady: false,
              message:
                  'Client terlalu lama (v$clientAppVersion). Server mensyaratkan minimal v$minClientVersion. Perbarui APK Client.',
              serverName: serverName,
              serverAppVersion: serverAppVersion,
              apiVersion: apiVersion.toInt(),
              versionCompatibilityKnown: true,
            );
          }
          if (maxClientVersion != null &&
              _compareVersions(clientAppVersion, maxClientVersion) > 0) {
            return ClientConnectionResult(
              isApiReady: false,
              message:
                  'Versi Client v$clientAppVersion lebih baru dari batas Server (maksimal v$maxClientVersion). Perbarui APK Server.',
              serverName: serverName,
              serverAppVersion: serverAppVersion,
              apiVersion: apiVersion.toInt(),
              versionCompatibilityKnown: true,
            );
          }
        } on FormatException {
          return ClientConnectionResult(
            isApiReady: false,
            message: 'Aturan kompatibilitas versi dari Server tidak valid.',
            serverName: serverName,
            serverAppVersion: serverAppVersion,
            apiVersion: apiVersion.toInt(),
          );
        }
      }

      return ClientConnectionResult(
        isApiReady: true,
        message: hasVersionPolicy
            ? 'Koneksi TLS aman. APK Client v$clientAppVersion kompatibel dengan Server'
                '${serverAppVersion == null ? '' : ' v$serverAppVersion'}.'
            : 'Koneksi TLS aman. API siap, tetapi kebijakan kompatibilitas versi belum dilaporkan.',
        serverName: serverName,
        serverAppVersion: serverAppVersion,
        apiVersion: apiVersion.toInt(),
        versionCompatibilityKnown: hasVersionPolicy,
      );
    } on SocketException {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Tidak dapat menjangkau Server melalui jaringan lokal.',
      );
    } on HandshakeException {
      return const ClientConnectionResult(
        isApiReady: false,
        message:
            'Verifikasi TLS gagal. Sertifikat Server tidak dipercaya atau koneksi bukan HTTPS.',
      );
    } on TlsException {
      return const ClientConnectionResult(
        isApiReady: false,
        message:
            'Koneksi TLS ditolak. Periksa sertifikat dan identitas Server hasil pairing.',
      );
    } on TimeoutException {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Pemeriksaan TLS Server melewati batas waktu.',
      );
    } on FormatException {
      return const ClientConnectionResult(
        isApiReady: false,
        message: 'Server mengirim respons HTTPS yang tidak valid.',
      );
    } catch (error) {
      return ClientConnectionResult(
        isApiReady: false,
        message: 'Gagal memeriksa Server melalui TLS: $error',
      );
    } finally {
      socket?.destroy();
    }
  }

}
