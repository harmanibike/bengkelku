import 'dart:io';

import 'package:bengkelku_pos/core/database/app_database.dart';
import 'package:bengkelku_pos/features/settings/data/sync_outbox_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

void main() {
  late Directory testDirectory;
  late DateTime now;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDirectory =
        await Directory.systemTemp.createTemp('bike_pos_sync_outbox_test_');
    await databaseFactory.setDatabasesPath(testDirectory.path);
    now = DateTime.utc(2026, 11, 28, 10);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  SyncOutboxRepository createRepository() {
    return SyncOutboxRepository(clock: () => now);
  }

  Future<int> enqueue(
    SyncOutboxRepository repository, {
    String eventId = 'sale:INV-001',
    int entityId = 1,
  }) async {
    final db = await AppDatabase.instance.database;
    return db.transaction((txn) => repository.enqueue(
          txn,
          eventId: eventId,
          entityType: 'sale',
          entityId: entityId,
          operation: 'create',
          payload: {
            'schema_version': 1,
            'sale': {'invoice_number': 'INV-001', 'total': 25000},
            'items': [
              {'product_name': 'Ban dalam', 'quantity': 1},
            ],
          },
        ));
  }

  test('stores an event once and rejects reuse of its id with other data',
      () async {
    final repository = createRepository();
    final firstId = await enqueue(repository);
    final secondId = await enqueue(repository);

    expect(secondId, firstId);
    final db = await AppDatabase.instance.database;
    expect(await db.query('sync_outbox'), hasLength(1));

    await expectLater(
      db.transaction((txn) => repository.enqueue(
            txn,
            eventId: 'sale:INV-001',
            entityType: 'sale',
            entityId: 1,
            operation: 'create',
            payload: {'sale': {'total': 999}},
          )),
      throwsA(isA<StateError>()),
    );
    expect(await db.query('sync_outbox'), hasLength(1));
  });

  test('claims events once, recovers expired leases, and acknowledges them',
      () async {
    final repository = createRepository();
    await enqueue(repository);

    final firstClaim = await repository.claimPending();
    expect(firstClaim, hasLength(1));
    expect(firstClaim.single['status'], 'in_flight');
    expect(firstClaim.single['attempt_count'], 1);
    expect(await repository.claimPending(), isEmpty);

    now = now.add(const Duration(minutes: 3));
    final recoveredClaim = await repository.claimPending();
    expect(recoveredClaim, hasLength(1));
    expect(recoveredClaim.single['attempt_count'], 2);

    await repository.markSynced(
      'sale:INV-001',
      serverAckId: 'server-sale-901',
    );
    expect(await repository.claimPending(), isEmpty);
    expect(await repository.getCounts(), {
      'pending': 0,
      'in_flight': 0,
      'failed': 0,
      'synced': 1,
    });

    final db = await AppDatabase.instance.database;
    final row = (await db.query('sync_outbox')).single;
    expect(row['server_ack_id'], 'server-sale-901');
    expect(row['synced_at'], isNotNull);
  });

  test('failed events use delayed retry and preserve bounded error text',
      () async {
    final repository = createRepository();
    await enqueue(repository);
    final claim = await repository.claimPending();
    expect(claim, hasLength(1));

    await repository.markFailed('sale:INV-001', 'network unavailable');
    expect(await repository.claimPending(), isEmpty);
    expect((await repository.getCounts())['failed'], 1);

    now = now.add(const Duration(seconds: 6));
    final retry = await repository.claimPending();
    expect(retry, hasLength(1));
    expect(retry.single['attempt_count'], 2);

    await repository.markFailed('sale:INV-001', 'x' * 700);
    final db = await AppDatabase.instance.database;
    final row = (await db.query('sync_outbox')).single;
    expect((row['last_error'] as String).length, 500);
    expect(row['status'], 'failed');
  });

  test('rejects invalid claim limits and malformed event identifiers',
      () async {
    final repository = createRepository();
    await expectLater(
      repository.claimPending(limit: 0),
      throwsArgumentError,
    );

    final db = await AppDatabase.instance.database;
    await expectLater(
      db.transaction((txn) => repository.enqueue(
            txn,
            eventId: ' ',
            entityType: 'sale',
            entityId: 1,
            operation: 'create',
            payload: const {},
          )),
      throwsArgumentError,
    );
  });
}
