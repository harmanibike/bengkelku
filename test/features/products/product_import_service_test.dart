import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/features/products/data/product_import_service.dart';

void main() {
  group('ProductImportService.parseInteger', () {
    test('parses Indonesian and spreadsheet thousand separators', () {
      expect(ProductImportService.parseInteger('1500'), 1500);
      expect(ProductImportService.parseInteger('1.500'), 1500);
      expect(ProductImportService.parseInteger('1,500'), 1500);
      expect(ProductImportService.parseInteger('Rp 1.500,00'), 1500);
      expect(ProductImportService.parseInteger('1,500.00'), 1500);
      expect(ProductImportService.parseInteger('1.250.000'), 1250000);
    });

    test('treats empty cells as zero', () {
      expect(ProductImportService.parseInteger(null), 0);
      expect(ProductImportService.parseInteger(''), 0);
      expect(ProductImportService.parseInteger('   '), 0);
    });

    test('rejects non-zero fractional and malformed values', () {
      expect(ProductImportService.parseInteger('1.5'), -1);
      expect(ProductImportService.parseInteger('1,25'), -1);
      expect(ProductImportService.parseInteger('Rp bukan angka'), -1);
      expect(ProductImportService.parseInteger('1.20.300'), -1);
    });

    test('preserves negative values for validation to reject', () {
      expect(ProductImportService.parseInteger('-100'), -100);
    });
  });
}
