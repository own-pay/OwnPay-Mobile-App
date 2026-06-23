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
        DisclosureCubit(FakePermissionGate(requestResult: SmsPermission.granted), FakeConsentStore());

    await tester.pumpWidget(_host(cubit));

    // The four mandated disclosure facets (DESIGN §4.2).
    expect(find.text('What is read'), findsOneWidget);
    expect(find.text('Why'), findsOneWidget);
    expect(find.text('Where it goes'), findsOneWidget);
    expect(find.text('What is ignored'), findsOneWidget);
    expect(find.textContaining('OTPs'), findsOneWidget);

    // Affirmative + decline actions.
    expect(find.text('Allow SMS access'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('Allow → denied surfaces a retry notice and stays on screen', (WidgetTester tester) async {
    final DisclosureCubit cubit =
        DisclosureCubit(FakePermissionGate(requestResult: SmsPermission.denied), FakeConsentStore());

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Allow SMS access'));
    await tester.pumpAndSettle();

    expect(find.textContaining('was not granted'), findsOneWidget);
    // Still on the disclosure screen (no navigation away on denial).
    expect(find.text('Allow SMS access'), findsOneWidget);
  });

  testWidgets('permanently denied shows Open settings', (WidgetTester tester) async {
    final DisclosureCubit cubit = DisclosureCubit(
      FakePermissionGate(requestResult: SmsPermission.permanentlyDenied),
      FakeConsentStore(),
    );

    await tester.pumpWidget(_host(cubit));
    await tester.tap(find.text('Allow SMS access'));
    await tester.pumpAndSettle();

    expect(find.text('Open settings'), findsOneWidget);
    expect(find.textContaining('blocked in system settings'), findsOneWidget);
  });
}
