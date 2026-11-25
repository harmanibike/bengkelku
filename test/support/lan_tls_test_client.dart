import 'dart:convert';
import 'dart:io';

/// Opens TCP to the paired LAN address, then explicitly upgrades that socket
/// to TLS using the stable paired DNS identity for SNI and certificate checks.
///
/// This deliberately avoids HttpClient.connectionFactory: a custom factory
/// returns a plain Socket and HttpClient does not automatically wrap that
/// socket in TLS for HTTPS requests.
///
/// Keep this helper under test/support; tests in nested test/features folders
/// should import it with a relative path back to the test root.
Future<SecureSocket> connectLanTlsTestSocket({
  required String urlHost,
  required String expectedDnsName,
  required InternetAddress routeAddress,
  required int routePort,
  required String trustedCertificatePem,
}) async {
  if (urlHost.toLowerCase() != expectedDnsName.toLowerCase()) {
    throw StateError('Identitas host URL tidak cocok dengan pairing.');
  }

  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(utf8.encode(trustedCertificatePem));

  final socket = await Socket.connect(routeAddress, routePort);
  try {
    return await SecureSocket.secure(
      socket,
      host: expectedDnsName,
      context: context,
    );
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}
