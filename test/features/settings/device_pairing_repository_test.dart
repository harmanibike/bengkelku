import 'dart:io';

import 'package:bengkelku_pos/core/auth/auth_session.dart';
import 'package:bengkelku_pos/core/database/app_database.dart';
import 'package:bengkelku_pos/features/settings/data/device_pairing_repository.dart';
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
    testDirectory = await Directory.systemTemp.createTemp('bengkelku_pairing_test_');
    await databaseFactory.setDatabasesPath(testDirectory.path);
    AuthSession.instance.signIn({
      'id': 1,
      'role': 'admin',
      'display_name': 'Admin Pengujian',
    });
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AuthSession.instance.signOut();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('pairing code is one-time and raw token is never stored', () async {
    final repository = DevicePairingRepository();
    final pairingCode = await repository.createPairingCode();
    expect(pairingCode.code, matches(RegExp(r'^\d{10}$')));

    AuthSession.instance.signOut();
    final credential = await repository.pairDevice(
      code: pairingCode.code,
      deviceName: 'HP Kasir 1',
    );
    expect(credential.token, hasLength(64));
    expect(credential.deviceName, 'HP Kasir 1');

    final db = await AppDatabase.instance.database;
    final stored = await db.query('paired_devices', limit: 1);
    expect(stored.single['token_hash'], isNot(credential.token));
    expect(stored.single['token_hash'], hasLength(64));

    final authenticated = await repository.authenticateDevice(credential.token);
    expect(authenticated?.deviceName, 'HP Kasir 1');
    expect(await repository.authenticateDevice('invalid'), isNull);

    await expectLater(
      repository.pairDevice(
        code: pairingCode.code,
        deviceName: 'HP Client Kedua',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('expired pairing code cannot be exchanged', () async {
    var now = DateTime.utc(2026, 11, 24, 10);
    final repository = DevicePairingRepository(clock: () => now);
    final pairingCode = await repository.createPairingCode(
      lifetime: const Duration(seconds: 30),
    );
    now = now.add(const Duration(seconds: 31));

    await expectLater(
      repository.pairDevice(
        code: pairingCode.code,
        deviceName: 'HP Client',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('only Admin can create pairing codes, list and revoke devices', () async {
    final repository = DevicePairingRepository();
    AuthSession.instance.signIn({
      'id': 2,
      'role': 'cashier',
      'display_name': 'Kasir',
    });
    await expectLater(
      repository.createPairingCode(),
      throwsA(isA<StateError>()),
    );

    AuthSession.instance.signIn({
      'id': 1,
      'role': 'admin',
      'display_name': 'Admin',
    });
    final code = await repository.createPairingCode();
    AuthSession.instance.signOut();
    final credential = await repository.pairDevice(
      code: code.code,
      deviceName: 'HP Client',
    );

    AuthSession.instance.signIn({
      'id': 2,
      'role': 'cashier',
      'display_name': 'Kasir',
    });
    await expectLater(
      repository.getPairedDevices(),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.revokeDevice(credential.deviceId),
      throwsA(isA<StateError>()),
    );

    AuthSession.instance.signIn({
      'id': 1,
      'role': 'admin',
      'display_name': 'Admin',
    });
    expect(await repository.getPairedDevices(), hasLength(1));
    await repository.revokeDevice(credential.deviceId);
    expect(await repository.authenticateDevice(credential.token), isNull);
    expect(await repository.getPairedDevices(), isEmpty);
  });
}
