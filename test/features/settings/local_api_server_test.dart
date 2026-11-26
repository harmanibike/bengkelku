import 'dart:convert';
import 'dart:io';

import 'package:bengkelku_pos/features/settings/data/local_api_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/features/settings/data/server_tls_identity_repository.dart';
import 'package:bengkelku_pos/features/settings/data/pinned_lan_tls_connector.dart';

class _MemoryTlsStore implements SecureValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async { values[key] = value; }
  @override
  Future<void> delete(String key) async { values.remove(key); }
}

void main() {
  late LocalApiServer server;

  setUp(() {
    server = LocalApiServer();
  });

  tearDown(() async {
    await server.stop();
  });


  test('serves health API over TLS with the paired certificate identity', () async {
    final identity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final port = await server.startSecure(
      securityContext: context,
      port: 0,
      serverName: 'HP Server TLS',
    );

    final socket = await const PinnedLanTlsConnector().connect(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );
    try {
      socket.write(
        'GET /api/v1/health HTTP/1.1\r\n'
        'Host: ${identity.dnsName}\r\n'
        'Connection: close\r\n\r\n',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
      expect(response, contains('200 OK'));
      expect(response, contains('HP Server TLS'));
      expect(response, contains('"status":"ok"'));
    } finally {
      await socket.close();
    }
  });

  test('rejects a Server presenting a different paired certificate', () async {
    final pairedIdentity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final impostorIdentity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final impostorContext = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(impostorIdentity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(impostorIdentity.privateKeyPem));
    final port = await server.startSecure(
      securityContext: impostorContext,
      port: 0,
      serverName: 'Server dengan sertifikat berbeda',
    );

    await expectLater(
      const PinnedLanTlsConnector().connect(
        address: InternetAddress.loopbackIPv4.address,
        port: port,
        serverDnsName: pairedIdentity.dnsName,
        certificatePem: pairedIdentity.certificatePem,
      ),
      throwsA(anyOf(isA<HandshakeException>(), isA<TlsException>())),
    );
  });

  test('server-info endpoint delegates only read-only metadata to bridge handler', () async {
    final identity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    LocalApiBridgeRequest? receivedBridgeRequest;
    final port = await server.startSecure(
      securityContext: context,
      port: 0,
      bridgeHandler: (request) async {
        receivedBridgeRequest = request;
        return {
          'server_name': 'Bike POS Server',
          'read_only': true,
        };
      },
    );
    final socket = await const PinnedLanTlsConnector().connect(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );
    try {
      socket.write(
        'GET /api/v1/server-info HTTP/1.1\r\n'
        'Host: ${identity.dnsName}\r\n'
        'Connection: close\r\n\r\n',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
      expect(receivedBridgeRequest?.operation, 'server_info');
      expect(receivedBridgeRequest?.requestId, isNotEmpty);
      expect(receivedBridgeRequest?.remoteAddress, InternetAddress.loopbackIPv4.address);
      expect(receivedBridgeRequest?.payload, isEmpty);
      expect(response, contains('200 OK'));
      expect(response, contains('"read_only":true'));
      expect(response, contains('Bike POS Server'));
    } finally {
      await socket.close();
    }
  });

  test('server-info endpoint fails closed when no main-isolate bridge exists', () async {
    final identity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final port = await server.startSecure(
      securityContext: context,
      port: 0,
    );
    final socket = await const PinnedLanTlsConnector().connect(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );
    try {
      socket.write(
        'GET /api/v1/server-info HTTP/1.1\r\n'
        'Host: ${identity.dnsName}\r\n'
        'Connection: close\r\n\r\n',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
      expect(response, contains('503 Service Unavailable'));
      expect(response, contains('bridge_unavailable'));
    } finally {
      await socket.close();
    }
  });


  test('server-info endpoint fails closed when the main-isolate bridge errors', () async {
    final identity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final port = await server.startSecure(
      securityContext: context,
      port: 0,
      bridgeHandler: (_) async => throw StateError('bridge failure'),
    );
    final socket = await const PinnedLanTlsConnector().connect(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );
    try {
      socket.write(
        'GET /api/v1/server-info HTTP/1.1\r\n'
        'Host: ${identity.dnsName}\r\n'
        'Connection: close\r\n\r\n',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
      expect(response, contains('503 Service Unavailable'));
      expect(response, contains('bridge_timeout_or_error'));
      expect(response, isNot(contains('bridge failure')));
    } finally {
      await socket.close();
    }
  });

  test('server-info endpoint rejects non-GET methods', () async {
    final identity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    final port = await server.startSecure(
      securityContext: context,
      port: 0,
      bridgeHandler: (_) async => {'read_only': true},
    );
    final socket = await const PinnedLanTlsConnector().connect(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );
    try {
      socket.write(
        'POST /api/v1/server-info HTTP/1.1\r\n'
        'Host: ${identity.dnsName}\r\n'
        'Content-Length: 0\r\n'
        'Connection: close\r\n\r\n',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
      expect(response, contains('405 Method Not Allowed'));
      expect(response.toLowerCase(), contains('allow: get'));
      expect(response, contains('method_not_allowed'));
    } finally {
      await socket.close();
    }
  });

  test('starts health endpoint and reports server/client compatibility', () async {
    final port = await server.start(port: 0, serverName: 'HP Server Bengkel');
    expect(server.isRunning, isTrue);

    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, '/api/v1/health');
      final response = await request.close();
      final body = jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.ok);
      expect(body['app'], 'bengkelku_pos');
      expect(body['status'], 'ok');
      expect(body['server_name'], 'HP Server Bengkel');
      expect(body['api_version'], LocalApiServer.apiVersion);
      expect(body['app_version'], LocalApiServer.appVersion);
      expect(body['min_client_version'], LocalApiServer.minimumClientVersion);
      expect(body['max_client_version'], LocalApiServer.maximumClientVersion);
    } finally {
      client.close(force: true);
    }
  });


  test('concurrent start calls share one listening server', () async {
    final ports = await Future.wait([
      server.start(port: 0),
      server.start(port: 0),
      server.start(port: 0),
    ]);

    expect(ports.toSet(), hasLength(1));
    expect(server.isRunning, isTrue);
    expect(server.port, ports.first);
  });

  test('health endpoint rejects methods other than GET', () async {
    final port = await server.start(port: 0);
    final client = HttpClient();
    try {
      final request = await client.post(
        InternetAddress.loopbackIPv4.address,
        port,
        '/api/v1/health',
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.methodNotAllowed);
      expect(response.headers.value(HttpHeaders.allowHeader), 'GET');
      expect(
        response.headers.value('X-Content-Type-Options'),
        'nosniff',
      );

      // Request berikutnya tetap harus dilayani setelah method yang ditolak.
      final healthRequest = await client.get(
        InternetAddress.loopbackIPv4.address,
        port,
        '/api/v1/health',
      );
      final healthResponse = await healthRequest.close();
      expect(healthResponse.statusCode, HttpStatus.ok);
      await healthResponse.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

  test('returns not found for unsupported endpoints', () async {
    final port = await server.start(port: 0);
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', port, '/api/v1/products');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.notFound);
    } finally {
      client.close(force: true);
    }
  });

  test('stops and releases the local API server', () async {
    await server.start(port: 0);
    expect(server.isRunning, isTrue);
    await server.stop();
    expect(server.isRunning, isFalse);
  });

  test('stop during start and a new start are serialized safely', () async {
    final firstStart = server.start(port: 0);
    final stopping = server.stop();
    final secondStart = server.start(port: 0);

    final firstPort = await firstStart;
    await stopping;
    final secondPort = await secondStart;

    expect(firstPort, greaterThan(0));
    expect(secondPort, greaterThan(0));
    expect(server.isRunning, isTrue);
    expect(server.port, secondPort);

    final client = HttpClient();
    try {
      final request = await client.get(
        InternetAddress.loopbackIPv4.address,
        secondPort,
        '/api/v1/health',
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

  test('can start again after the previous listener has stopped', () async {
    await server.start(port: 0);
    await server.stop();
    expect(server.isRunning, isFalse);

    final secondPort = await server.start(port: 0);
    expect(server.isRunning, isTrue);
    expect(secondPort, greaterThan(0));

    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', secondPort, '/api/v1/health');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

  test('pair endpoint refuses to expose a token over plaintext HTTP', () async {
    var invoked = false;
    final port = await server.start(
      port: 0,
      bridgeHandler: (_) async {
        invoked = true;
        return {
          'status': 'paired',
          'device_id': 7,
          'device_name': 'HP Client',
          'token': 'a' * 64,
        };
      },
    );
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/api/v1/pair'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'code': '1234567890',
        'device_name': 'HP Client',
      }));
      final response = await request.close();
      final body = jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;

      expect(response.statusCode, HttpStatus.upgradeRequired);
      expect(body['status'], 'https_required');
      expect(body.containsKey('token'), isFalse);
      expect(invoked, isFalse);
    } finally {
      client.close(force: true);
    }
  });

  test('pair endpoint sends bounded request metadata over pinned HTTPS', () async {
    final identity = await ServerTlsIdentityRepository(
      store: _MemoryTlsStore(),
    ).loadOrCreate();
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    LocalApiBridgeRequest? received;
    final port = await server.startSecure(
      securityContext: context,
      port: 0,
      bridgeHandler: (request) async {
        received = request;
        return {
          'status': 'paired',
          'device_id': 7,
          'device_name': 'HP Client',
          'token': 'a' * 64,
        };
      },
    );
    final socket = await const PinnedLanTlsConnector().connect(
      address: InternetAddress.loopbackIPv4.address,
      port: port,
      serverDnsName: identity.dnsName,
      certificatePem: identity.certificatePem,
    );
    try {
      socket.write(
        'POST /api/v1/pair HTTP/1.1\\r\\n'
        'Host: ${identity.dnsName}\\r\\n'
        'Content-Type: application/json\\r\\n'
        'Content-Length: ${utf8.encode(jsonEncode({'code': '1234567890', 'device_name': 'HP Client'})).length}\\r\\n'
        'Connection: close\\r\\n\\r\\n'
        '${jsonEncode({'code': '1234567890', 'device_name': 'HP Client'})}',
      );
      final response = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 5));
      expect(response, contains('201 Created'));
      expect(response, contains('"status":"paired"'));
      expect(response, contains('"token":"${'a' * 64}"'));
      expect(received?.operation, 'pair_device');
      expect(received?.remoteAddress, InternetAddress.loopbackIPv4.address);
      expect(received?.payload['code'], '1234567890');
      expect(received?.payload['device_name'], 'HP Client');
    } finally {
      await socket.close();
    }
  });

  test('pair endpoint rejects non-JSON content without invoking the bridge', () async {
    var invoked = false;
    final port = await server.start(
      port: 0,
      bridgeHandler: (_) async {
        invoked = true;
        return {'status': 'paired'};
      },
    );
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/api/v1/pair'),
      );
      request.headers.contentType = ContentType.text;
      request.write('code=1234567890');
      final response = await request.close();
      expect(response.statusCode, HttpStatus.unsupportedMediaType);
      expect(invoked, isFalse);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

  test('pair endpoint rejects oversized bodies before invoking the bridge', () async {
    var invoked = false;
    final port = await server.start(
      port: 0,
      bridgeHandler: (_) async {
        invoked = true;
        return {'status': 'paired'};
      },
    );
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/api/v1/pair'),
      );
      request.headers.contentType = ContentType.json;
      request.write('x' * 4097);
      final response = await request.close();
      expect(response.statusCode, 413);
      expect(invoked, isFalse);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

}
