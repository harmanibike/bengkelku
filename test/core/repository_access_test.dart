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
  });
}
