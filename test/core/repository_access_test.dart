import 'package:flutter_test/flutter_test.dart';

import 'package:bengkelku/core/auth/auth_session.dart';
import 'package:bengkelku/features/sales/data/sale_return_repository.dart';
import 'package:bengkelku/features/purchases/data/purchase_return_repository.dart';
import 'package:bengkelku/features/products/data/stock_opname_repository.dart';
import 'package:bengkelku/features/purchases/data/supplier_repository.dart';
import 'package:bengkelku/features/reports/data/cashbook_repository.dart';
import 'package:bengkelku/features/receivables/data/receivable_repository.dart';

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
  });
}
