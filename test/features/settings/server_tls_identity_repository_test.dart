import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/features/settings/data/server_tls_identity_repository.dart';

import '../../support/lan_tls_test_client.dart';

class _MemorySecureValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _FailingGenerator implements ServerTlsIdentityMaterialGenerator {
  @override
  Future<ServerTlsIdentityMaterial> generate({required String dnsName}) {
    throw StateError('Generator must not run for an existing identity.');
  }
}

void main() {
  group('Server TLS identity lifecycle', () {
    test('creates identity once and restores the same identity from storage',
        () async {
      final store = _MemorySecureValueStore();
      final firstRepository = ServerTlsIdentityRepository(
        store: store,
        random: Random(7),
      );

      final first = await firstRepository.loadOrCreate();
      final restored = await ServerTlsIdentityRepository(
        store: store,
        generator: _FailingGenerator(),
      ).loadOrCreate();

      expect(first.serverId, matches(RegExp(r'^[a-f0-9]{32}$')));
      expect(first.dnsName, 'bikepos-' + first.serverId + '.invalid');
      expect(first.fingerprint, hasLength(64));
      expect(restored.serverId, first.serverId);
      expect(restored.dnsName, first.dnsName);
      expect(restored.fingerprint, first.fingerprint);
      expect(restored.certificatePem, first.certificatePem);
      expect(restored.privateKeyPem, first.privateKeyPem);
    });

    test('fails closed when stored identity is incomplete', () async {
      final store = _MemorySecureValueStore()
        ..values['bikepos.server_tls.v1.server_id'] =
            '0123456789abcdef0123456789abcdef';

      await expectLater(
        ServerTlsIdentityRepository(store: store).loadOrCreate(),
        throwsA(isA<StateError>()),
      );
    });

    test('fails closed when the stored certificate fingerprint is changed',
        () async {
      final store = _MemorySecureValueStore();
      final identity = await ServerTlsIdentityRepository(
        store: store,
        random: Random(9),
      ).loadOrCreate();
      store.values['bikepos.server_tls.v1.fingerprint'] =
          List.filled(64, '0').join();

      await expectLater(
        ServerTlsIdentityRepository(
          store: store,
          generator: _FailingGenerator(),
        ).loadOrCreate(),
        throwsA(isA<StateError>()),
      );
      expect(identity.privateKeyPem, isNotEmpty);
    });

    test('generated leaf certificate can be trusted for its paired DNS name',
        () async {
      final identity = await ServerTlsIdentityRepository(
        store: _MemorySecureValueStore(),
        random: Random(11),
      ).loadOrCreate();
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
        ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );

      server.listen((request) async {
        request.response.statusCode = HttpStatus.ok;
        request.response.write('identity-ok');
        await request.response.close();
      });

      try {
        final socket = await connectLanTlsTestSocket(
          urlHost: identity.dnsName,
          expectedDnsName: identity.dnsName,
          routeAddress: InternetAddress.loopbackIPv4,
          routePort: server.port,
          trustedCertificatePem: identity.certificatePem,
        );
        try {
          socket.write(
            'GET /health HTTP/1.1\r\n'
            'Host: ' + identity.dnsName + '\r\n' +
            'Connection: close\r\n\r\n',
          );
          final response = await utf8.decoder
              .bind(socket)
              .join()
              .timeout(const Duration(seconds: 5));
          expect(response, contains('200 OK'));
          expect(response, contains('identity-ok'));
        } finally {
          await socket.close();
        }
      } finally {
        await server.close(force: true);
      }
    });
  });
}
