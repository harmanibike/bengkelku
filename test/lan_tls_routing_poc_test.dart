import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/lan_tls_test_client.dart';

const _expectedHost = 'bikepos-poc.invalid';
const _wrongHost = 'wrong-bikepos-poc.invalid';

Future<HttpServer> _startSecureServer({
  required String certificatePath,
  required String privateKeyPath,
}) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(await File(certificatePath).readAsBytes())
    ..usePrivateKeyBytes(await File(privateKeyPath).readAsBytes());

  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  server.listen((request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.write('tls-poc-ok');
    await request.response.close();
  });
  return server;
}

Future<HttpServer> _startPlainServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.write('plain-poc');
    await request.response.close();
  });
  return server;
}

Future<int> _request(HttpClient client, String host, int port) async {
  final uri = Uri(
    scheme: 'https',
    host: host,
    port: port,
    path: '/health',
  );
  final request = await client.getUrl(uri);
  final response = await request.close();
  await response.drain<void>();
  return response.statusCode;
}

void main() {
  group('LAN TLS stable DNS routing PoC', () {
    test('routes TCP to LAN IP while TLS verifies stable DNS identity', () async {
      final server = await _startSecureServer(
        certificatePath: 'test/fixtures/server-cert.pem',
        privateKeyPath: 'test/fixtures/server-key.pem',
      );
      final client = createLanTlsTestClient(
        expectedDnsName: _expectedHost,
        routeAddress: InternetAddress.loopbackIPv4,
        routePort: server.port,
        trustedCertificatePem:
            await File('test/fixtures/server-cert.pem').readAsString(),
      );

      try {
        expect(await _request(client, _expectedHost, server.port), HttpStatus.ok);
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('rejects a trusted certificate with the wrong DNS identity', () async {
      final server = await _startSecureServer(
        certificatePath: 'test/fixtures/wrong-cert.pem',
        privateKeyPath: 'test/fixtures/wrong-key.pem',
      );
      final client = createLanTlsTestClient(
        expectedDnsName: _expectedHost,
        routeAddress: InternetAddress.loopbackIPv4,
        routePort: server.port,
        // Trust the presented certificate so this test isolates hostname
        // verification rather than merely testing an unknown trust anchor.
        trustedCertificatePem:
            await File('test/fixtures/wrong-cert.pem').readAsString(),
      );

      try {
        await expectLater(
          _request(client, _expectedHost, server.port),
          throwsA(isA<HandshakeException>()),
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('rejects a server certificate that differs from the pinned cert', () async {
      final server = await _startSecureServer(
        certificatePath: 'test/fixtures/server-cert.pem',
        privateKeyPath: 'test/fixtures/server-key.pem',
      );
      final client = createLanTlsTestClient(
        expectedDnsName: _expectedHost,
        routeAddress: InternetAddress.loopbackIPv4,
        routePort: server.port,
        trustedCertificatePem:
            await File('test/fixtures/wrong-cert.pem').readAsString(),
      );

      try {
        await expectLater(
          _request(client, _expectedHost, server.port),
          throwsA(isA<HandshakeException>()),
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('rejects plaintext HTTP on the HTTPS route', () async {
      final server = await _startPlainServer();
      final client = createLanTlsTestClient(
        expectedDnsName: _expectedHost,
        routeAddress: InternetAddress.loopbackIPv4,
        routePort: server.port,
        trustedCertificatePem:
            await File('test/fixtures/server-cert.pem').readAsString(),
      );

      try {
        await expectLater(
          _request(client, _expectedHost, server.port),
          throwsA(anything),
        );
      } finally {
        client.close(force: true);
        await server.close(force: true);
      }
    });

    test('refuses a URL host that differs from the paired identity', () async {
      final client = createLanTlsTestClient(
        expectedDnsName: _expectedHost,
        routeAddress: InternetAddress.loopbackIPv4,
        routePort: 443,
        trustedCertificatePem:
            await File('test/fixtures/server-cert.pem').readAsString(),
      );

      try {
        await expectLater(
          _request(client, _wrongHost, 443),
          throwsA(isA<StateError>()),
        );
      } finally {
        client.close(force: true);
      }
    });
  });
}
