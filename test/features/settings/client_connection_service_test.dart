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

  test('accepts a valid BengkelKu health response', () async {
    server.listen((request) async {
      expect(request.uri.path, '/api/v1/health');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'api_version': 1,
        'status': 'ok',
        'server_name': 'HP Server',
      }));
      await request.response.close();
    });

    final result = await service.checkServer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    expect(result.isApiReady, isTrue);
    expect(result.serverName, 'HP Server');
    expect(result.apiVersion, 1);
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
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'another_app',
        'api_version': 1,
        'status': 'ok',
      }));
      await request.response.close();
    });

    final result = await service.checkServer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('bukan layanan BengkelKu Server'));
  });

  test('rejects an unsupported API version', () async {
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'app': 'bengkelku_pos',
        'api_version': 2,
        'status': 'ok',
      }));
      await request.response.close();
    });

    final result = await service.checkServer(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    );

    expect(result.isApiReady, isFalse);
    expect(result.message, contains('Versi API Server tidak cocok'));
  });
}
