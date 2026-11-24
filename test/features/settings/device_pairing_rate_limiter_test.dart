import 'dart:io';

import 'package:bengkelku_pos/core/database/app_database.dart';
import 'package:bengkelku_pos/features/settings/data/device_pairing_rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

void main() {
  late Directory testDirectory;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('bengkelku_rate_limit_test_');
    await databaseFactory.setDatabasesPath(testDirectory.path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('blocks after five failures and persists across limiter instances', () async {
    var now = DateTime.utc(2026, 11, 24, 10);
    final limiter = DevicePairingRateLimiter(clock: () => now);
    const address = '192.168.1.20';

    expect(await limiter.isAllowed(address), isTrue);
    for (var i = 0; i < 4; i++) {
      await limiter.recordFailure(address);
      expect(await limiter.isAllowed(address), isTrue);
    }
    await limiter.recordFailure(address);
    expect(await limiter.isAllowed(address), isFalse);

    final restartedLimiter = DevicePairingRateLimiter(clock: () => now);
    expect(await restartedLimiter.isAllowed(address), isFalse);

    now = now.add(const Duration(minutes: 16));
    expect(await restartedLimiter.isAllowed(address), isTrue);
  });

  test('clears failures after successful pairing and isolates IP addresses', () async {
    final limiter = DevicePairingRateLimiter();
    await limiter.recordFailure('192.168.1.20');
    await limiter.recordFailure('192.168.1.20');

    expect(await limiter.isAllowed('192.168.1.21'), isTrue);
    await limiter.clearAfterSuccess('192.168.1.20');
    expect(await limiter.isAllowed('192.168.1.20'), isTrue);
  });

  test('rejects invalid client addresses', () async {
    final limiter = DevicePairingRateLimiter();
    await expectLater(
      limiter.recordFailure('not-an-ip'),
      throwsA(isA<ArgumentError>()),
    );
  });
}
