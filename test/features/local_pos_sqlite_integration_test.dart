import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Database, databaseFactory, getDatabasesPath, openDatabase;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'package:bengkelku_pos/core/auth/auth_session.dart';
import 'package:bengkelku_pos/core/database/app_database.dart';
import 'package:bengkelku_pos/features/customers/data/customer_wallet_repository.dart';
import 'package:bengkelku_pos/features/services/data/service_repository.dart';
import 'package:bengkelku_pos/features/sales/data/sale_repository.dart';

void main() {
  late Directory testDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('bengkelku_sqlite_test_');
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

  Future<(int, int)> createRegisteredCustomerAndBicycle(Database db) async {
    final customerId = await db.insert('customers', {
      'name': 'Pelanggan Uji',
      'phone': '081234567890',
    });
    final bicycleId = await db.insert('bicycles', {
      'customer_id': customerId,
      'brand': 'Polygon',
      'model': 'Uji',
    });
    return (customerId, bicycleId);
  }

  test('wallet deposit and withdrawal keep Rupiah ledger consistent', () async {
    final db = await AppDatabase.instance.database;
    final customerId = await db.insert('customers', {'name': 'Pelanggan Saldo'});
    final wallet = CustomerWalletRepository();

    await wallet.addDeposit(
      customerId: customerId,
      amount: 150000,
      paymentMethod: 'cash',
    );
    expect(await wallet.getBalance(customerId), 150000);

    await wallet.withdrawCash(customerId: customerId, amount: 50000);
    expect(await wallet.getBalance(customerId), 100000);

    await expectLater(
      wallet.withdrawCash(customerId: customerId, amount: 100001),
      throwsA(isA<StateError>()),
    );
    expect(await wallet.getBalance(customerId), 100000);

    final ledger = await wallet.getLedger(customerId);
    expect(ledger, hasLength(2));
    expect(
      ledger.map((entry) => entry['balance_after']).toSet(),
      containsAll(<int>{150000, 100000}),
    );

    final cash = await db.query('cash_transactions');
    final deposit = cash.where((row) => row['category'] == 'Deposit Pelanggan');
    final withdrawal = cash.where((row) => row['category'] == 'Penarikan Saldo Pelanggan');
    expect(deposit.fold<int>(0, (sum, row) => sum + (row['amount'] as int)), 150000);
    expect(withdrawal.fold<int>(0, (sum, row) => sum + (row['amount'] as int)), 50000);
  });

  test('service cancellation refunds cash and wallet without mixing tip', () async {
    final db = await AppDatabase.instance.database;
    final (customerId, bicycleId) = await createRegisteredCustomerAndBicycle(db);
    final wallet = CustomerWalletRepository();
    final service = ServiceRepository();

    await wallet.addDeposit(
      customerId: customerId,
      amount: 40000,
      paymentMethod: 'cash',
    );

    final serviceId = await service.createServiceOrder(
      customerId: customerId,
      bicycleId: bicycleId,
      complaint: 'Rem belakang kurang pakem',
      laborCost: 100000,
      downPayment: 20000,
    );

    await service.addPayment(
      id: serviceId,
      amount: 30000,
      tipAmount: 5000,
      tipRecipientName: 'Mekanik Uji',
    );

    await service.updateServiceStatus(id: serviceId, status: 'checking');
    await service.updateServiceStatus(id: serviceId, status: 'in_progress');
    await service.updateServiceStatus(id: serviceId, status: 'completed');

    final completed = await service.getServiceOrderById(serviceId);
    expect(completed?['down_payment'], 90000);
    expect(completed?['remaining_payment'], 10000);
    expect(await wallet.getBalance(customerId), 0);

    // Alur status yang sah: selesai -> dikerjakan kembali -> dibatalkan.
    await service.updateServiceStatus(id: serviceId, status: 'in_progress');
    await service.updateServiceStatus(
      id: serviceId,
      status: 'cancelled',
      note: 'Pengujian pengembalian pembayaran',
    );

    expect(await wallet.getBalance(customerId), 40000);
    final walletLedger = await wallet.getLedger(customerId);
    expect(
      walletLedger.any((row) =>
          row['entry_type'] == 'refund' &&
          row['reference_type'] == 'service_order_cancellation' &&
          row['amount'] == 40000),
      isTrue,
    );

    final cash = await db.query('cash_transactions');
    final cancellationRefund = cash.where(
      (row) => row['reference_type'] == 'service_order_cancellation',
    );
    expect(
      cancellationRefund.fold<int>(
        0,
        (sum, row) => sum + (row['amount'] as int),
      ),
      50000,
    );

    final tips = await db.query(
      'tip_transactions',
      where: "source_type = 'service_order' AND source_id = ?",
      whereArgs: [serviceId],
    );
    expect(tips, hasLength(1));
    expect(tips.single['amount'], 5000);
  });


  test('sale checkout deducts stock and records cash and change correctly', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Ban Uji',
      'selling_price': 50000,
      'purchase_price': 20000,
      'stock': 3,
      'track_stock': 1,
      'is_active': 1,
    });
    await db.insert('inventory_cost_batches', {
      'product_id': productId,
      'quantity_received': 3,
      'quantity_remaining': 3,
      'unit_cost': 20000,
    });

    final saleId = await SaleRepository().checkout(
      items: [
        {'product_id': productId, 'quantity': 2, 'unit_price': 50000},
      ],
      paid: 120000,
      paymentMethod: 'cash',
    );

    final sale = (await db.query('sales', where: 'id = ?', whereArgs: [saleId])).single;
    expect(sale['total'], 100000);
    expect(sale['paid'], 100000);
    expect(sale['change_amount'], 20000);
    expect(sale['payment_status'], 'paid');

    final product = (await db.query('products', where: 'id = ?', whereArgs: [productId])).single;
    expect(product['stock'], 1);
    final batch = (await db.query('inventory_cost_batches', where: 'product_id = ?', whereArgs: [productId])).single;
    expect(batch['quantity_remaining'], 1);

    final allocations = await db.query('sale_batch_allocations', where: 'sale_id = ?', whereArgs: [saleId]);
    expect(allocations, hasLength(1));
    expect(allocations.single['quantity'], 2);

    final cash = await db.query(
      'cash_transactions',
      where: "reference_type = 'sale' AND reference_id = ?",
      whereArgs: [saleId],
    );
    expect(cash.fold<int>(0, (sum, row) => sum + (row['amount'] as int)), 100000);
  });

  test('failed sale does not create invoice or deduct stock', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Kampas Uji',
      'selling_price': 30000,
      'purchase_price': 10000,
      'stock': 1,
      'track_stock': 1,
      'is_active': 1,
    });

    await expectLater(
      SaleRepository().checkout(
        items: [
          {'product_id': productId, 'quantity': 2, 'unit_price': 30000},
        ],
        paid: 60000,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('sales'), isEmpty);
    final product = (await db.query('products', where: 'id = ?', whereArgs: [productId])).single;
    expect(product['stock'], 1);
    expect(await db.query('cash_transactions'), isEmpty);
  });

  test('version 33 migration preserves legacy return rows as unknown snapshot', () async {
    final databasePath = p.join(await getDatabasesPath(), 'bengkelku_pos.db');
    final legacyDb = await openDatabase(
      databasePath,
      version: 33,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE purchase_return_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            quantity INTEGER NOT NULL
          )
        ''');
        await db.insert('purchase_return_items', {'quantity': 2});
      },
    );
    await legacyDb.close();

    final upgradedDb = await AppDatabase.instance.database;
    final columns = await upgradedDb.rawQuery(
      'PRAGMA table_info(purchase_return_items)',
    );
    expect(columns.any((column) => column['name'] == 'stock_deducted'), isTrue);

    final legacyRows = await upgradedDb.query('purchase_return_items');
    expect(legacyRows, hasLength(1));
    expect(legacyRows.single['stock_deducted'], isNull);
    final versionRows = await upgradedDb.rawQuery('PRAGMA user_version');
    expect(versionRows.single['user_version'], AppDatabase.currentVersion);
  });
}
