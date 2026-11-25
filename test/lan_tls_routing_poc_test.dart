import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/lan_tls_test_client.dart';
import 'support/test_certificate.dart';

const _expectedHost = 'bikepos-poc.invalid';
const _wrongHost = 'wrong-bikepos-poc.invalid';

Future<HttpServer> _startSecureServer(TestCertificate certificate) async {
  final context = SecurityContext()
    ..useCertificateChainBytes(await certificate.certificate.readAsBytes())
    ..usePrivateKeyBytes(await certificate.privateKey.readAsBytes());

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

Future<int> _request({
  required String urlHost,
  required String expectedDnsName,
  required int port,
  required String trustedCertificatePem,
}) async {
  final socket = await connectLanTlsTestSocket(
    urlHost: urlHost,
    expectedDnsName: expectedDnsName,
    routeAddress: InternetAddress.loopbackIPv4,
    routePort: port,
    trustedCertificatePem: trustedCertificatePem,
  );
  try {
    socket.write(
      'GET /health HTTP/1.1\\r\\n'
      'Host: $urlHost\\r\\n'
      'Connection: close\\r\\n\\r\\n',
    );
    final response = await utf8.decoder.bind(socket).join();
    final statusLine = response.split('\\r\\n').first;
    return int.parse(statusLine.split(' ')[1]);
  } finally {
    await socket.close();
  }
}

void main() {
  group('LAN TLS stable DNS routing PoC', () {
    test('routes TCP to LAN IP while TLS verifies stable DNS identity', () async {
      final certificate = await createTestCertificate(_expectedHost);
      final server = await _startSecureServer(certificate);

      try {
        expect(
          await _request(
            urlHost: _expectedHost,
            expectedDnsName: _expectedHost,
            port: server.port,
            trustedCertificatePem:
                await certificate.certificate.readAsString(),
          ),
          HttpStatus.ok,
        );
      } finally {
        await server.close(force: true);
        await certificate.dispose();
      }
    });

    test('rejects a trusted certificate with the wrong DNS identity', () async {
      final certificate = await createTestCertificate(_wrongHost);
      final server = await _startSecureServer(certificate);

      try {
        await expectLater(
          _request(
            urlHost: _expectedHost,
            expectedDnsName: _expectedHost,
            port: server.port,
            trustedCertificatePem:
                await certificate.certificate.readAsString(),
          ),
          throwsA(isA<HandshakeException>()),
        );
      } finally {
        await server.close(force: true);
        await certificate.dispose();
      }
    });

    test('rejects a server certificate that differs from the pinned cert',
        () async {
      final serverCertificate = await createTestCertificate(_expectedHost);
      final differentTrustedCertificate =
          await createTestCertificate(_expectedHost);
      final server = await _startSecureServer(serverCertificate);

      try {
        await expectLater(
          _request(
            urlHost: _expectedHost,
            expectedDnsName: _expectedHost,
            port: server.port,
            trustedCertificatePem:
                await differentTrustedCertificate.certificate.readAsString(),
          ),
          throwsA(isA<HandshakeException>()),
        );
      } finally {
        await server.close(force: true);
        await serverCertificate.dispose();
        await differentTrustedCertificate.dispose();
      }
    });

    test('rejects plaintext HTTP on the HTTPS route', () async {
      final certificate = await createTestCertificate(_expectedHost);
      final server = await _startPlainServer();

      try {
        await expectLater(
          _request(
            urlHost: _expectedHost,
            expectedDnsName: _expectedHost,
            port: server.port,
            trustedCertificatePem:
                await certificate.certificate.readAsString(),
          ),
          throwsA(anything),
        );
      } finally {
        await server.close(force: true);
        await certificate.dispose();
      }
    });

    test('refuses a URL host that differs from the paired identity', () async {
      final certificate = await createTestCertificate(_expectedHost);

      try {
        await expectLater(
          _request(
            urlHost: _wrongHost,
            expectedDnsName: _expectedHost,
            port: 443,
            trustedCertificatePem:
                await certificate.certificate.readAsString(),
          ),
          throwsA(isA<StateError>()),
        );
      } finally {
        await certificate.dispose();
      }
    });
  });
}
