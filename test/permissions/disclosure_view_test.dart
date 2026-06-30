import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/permissions/domain/sms_permission.dart';
import 'package:ownpay_console/features/permissions/presentation/disclosure_cubit.dart';
import 'package:ownpay_console/features/permissions/presentation/disclosure_screen.dart';

import 'permission_fakes.dart';

Widget _host(DisclosureCubit cubit) {
  return MaterialApp(
    home: BlocProvider<DisclosureCubit>.value(value: cubit, child: const DisclosureView()),
  );
}

void main() {
  testWidgets('shows the prominent disclosure points and both choices', (WidgetTester tester) async {
    final DisclosureCubit cubit =
        DisclosureCubit(FakePermissionGate(requestResult: SmsPermission.granted), FakeConsentStore(), FakeSmsCapture());

    await tester.pumpWidget(_host(cubit));

    // The four mandated disclosure facets (DESIGN §4.2), per the mockup copy.
    expect(find.text('WHAT IS ACCESSED'), findsOneWidget);
    expect(find.text('WHY IT IS NEEDED'), findsOneWidget);
    expect(find.text('WHERE YOUR DATA GOES'), findsOneWidget);
    expect(find.text('WHAT IS IGNORED'), findsOneWidget);
    expect(find.textContaining('OTPs'), findsOneWidget);

    // Affirmative + decline actions.
    expect(find.text('Allow SMS Access'), findsOneWidget);
    expect(find.text('Not Now (Manual Mode)'), findsOneWidget);
  });

  testWidgets('Allow → denied surfaces a retry notice and stays on screen', (WidgetTester tester) async {
    final DisclosureCubit cubit =
        DisclosureCubit(FakePermissionGate(requestResult: SmsPermission.denied), FakeConsentStore(), FakeSmsCapture());

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Allow SMS Access'));
    await tester.pumpAndSettle();

    expect(find.textContaining('was not granted'), findsOneWidget);
    // Still on the disclosure screen (no navigation away on denial).
    expect(find.text('Allow SMS Access'), findsOneWidget);
  });

  testWidgets('permanently denied shows Open settings', (WidgetTester tester) async {
    final DisclosureCubit cubit = DisclosureCubit(
      FakePermissionGate(requestResult: SmsPermission.permanentlyDenied),
      FakeConsentStore(),
      FakeSmsCapture(),
    );

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Allow SMS Access'));
    await tester.pumpAndSettle();

    expect(find.text('Open settings'), findsOneWidget);
    expect(find.textContaining('blocked in system settings'), findsOneWidget);
  });
}
