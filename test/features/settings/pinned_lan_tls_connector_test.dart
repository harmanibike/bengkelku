import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/features/settings/data/pinned_lan_tls_connector.dart';

void main() {
  const connector = PinnedLanTlsConnector();

  group('Pinned LAN TLS connector input validation', () {
    test('rejects invalid LAN address and port before connecting', () async {
      await expectLater(
        connector.connect(
          address: '',
          port: 8080,
          serverDnsName: 'bikepos-0123456789abcdef0123456789abcdef.invalid',
          certificatePem: 'not a certificate',
        ),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        connector.connect(
          address: '192.168.1.10',
          port: 70000,
          serverDnsName: 'bikepos-0123456789abcdef0123456789abcdef.invalid',
          certificatePem: 'not a certificate',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects a DNS identity outside the paired Bike POS namespace',
        () async {
      await expectLater(
        connector.connect(
          address: '192.168.1.10',
          port: 8080,
          serverDnsName: 'attacker.example',
          certificatePem: 'not a certificate',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects malformed certificate before opening a network socket',
        () async {
      await expectLater(
        connector.connect(
          address: '192.168.1.10',
          port: 8080,
          serverDnsName: 'bikepos-0123456789abcdef0123456789abcdef.invalid',
          certificatePem: 'not a certificate',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
