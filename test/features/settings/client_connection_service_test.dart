import 'package:bengkelku_pos/features/settings/data/client_connection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy plaintext connection check fails closed without opening HTTP', () async {
    final service = ClientConnectionService();

    final result = await service.checkServer(
      host: '127.0.0.1',
      port: 8765,
    );

    expect(result.isApiReady, isFalse);
    expect(result.versionCompatibilityKnown, isFalse);
    expect(result.message, contains('HTTP tanpa enkripsi dinonaktifkan'));
  });
}
