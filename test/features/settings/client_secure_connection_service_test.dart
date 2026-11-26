import 'dart:convert';
import 'dart:io';

import 'package:bengkelku_pos/features/settings/data/client_connection_service.dart';
import 'package:bengkelku_pos/features/settings/data/local_api_server.dart';
import 'package:bengkelku_pos/features/settings/data/server_tls_identity_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTlsStore implements SecureValueStore {
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

void main() {
  late LocalApiServer server;
  late ClientConnectionService service;

  setUp(() {
    server = LocalApiServer();
    service = ClientConnectionService();
  });

  tearDown(() async {
    await server.stop();
  });

  Future<ServerTlsIdentity> createIdentity() {
    return ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
  }

  Future<int> startSecureServer(ServerTlsIdentity identity) {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    return server.startSecure(
      securityContext: context,
      port: 0,
      serverName: 'Bike POS Server TLS',
    );
  }

  test('accepts the paired certificate and verifies the health API over TLS',
      () async {
    final identity = await createIdentity();
    final port = await startSecureServer(identity);

    final result = await service.checkSecureServer(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );

    expect(result.isApiReady, isTrue);
    expect(result.serverName, 'Bike POS Server TLS');
    expect(result.versionCompatibilityKnown, isTrue);
    expect(result.message, contains('Koneksi TLS aman'));
  });

  test('rejects a server certificate that differs from the paired identity',
      () async {
    final serverIdentity = await createIdentity();
    final untrustedIdentity = await createIdentity();
    final port = await startSecureServer(serverIdentity);

    final result = await service.checkSecureServer(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: serverIdentity.dnsName,
      certificatePem: untrustedIdentity.certificatePem,
    );

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('TLS'));
  });

  test('rejects a paired certificate when the trusted DNS identity differs,
      () async {
    final serverIdentity = await createIdentity();
    final otherIdentity = await createIdentity();
    final port = await startSecureServer(serverIdentity);

    final result = await service.checkSecureServer(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: otherIdentity.dnsName,
      certificatePem: serverIdentity.certificatePem,
    );

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('TLS'));
  });

  test('does not fall back to plaintext HTTP when TLS is requested', () async {
    final identity = await createIdentity();
    final port = await server.start(port: 0);

    final result = await service.checkSecureServer(
      host: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('TLS'));
  });
}
