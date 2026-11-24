import 'package:flutter_test/flutter_test.dart';

import 'package:bengkelku_pos/core/auth/auth_session.dart';
import 'package:bengkelku_pos/features/sales/data/sale_return_repository.dart';
import 'package:bengkelku_pos/features/purchases/data/purchase_return_repository.dart';
import 'package:bengkelku_pos/features/products/data/stock_opname_repository.dart';
import 'package:bengkelku_pos/features/purchases/data/supplier_repository.dart';
import 'package:bengkelku_pos/features/reports/data/cashbook_repository.dart';
import 'package:bengkelku_pos/features/receivables/data/receivable_repository.dart';
import 'package:bengkelku_pos/features/services/data/service_repository.dart';
import 'package:bengkelku_pos/features/reports/data/report_repository.dart';
import 'package:bengkelku_pos/core/database/database_backup_service.dart';
import 'package:bengkelku_pos/features/customers/data/customer_wallet_repository.dart';
import 'package:bengkelku_pos/features/sales/data/sale_repository.dart';
import 'package:bengkelku_pos/features/products/data/product_repository.dart';
import 'package:bengkelku_pos/features/business/data/business_profile_repository.dart';
import 'package:bengkelku_pos/features/purchases/data/purchase_cost_settings_repository.dart';
import 'package:bengkelku_pos/features/purchases/data/purchase_report_repository.dart';
import 'package:bengkelku_pos/features/services/data/service_pricing_repository.dart';
import 'package:bengkelku_pos/features/settings/data/device_mode_repository.dart';
import 'package:bengkelku_pos/features/settings/data/payment_methods_repository.dart';
import 'package:bengkelku_pos/features/settings/data/business_settings_repository.dart';
import 'package:bengkelku_pos/features/settings/data/receipt_settings_repository.dart';

void main() {
  setUp(() {
    AuthSession.instance.signOut();
  });

  group('Repository role protection', () {
    test('sale returns reject unauthenticated access', () async {
      await expectLater(
        SaleReturnRepository().getReturns(),
        throwsA(isA<StateError>()),
      );
    });

    test('purchase returns reject unauthenticated access', () async {
      await expectLater(
        PurchaseReturnRepository().getPurchases(),
        throwsA(isA<StateError>()),
      );
    });

    test('stock opname rejects unauthenticated access', () async {
      await expectLater(
        StockOpnameRepository().getSessions(),
        throwsA(isA<StateError>()),
      );
    });

    test('supplier records reject unauthenticated access', () async {
      await expectLater(
        SupplierRepository().getSuppliers(),
        throwsA(isA<StateError>()),
      );
    });

    test('cashbook rejects unauthenticated access', () async {
      await expectLater(
        CashbookRepository().getLedger(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 2),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('receivables reject unauthenticated access', () async {
      await expectLater(
        ReceivableRepository().getReceivables(),
        throwsA(isA<StateError>()),
      );
    });

    test('service payment rejects unauthenticated access', () async {
      await expectLater(
        ServiceRepository().addPayment(id: 1, amount: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('service intake rejects unauthenticated access', () async {
      await expectLater(
        ServiceRepository().createServiceOrder(complaint: 'Tes akses'),
        throwsA(isA<StateError>()),
      );
    });

    test('service receivables reject unauthenticated access', () async {
      await expectLater(
        ServiceRepository().getOutstandingServiceOrders(),
        throwsA(isA<StateError>()),
      );
    });

    test('service list rejects unauthenticated access', () async {
      await expectLater(
        ServiceRepository().getServiceOrders(),
        throwsA(isA<StateError>()),
      );
    });

    test('financial reports reject unauthenticated access', () async {
      await expectLater(
        ReportRepository().getSummary(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 2),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('database backup rejects unauthenticated access', () async {
      await expectLater(
        DatabaseBackupService().createBackup(),
        throwsA(isA<StateError>()),
      );
    });

    test('database restore rejects unauthenticated access', () async {
      await expectLater(
        DatabaseBackupService().restoreBackup('/not-used.db'),
        throwsA(isA<StateError>()),
      );
    });

    test('mechanic cannot process customer wallet deposit or withdrawal', () async {
      AuthSession.instance.signIn({
        'id': 7,
        'role': 'mechanic',
        'display_name': 'Mekanik Tes',
      });
      final wallet = CustomerWalletRepository();
      await expectLater(
        wallet.addDeposit(
          customerId: 1,
          amount: 10000,
          paymentMethod: 'cash',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        wallet.withdrawCash(customerId: 1, amount: 10000),
        throwsA(isA<StateError>()),
      );
    });

    test('mechanic cannot create a POS sale', () async {
      AuthSession.instance.signIn({
        'id': 7,
        'role': 'mechanic',
        'display_name': 'Mekanik Tes',
      });
      await expectLater(
        SaleRepository().checkout(items: [], paid: 0),
        throwsA(isA<StateError>()),
      );
    });

    test('mechanic cannot cancel a service order', () async {
      AuthSession.instance.signIn({
        'id': 7,
        'role': 'mechanic',
        'display_name': 'Mekanik Tes',
      });
      await expectLater(
        ServiceRepository().updateServiceStatus(
          id: 1,
          status: 'cancelled',
          actingMechanicId: 7,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot make manual stock adjustments', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      await expectLater(
        ProductRepository().adjustStock(
          productId: 1,
          quantity: 1,
          isStockIn: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot create manual cashbook transactions', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      await expectLater(
        CashbookRepository().addManualTransaction(
          type: 'expense',
          category: 'Tes',
          description: 'Tes akses',
          amount: 10000,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot create or restore database backups', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      final backup = DatabaseBackupService();
      await expectLater(backup.createBackup(), throwsA(isA<StateError>()));
      await expectLater(
        backup.restoreBackup('/not-used.db'),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot access purchase cost configuration or report', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      await expectLater(
        PurchaseCostSettingsRepository().setMethod('per_batch'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        PurchaseReportRepository().getReport(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 2),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot change business profile or service pricing', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      await expectLater(
        BusinessProfileRepository().saveProfile({'business_name': 'Tes'}),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        ServicePricingRepository().saveService(
          name: 'Tes jasa',
          standardPrice: 10000,
          reason: 'Tes',
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        ServicePricingRepository().getPriceHistory(),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot change device connection settings', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      final devices = DeviceModeRepository();
      await expectLater(
        devices.saveClientConfig(host: '192.168.1.2', port: 8765),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        devices.saveMode(DeviceModeRepository.localMode),
        throwsA(isA<StateError>()),
      );
    });

    test('cashier cannot change payment, loyalty, or receipt settings', () async {
      AuthSession.instance.signIn({
        'id': 8,
        'role': 'cashier',
        'display_name': 'Kasir Tes',
      });
      await expectLater(
        PaymentMethodsRepository().saveEnabledCodes({'cash'}),
        throwsA(isA<StateError>()),
      );
      expect(
        () => BusinessSettingsRepository().saveLoyaltySettings(
          const LoyaltySettings(enabled: true),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => BusinessSettingsRepository().saveStockReminderSettings(
          const StockReminderSettings(enabled: true),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        ReceiptSettingsRepository().saveReceiptSettings(
          const ReceiptPrintSettings(),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        ReceiptSettingsRepository().saveCashDrawerAutoOpen(true),
        throwsA(isA<StateError>()),
      );
    });
  });
}
