import 'dart:convert';
import 'dart:io';

/// Test-only route for the LAN TLS proof of concept.
///
/// The URL keeps a stable logical DNS identity for TLS hostname validation,
/// while the TCP socket is routed to the current LAN IP learned at pairing.
HttpClient createLanTlsTestClient({
  required String expectedDnsName,
  required InternetAddress routeAddress,
  required int routePort,
  required String trustedCertificatePem,
}) {
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(trustedCertificatePem));

  return HttpClient(context: context)
    ..findProxy = (_) => 'DIRECT'
    ..connectionFactory = (uri, proxyHost, proxyPort) {
      if (proxyHost != null || proxyPort != null) {
        throw StateError('Proxy tidak diizinkan untuk rute LAN PoC.');
      }
      if (uri.scheme != 'https' ||
          uri.host.toLowerCase() != expectedDnsName.toLowerCase() ||
          uri.port != routePort) {
        throw StateError('Identitas host/port URL tidak cocok dengan pairing.');
      }
      return Socket.startConnect(routeAddress, routePort);
    };
}
