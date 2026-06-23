import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('Home shows the OwnPay Console unpaired state', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.text('OwnPay Console'), findsOneWidget);
    expect(find.text('Not paired'), findsOneWidget);
  });
}
