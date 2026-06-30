import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/audit/presentation/audit_cubit.dart';
import 'package:ownpay_console/features/audit/presentation/audit_screen.dart';
import 'package:ownpay_console/features/sync/domain/queued_sms.dart';

import 'audit_fakes.dart';

Widget _host(AuditCubit cubit) =>
    MaterialApp(home: BlocProvider<AuditCubit>.value(value: cubit, child: const AuditView()));

void main() {
  testWidgets('renders entries as metadata and never the encrypted payload', (WidgetTester tester) async {
    final FakeSmsQueueStore queue = FakeSmsQueueStore();
    queue.seed(sender: 'bKash', status: SyncStatus.approved, payload: 'SECRET_ENVELOPE');
    queue.seed(sender: 'Nagad', status: SyncStatus.failed, failureReason: 'timeout');
    final AuditCubit cubit = AuditCubit(queue, FakeSyncer(), FakeSmsBodyRevealer());
    await cubit.load();

    await tester.pumpWidget(_host(cubit));

    expect(find.text('bKash'), findsOneWidget);
    expect(find.text('Nagad'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.textContaining('timeout'), findsOneWidget);
    // The ciphertext envelope must never reach the UI.
    expect(find.textContaining('SECRET_ENVELOPE'), findsNothing);
  });

  testWidgets('Issues filter hides non-failed rows', (WidgetTester tester) async {
    final FakeSmsQueueStore queue = FakeSmsQueueStore();
    queue.seed(sender: 'bKash', status: SyncStatus.approved);
    queue.seed(sender: 'Nagad', status: SyncStatus.failed, failureReason: 'timeout');
    final AuditCubit cubit = AuditCubit(queue, FakeSyncer(), FakeSmsBodyRevealer());
    await cubit.load();
    await tester.pumpWidget(_host(cubit));

    await tester.tap(find.text('Issues'));
    await tester.pumpAndSettle();

    expect(find.text('Nagad'), findsOneWidget);
    expect(find.text('bKash'), findsNothing);
  });

  testWidgets('empty queue shows the empty state', (WidgetTester tester) async {
    final AuditCubit cubit = AuditCubit(FakeSmsQueueStore(), FakeSyncer(), FakeSmsBodyRevealer());
    await cubit.load();

    await tester.pumpWidget(_host(cubit));

    expect(find.textContaining('No activity yet'), findsOneWidget);
  });

  testWidgets('Clear failed removes failed rows after confirmation', (WidgetTester tester) async {
    final FakeSmsQueueStore queue = FakeSmsQueueStore();
    queue.seed(sender: 'Nagad', status: SyncStatus.failed, failureReason: 'timeout');
    final AuditCubit cubit = AuditCubit(queue, FakeSyncer(), FakeSmsBodyRevealer());
    await cubit.load();
    await tester.pumpWidget(_host(cubit));

    await tester.tap(find.text('Clear failed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear')); // confirm in the dialog
    await tester.pumpAndSettle();

    expect(find.text('Nagad'), findsNothing);
    expect(queue.rows, isEmpty);
  });

  testWidgets('Retry now triggers a sync', (WidgetTester tester) async {
    final FakeSmsQueueStore queue = FakeSmsQueueStore();
    queue.seed(status: SyncStatus.failed);
    final FakeSyncer sync = FakeSyncer();
    final AuditCubit cubit = AuditCubit(queue, sync, FakeSmsBodyRevealer());
    await cubit.load();
    await tester.pumpWidget(_host(cubit));

    await tester.tap(find.byTooltip('Retry now'));
    await tester.pumpAndSettle();

    expect(sync.syncCalls, 1);
  });
}
