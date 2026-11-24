import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/features/receipts/data/receipt_document_service.dart';

void main() {
  group('ReceiptDocumentService', () {
    test('formats Indonesian Rupiah with thousand separators', () {
      expect(ReceiptDocumentService.rupiah(0), 'Rp.0');
      expect(ReceiptDocumentService.rupiah(12500), 'Rp.12.500');
      expect(ReceiptDocumentService.rupiah(1234567), 'Rp.1.234.567');
    });

    test('returns dash for invalid receipt date', () {
      expect(ReceiptDocumentService.dateLabel('not-a-date'), '-');
    });
  });
}
