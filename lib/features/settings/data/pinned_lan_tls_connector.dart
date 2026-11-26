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

    // Trust is limited to the certificate obtained during pairing. Also
    // compare the certificate actually presented by the peer with that exact
    // leaf fingerprint; trusting a certificate as an anchor alone is not the
    // explicit pin check required by the pairing record.
    final expectedFingerprint =
        ServerCertificatePin.fingerprintOfPem(certificatePem);
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(utf8.encode(certificatePem));

    final socket = await Socket.connect(
      normalizedAddress,
      port,
      timeout: timeout,
    );
    SecureSocket? secureSocket;
    try {
      secureSocket = await SecureSocket.secure(
        socket,
        host: serverDnsName,
        context: context,
      ).timeout(timeout);
      final peerCertificate = secureSocket.peerCertificate;
      if (peerCertificate == null ||
          !ServerCertificatePin.matchesDer(
            certificateDer: peerCertificate.der,
            expectedFingerprint: expectedFingerprint,
          )) {
        secureSocket.destroy();
        throw HandshakeException(
          'Fingerprint sertifikat Server tidak cocok dengan hasil pairing.',
        );
      }
      return secureSocket;
    } catch (_) {
      secureSocket?.destroy();
      socket.destroy();
      rethrow;
    }
  }
}
