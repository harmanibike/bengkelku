import 'dart:convert';
import 'dart:io';

import 'package:bengkelku_pos/features/settings/data/client_connection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late ClientConnectionService service;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    service = ClientConnectionService();
  });

  tearDown(() async {
    await server.close(force: true);
  });

  Future<ClientConnectionResult> respond(Map<String, Object?> payload) async {
    server.listen((request) async {
      expect(request.uri.path, '/api/v1/health');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(payload));
      await request.response.close();
    });
    return service.checkServer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );
  }

  test('accepts different APK versions when server compatibility range allows it', () async {
    final result = await respond({
      'app': 'bengkelku_pos',
      'api_version': 1,
      'app_version': '1.0.5',
      'min_client_version': '1.0.0',
      'max_client_version': '1.2.0',
      'status': 'ok',
      'server_name': 'HP Server',
    });

    expect(result.isApiReady, isTrue);
    expect(result.serverName, 'HP Server');
    expect(result.serverAppVersion, '1.0.5');
    expect(result.versionCompatibilityKnown, isTrue);
    expect(result.message, contains('kompatibel'));
  });

  test('rejects a client below the server minimum version', () async {
    final result = await respond({
      'app': 'bengkelku_pos',
      'api_version': 1,
      'app_version': '1.0.5',
      'min_client_version': '1.1.0',
      'status': 'ok',
    });

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('Client terlalu lama'));
  });

  test('rejects a client above the server maximum version', () async {
    final result = await respond({
      'app': 'bengkelku_pos',
      'api_version': 1,
      'app_version': '1.0.5',
      'min_client_version': '1.0.0',
      'max_client_version': '0.9.9',
      'status': 'ok',
    });

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('lebih baru dari batas Server'));
  });

  test('reports legacy server without version policy as not fully verified', () async {
    final result = await respond({
      'app': 'bengkelku_pos',
      'api_version': 1,
      'status': 'ok',
    });

    expect(result.isApiReady, isTrue);
    expect(result.versionCompatibilityKnown, isFalse);
    expect(result.message, contains('kompatibilitas penuh'));
  });

  test('rejects a reachable host without the health endpoint', () async {
    server.listen((request) async {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final result = await service.checkServer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('API BengkelKu Server belum tersedia'));
  });

  test('rejects a response from another application', () async {
    final result = await respond({
      'app': 'another_app',
      'api_version': 1,
      'status': 'ok',
    });

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('bukan layanan BengkelKu Server'));
  });

  test('rejects an unsupported API version', () async {
    final result = await respond({
      'app': 'bengkelku_pos',
      'api_version': 2,
      'status': 'ok',
    });

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('Versi API Server tidak cocok'));
  });
}
