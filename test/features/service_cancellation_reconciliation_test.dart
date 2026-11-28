import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'package:bengkelku_pos/core/auth/auth_session.dart';
import 'package:bengkelku_pos/core/database/app_database.dart';
import 'package:bengkelku_pos/features/customers/data/customer_wallet_repository.dart';
import 'package:bengkelku_pos/features/services/data/service_repository.dart';
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
    testDirectory = await Directory.systemTemp.createTemp(
      'bengkelku_service_reconciliation_test_',
    );
    await databaseFactory.setDatabasesPath(testDirectory.path);
    pathProviderChannel.setMockMethodCallHandler(
      (call) async => testDirectory.path,
    );
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

  test(
    'service cancellation keeps cash and wallet payment reconciliation balanced',
    () async {
      final db = await AppDatabase.instance.database;
      final (customerId, bicycleId) =
          await createRegisteredCustomerAndBicycle(db);
      final wallet = CustomerWalletRepository();
      final services = ServiceRepository();

      await wallet.addDeposit(
        customerId: customerId,
        amount: 20000,
        paymentMethod: 'cash',
      );
      final serviceId = await services.createServiceOrder(
        customerId: customerId,
        bicycleId: bicycleId,
        complaint: 'Uji rekonsiliasi pembatalan servis',
        laborCost: 100000,
        downPayment: 30000,
        downPaymentMethod: 'cash',
      );
      await services.addPayment(id: serviceId, amount: 20000);
      await services.addWalletPayment(id: serviceId, amount: 20000);

      await services.updateServiceStatus(id: serviceId, status: 'checking');
      await services.updateServiceStatus(id: serviceId, status: 'in_progress');
      await services.updateServiceStatus(id: serviceId, status: 'cancelled');

      final now = DateTime.now();
      final cashbook = CashbookRepository();
      expect(
        await cashbook.getCustomerPaymentMismatches(
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 1)),
        ),
        isEmpty,
      );
      expect(
        await cashbook.getReconciliationIssues(
          start: DateTime(2000),
          end: DateTime(2100),
        ),
        isEmpty,
      );

      final refunds = await db.query(
        'cash_transactions',
        where:
            "reference_type = 'service_order_cancellation' AND reference_id = ?",
        whereArgs: [serviceId],
      );
      expect(refunds, hasLength(1));
      expect(refunds.single['transaction_type'], 'expense');
      expect(refunds.single['amount'], 50000);

      final walletRefunds = await db.query(
        'customer_wallet_ledger',
        where:
            "reference_type = 'service_order_cancellation' AND reference_id = ? AND entry_type = 'refund'",
        whereArgs: [serviceId],
      );
      expect(walletRefunds, hasLength(1));
      expect(walletRefunds.single['amount'], 20000);
      expect(await wallet.getBalance(customerId), 20000);
    },
  );
}
