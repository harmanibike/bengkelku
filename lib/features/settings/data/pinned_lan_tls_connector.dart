import 'dart:convert';
import 'dart:io';

import 'server_certificate_pin.dart';

/// Opens a LAN TCP connection and upgrades it using the stable DNS identity
/// and certificate obtained during an authenticated pairing ceremony.
///
/// The LAN address is only a routing address. TLS hostname verification uses
/// [serverDnsName], so a changing DHCP address does not change server identity.
class PinnedLanTlsConnector {
  const PinnedLanTlsConnector();

  Future<SecureSocket> connect({
    required String address,
    required int port,
    required String serverDnsName,
    required String certificatePem,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final normalizedAddress = address.trim();
    if (normalizedAddress.isEmpty || port < 1 || port > 65535) {
      throw ArgumentError('Alamat atau port Server tidak valid.');
    }
    final validDnsName =
        RegExp(r'^bikepos-[a-f0-9]{32}\.invalid$').hasMatch(serverDnsName);
    if (!validDnsName) {
      throw ArgumentError('Identitas DNS Server tidak valid.');
    }

    // Trust is limited to the certificate obtained during pairing.
    ServerCertificatePin.fingerprintOfPem(certificatePem);
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(certificatePem));

    final socket = await Socket.connect(
      normalizedAddress,
      port,
      timeout: timeout,
    );
    try {
      return await SecureSocket.secure(
        socket,
        host: serverDnsName,
        context: context,
      ).timeout(timeout);
    } catch (_) {
      socket.destroy();
      rethrow;
    }
  }
}
