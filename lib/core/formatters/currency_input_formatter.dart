import 'package:flutter/services.dart';

/// Formats whole-number Rupiah input with Indonesian thousands separators.
/// Example: 10000 becomes 10.000 while the stored value remains parseable.
class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final rawText = newValue.text;
    final digits = rawText.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final selectionOffset = newValue.selection.isValid
        ? newValue.selection.extentOffset.clamp(0, rawText.length)
        : rawText.length;
    final digitsBeforeCursor = rawText
        .substring(0, selectionOffset)
        .replaceAll(RegExp(r'[^0-9]'), '')
        .length;

    final formatted = formatCurrencyInput(digits);
    var cursor = 0;
    var countedDigits = 0;
    while (cursor < formatted.length && countedDigits < digitsBeforeCursor) {
      if (_isDigit(formatted.codeUnitAt(cursor))) countedDigits++;
      cursor++;
    }
    while (cursor < formatted.length && formatted[cursor] == '.') {
      cursor++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
      composing: TextRange.empty,
    );
  }

  static bool _isDigit(int codeUnit) =>
      codeUnit >= 48 && codeUnit <= 57;
}

/// Removes display separators and returns the numeric Rupiah value.
int parseCurrencyInput(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

/// Adds Indonesian thousands separators to a digit string or integer.
String formatCurrencyInput(Object? value) {
  final digits = (value ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
