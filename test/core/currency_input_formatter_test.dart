import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/core/formatters/currency_input_formatter.dart';

void main() {
  group('CurrencyInputFormatter', () {
    const formatter = CurrencyInputFormatter();

    test('formats Indonesian thousands separators while typing', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '10000',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );

      expect(result.text, '10.000');
      expect(result.selection.extentOffset, 6);
    });

    test('parses formatted Rupiah back to an integer', () {
      expect(parseCurrencyInput('10.000'), 10000);
      expect(parseCurrencyInput('1.250.000'), 1250000);
    });

    test('formats prefilled amounts consistently', () {
      expect(formatCurrencyInput(10000), '10.000');
      expect(formatCurrencyInput('1250000'), '1.250.000');
      expect(formatCurrencyInput(0), '0');
    });

    test('allows clearing the field', () {
      final result = formatter.formatEditUpdate(
        const TextEditingValue(
          text: '10.000',
          selection: TextSelection.collapsed(offset: 6),
        ),
        const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        ),
      );

      expect(result.text, isEmpty);
      expect(parseCurrencyInput(result.text), 0);
    });
  });
}
