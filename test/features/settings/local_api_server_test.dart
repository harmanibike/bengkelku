import 'dart:convert';
import 'dart:io';

import 'package:bengkelku_pos/features/settings/data/local_api_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalApiServer server;

  setUp(() {
    server = LocalApiServer();
  });

  tearDown(() async {
    await server.stop();
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
}
