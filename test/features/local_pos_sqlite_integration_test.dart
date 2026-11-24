import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Database, databaseFactory, getDatabasesPath, openDatabase;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'package:bengkelku_pos/core/auth/auth_session.dart';
import 'package:bengkelku_pos/core/database/app_database.dart';
import 'package:bengkelku_pos/core/database/database_backup_service.dart';
import 'package:bengkelku_pos/features/customers/data/customer_wallet_repository.dart';
import 'package:bengkelku_pos/features/services/data/service_repository.dart';
import 'package:bengkelku_pos/features/sales/data/sale_repository.dart';
import 'package:bengkelku_pos/features/sales/data/sale_return_repository.dart';
import 'package:bengkelku_pos/features/purchases/data/purchase_return_repository.dart';
import 'package:bengkelku_pos/features/purchases/data/purchase_repository.dart';
import 'package:bengkelku_pos/features/reports/data/cashbook_repository.dart';

void main() {
  late Directory testDirectory;
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp('bengkelku_sqlite_test_');
    await databaseFactory.setDatabasesPath(testDirectory.path);
    pathProviderChannel.setMockMethodCallHandler((call) async => testDirectory.path);
    AuthSession.instance.signIn({
      'id': 1,
      'role': 'admin',
      'display_name': 'Admin Pengujian',
    });
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AuthSession.instance.signOut();
    pathProviderChannel.setMockMethodCallHandler(null);
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

  test('supplier payment history and cashbook stay synchronized', () async {
    final db = await AppDatabase.instance.database;
    final supplierId = await db.insert('suppliers', {'name': 'Pemasok Uji'});
    final purchases = PurchaseRepository();
    final purchaseId = await purchases.createPurchase(
      invoiceNumber: 'INV-UJI-REKON-001',
      supplierId: supplierId,
      items: [
        {
          'product_id': null,
          'product_name': 'Barang Uji',
          'quantity': 1,
          'unit_cost': 100000,
          'discount': 0,
        },
      ],
      initialPayment: 30000,
      paymentMethod: 'cash',
    );

    // Audit harus mendeteksi nominal kas yang berbeda dari riwayat pembayaran.
    await db.update(
      'cash_transactions',
      {'amount': 29000},
      where: "reference_type = 'purchase_payment' AND reference_id = ?",
      whereArgs: [purchaseId],
    );
    final detected = await CashbookRepository().getSupplierPaymentMismatches(
      start: DateTime(2000),
      end: DateTime(2100),
    );
    expect(detected, hasLength(1));
    expect(detected.single['difference'], 1000);

    // Setelah nominal dipulihkan dan pembayaran tambahan dicatat,
    // kedua sumber harus kembali cocok.
    await db.update(
      'cash_transactions',
      {'amount': 30000},
      where: "reference_type = 'purchase_payment' AND reference_id = ?",
      whereArgs: [purchaseId],
    );
    await purchases.addPayment(purchaseId: purchaseId, amount: 20000);
    final clean = await CashbookRepository().getSupplierPaymentMismatches(
      start: DateTime(2000),
      end: DateTime(2100),
    );
    expect(clean, isEmpty);
  });

  test('database backup creation is restricted to Admin', () async {
    AuthSession.instance.signOut();
    await expectLater(
      DatabaseBackupService().createBackup(),
      throwsA(isA<StateError>()),
    );
  });

  test('database backup restores data and preserves a safety copy', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Produk Sebelum Backup',
      'selling_price': 50000,
      'purchase_price': 25000,
      'stock': 4,
      'track_stock': 1,
      'is_active': 1,
    });

    final backupService = DatabaseBackupService();
    final backup = await backupService.createBackup();
    expect(await backup.exists(), isTrue);
    expect(await backup.length(), greaterThan(100));

    final currentDb = await AppDatabase.instance.database;
    await currentDb.update(
      'products',
      {'name': 'Produk Setelah Backup'},
      where: 'id = ?',
      whereArgs: [productId],
    );

    final safetyCopyPath = await backupService.restoreBackup(backup.path);
    expect(await File(safetyCopyPath).exists(), isTrue);

    final restoredDb = await AppDatabase.instance.database;
    final restored = await restoredDb.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    expect(restored.single['name'], 'Produk Sebelum Backup');
    expect(
      (await restoredDb.rawQuery('PRAGMA integrity_check')).single.values.first,
      'ok',
    );
  });

  test('invalid database backup is rejected and temporary candidate is removed', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Data Tetap Aman',
      'selling_price': 10000,
      'purchase_price': 5000,
      'stock': 1,
      'track_stock': 1,
      'is_active': 1,
    });

    final invalidBackup = File(p.join(testDirectory.path, 'invalid_backup.db'));
    final invalidDb = await openDatabase(
      invalidBackup.path,
      version: AppDatabase.currentVersion,
      onCreate: (database, version) async {
        await database.execute('CREATE TABLE unrelated (id INTEGER PRIMARY KEY)');
      },
    );
    await invalidDb.close();

    final backupService = DatabaseBackupService();
    await expectLater(
      backupService.restoreBackup(invalidBackup.path),
      throwsA(isA<FormatException>()),
    );

    final candidates = Directory(p.join(testDirectory.path, 'BengkelKuBackups'));
    final leftovers = await candidates
        .list()
        .where((entity) => p.basename(entity.path).startsWith('restore_candidate_'))
        .toList();
    expect(leftovers, isEmpty);

    final unchangedDb = await AppDatabase.instance.database;
    final unchanged = await unchangedDb.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    expect(unchanged.single['name'], 'Data Tetap Aman');
  });

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

    final issues = await CashbookRepository().getReconciliationIssues(
      start: DateTime(2000),
      end: DateTime(2100),
    );
    expect(issues, isEmpty);
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

    final paymentMismatches = await CashbookRepository().getCustomerPaymentMismatches(
      start: DateTime(2000),
      end: DateTime(2100),
    );
    expect(paymentMismatches, isEmpty);

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

    final reconciliationIssues = await CashbookRepository().getReconciliationIssues(
      start: DateTime(2000),
      end: DateTime(2100),
    );
    expect(reconciliationIssues, isEmpty);
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

  test('sale return restores original stock batch and records cash refund', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Rantai Uji',
      'selling_price': 50000,
      'purchase_price': 20000,
      'stock': 3,
      'track_stock': 1,
      'is_active': 1,
    });
    final batchId = await db.insert('inventory_cost_batches', {
      'product_id': productId,
      'quantity_received': 3,
      'quantity_remaining': 3,
      'unit_cost': 20000,
    });

    final saleId = await SaleRepository().checkout(
      items: [
        {'product_id': productId, 'quantity': 2, 'unit_price': 50000},
      ],
      paid: 100000,
      paymentMethod: 'cash',
    );
    final saleItem = (await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    )).single;

    final returnId = await SaleReturnRepository().createReturn(
      saleId: saleId,
      items: [
        {'sale_item_id': saleItem['id'], 'quantity': 1},
      ],
      refundAmount: 50000,
      notes: 'Barang dikembalikan',
    );

    final product = (await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    final batch = (await db.query(
      'inventory_cost_batches',
      where: 'id = ?',
      whereArgs: [batchId],
    )).single;
    expect(product['stock'], 2);
    expect(batch['quantity_remaining'], 2);

    final allocations = await db.query(
      'sale_return_batch_allocations',
      where: 'batch_id = ?',
      whereArgs: [batchId],
    );
    expect(allocations, hasLength(1));
    expect(allocations.single['quantity'], 1);

    final refund = (await db.query(
      'cash_transactions',
      where: "reference_type = 'sale_return' AND reference_id = ?",
      whereArgs: [returnId],
    )).single;
    expect(refund['transaction_type'], 'expense');
    expect(refund['amount'], 50000);

    final sale = (await db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
    )).single;
    expect(sale['payment_status'], 'paid');
    expect(await SaleReturnRepository().getReturnableItems(saleId), isNotEmpty);
  });

  test('sale return rejects quantities beyond the remaining returnable amount', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Kabel Uji',
      'selling_price': 25000,
      'purchase_price': 10000,
      'stock': 2,
      'track_stock': 1,
      'is_active': 1,
    });
    await db.insert('inventory_cost_batches', {
      'product_id': productId,
      'quantity_received': 2,
      'quantity_remaining': 2,
      'unit_cost': 10000,
    });

    final saleId = await SaleRepository().checkout(
      items: [
        {'product_id': productId, 'quantity': 2, 'unit_price': 25000},
      ],
      paid: 50000,
      paymentMethod: 'cash',
    );
    final saleItem = (await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    )).single;
    final returns = SaleReturnRepository();

    await returns.createReturn(
      saleId: saleId,
      items: [
        {'sale_item_id': saleItem['id'], 'quantity': 1},
      ],
      refundAmount: 25000,
    );

    await expectLater(
      returns.createReturn(
        saleId: saleId,
        items: [
          {'sale_item_id': saleItem['id'], 'quantity': 2},
        ],
        refundAmount: 50000,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('sale_returns'), hasLength(1));
    final product = (await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    expect(product['stock'], 1);
  });

  test('sale return prorates invoice discount across returned quantity', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Gear Uji',
      'selling_price': 50000,
      'purchase_price': 20000,
      'stock': 2,
      'track_stock': 1,
      'is_active': 1,
    });
    await db.insert('inventory_cost_batches', {
      'product_id': productId,
      'quantity_received': 2,
      'quantity_remaining': 2,
      'unit_cost': 20000,
    });

    final saleId = await SaleRepository().checkout(
      items: [
        {'product_id': productId, 'quantity': 2, 'unit_price': 50000},
      ],
      discount: 20000,
      paid: 80000,
      paymentMethod: 'cash',
    );
    final saleItem = (await db.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    )).single;

    final returnId = await SaleReturnRepository().createReturn(
      saleId: saleId,
      items: [
        {'sale_item_id': saleItem['id'], 'quantity': 1},
      ],
      refundAmount: 40000,
    );

    final returned = (await db.query(
      'sale_returns',
      where: 'id = ?',
      whereArgs: [returnId],
    )).single;
    expect(returned['total_amount'], 40000);
    expect(returned['refunded_amount'], 40000);
    final expense = (await db.query(
      'cash_transactions',
      where: "reference_type = 'sale_return' AND reference_id = ?",
      whereArgs: [returnId],
    )).single;
    expect(expense['amount'], 40000);
  });

  test('purchase return cancellation restores stock and original cost batch', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Pedal Uji',
      'selling_price': 60000,
      'purchase_price': 25000,
      'stock': 5,
      'track_stock': 1,
      'is_active': 1,
    });
    final purchaseId = await db.insert('purchases', {
      'invoice_number': 'PO-RETUR-UJI-001',
      'subtotal': 75000,
      'total': 75000,
      'paid': 75000,
      'payment_status': 'paid',
      'status': 'active',
    });
    final purchaseItemId = await db.insert('purchase_items', {
      'purchase_id': purchaseId,
      'product_id': productId,
      'product_name': 'Pedal Uji',
      'quantity': 3,
      'unit_cost': 25000,
      'subtotal': 75000,
    });
    final batchId = await db.insert('inventory_cost_batches', {
      'product_id': productId,
      'purchase_id': purchaseId,
      'purchase_item_id': purchaseItemId,
      'quantity_received': 3,
      'quantity_remaining': 3,
      'unit_cost': 25000,
    });

    final returns = PurchaseReturnRepository();
    final returnId = await returns.createReturn(
      purchaseId: purchaseId,
      returnNumber: 'PR-RETUR-UJI-001',
      quantities: {purchaseItemId: 2},
      notes: 'Pengujian retur pembelian',
    );

    var product = (await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    var batch = (await db.query(
      'inventory_cost_batches',
      where: 'id = ?',
      whereArgs: [batchId],
    )).single;
    expect(product['stock'], 3);
    expect(batch['quantity_remaining'], 1);

    await returns.cancelReturn(
      returnId: returnId,
      reason: 'Retur dibatalkan untuk pengujian',
    );

    product = (await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    batch = (await db.query(
      'inventory_cost_batches',
      where: 'id = ?',
      whereArgs: [batchId],
    )).single;
    expect(product['stock'], 5);
    expect(batch['quantity_remaining'], 3);

    final returnRow = (await db.query(
      'purchase_returns',
      where: 'id = ?',
      whereArgs: [returnId],
    )).single;
    expect(returnRow['status'], 'cancelled');
    final movements = await db.query(
      'stock_movements',
      where: 'reference_type = ? AND reference_id = ?',
      whereArgs: ['purchase_return_cancel', returnId],
    );
    expect(movements, hasLength(1));
    expect(movements.single['quantity'], 2);
  });

  test('purchase return rejects quantity beyond remaining purchased amount', () async {
    final db = await AppDatabase.instance.database;
    final productId = await db.insert('products', {
      'name': 'Sadel Uji',
      'selling_price': 40000,
      'purchase_price': 15000,
      'stock': 2,
      'track_stock': 1,
      'is_active': 1,
    });
    final purchaseId = await db.insert('purchases', {
      'invoice_number': 'PO-RETUR-UJI-002',
      'subtotal': 30000,
      'total': 30000,
      'paid': 30000,
      'payment_status': 'paid',
      'status': 'active',
    });
    final purchaseItemId = await db.insert('purchase_items', {
      'purchase_id': purchaseId,
      'product_id': productId,
      'product_name': 'Sadel Uji',
      'quantity': 2,
      'unit_cost': 15000,
      'subtotal': 30000,
    });
    await db.insert('inventory_cost_batches', {
      'product_id': productId,
      'purchase_id': purchaseId,
      'purchase_item_id': purchaseItemId,
      'quantity_received': 2,
      'quantity_remaining': 2,
      'unit_cost': 15000,
    });

    final returns = PurchaseReturnRepository();
    await returns.createReturn(
      purchaseId: purchaseId,
      returnNumber: 'PR-RETUR-UJI-002',
      quantities: {purchaseItemId: 1},
    );
    await expectLater(
      returns.createReturn(
        purchaseId: purchaseId,
        returnNumber: 'PR-RETUR-UJI-003',
        quantities: {purchaseItemId: 2},
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.query('purchase_returns'), hasLength(1));
    final product = (await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
    )).single;
    expect(product['stock'], 1);
  });


  test('cashbook calculates opening, running and closing balances consistently', () async {
    final db = await AppDatabase.instance.database;
    await db.insert('cash_transactions', {
      'transaction_type': 'income',
      'category': 'Modal awal',
      'description': 'Saldo sebelum periode',
      'amount': 10000,
      'reference_type': 'manual_cash',
      'transaction_date': '2026-01-01T09:00:00.000',
    });
    await db.insert('cash_transactions', {
      'transaction_type': 'income',
      'category': 'Penjualan',
      'description': 'Kas masuk',
      'amount': 5000,
      'reference_type': 'manual_cash',
      'transaction_date': '2026-01-02T09:00:00.000',
    });
    await db.insert('cash_transactions', {
      'transaction_type': 'expense',
      'category': 'Operasional',
      'description': 'Kas keluar',
      'amount': 2000,
      'reference_type': 'manual_cash',
      'transaction_date': '2026-01-02T10:00:00.000',
    });

    final cashbook = CashbookRepository();
    final ledger = await cashbook.getLedger(
      start: DateTime(2026, 1, 2),
      end: DateTime(2026, 1, 3),
    );
    expect(ledger['opening_balance'], 10000);
    expect(ledger['income'], 5000);
    expect(ledger['expense'], 2000);
    expect(ledger['closing_balance'], 13000);
    final entries = ledger['entries'] as List<Map<String, Object?>>;
    expect(entries, hasLength(2));
    expect(entries.first['running_balance'], 13000);
    expect(entries.last['running_balance'], 15000);

    final incomeOnly = await cashbook.getLedger(
      start: DateTime(2026, 1, 2),
      end: DateTime(2026, 1, 3),
      type: 'income',
    );
    expect(incomeOnly['entries'], hasLength(1));
    // Filter hanya menyaring daftar transaksi; saldo dan ringkasan tetap total periode.
    expect(incomeOnly['income'], 5000);
    expect(incomeOnly['expense'], 2000);
    expect(incomeOnly['closing_balance'], 13000);
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
