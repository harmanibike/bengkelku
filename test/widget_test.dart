
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bengkelku_pos/main.dart';

void main() {
  testWidgets('BengkelKu POS dapat dibuka', (WidgetTester tester) async {
    await tester.pumpWidget(const BengkelKuApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
