import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/notifications/data/notification_poller.dart';
import 'package:ownpay_console/features/notifications/domain/app_notification.dart';
import 'package:ownpay_console/features/notifications/domain/notification_repository.dart';
import 'package:ownpay_console/features/notifications/domain/notifier.dart';

class _FakeRepo implements NotificationRepository {
  _FakeRepo(this._batches);

  final List<List<AppNotification>> _batches;
  final List<List<int>> acked = <List<int>>[];

  @override
  Future<List<AppNotification>> fetch() async =>
      _batches.isEmpty ? const <AppNotification>[] : _batches.removeAt(0);

  @override
  Future<void> acknowledge(List<int> ids) async => acked.add(ids);
}

class _FakeNotifier implements Notifier {
  final List<AppNotification> shown = <AppNotification>[];

  @override
  Future<void> show(AppNotification notification) async => shown.add(notification);
}

AppNotification notif(int id) =>
    AppNotification(id: id, type: 'payment', title: 'T$id', body: 'B', createdAt: DateTime(2026, 6, 24));

void main() {
  test('poll shows new notifications and acknowledges them', () async {
    final _FakeRepo repo = _FakeRepo(<List<AppNotification>>[
      <AppNotification>[notif(1), notif(2)],
    ]);
    final _FakeNotifier notifier = _FakeNotifier();

    await NotificationPoller(repo, notifier).poll();

    expect(notifier.shown.map((AppNotification n) => n.id), <int>[1, 2]);
    expect(repo.acked, <List<int>>[<int>[1, 2]]);
  });

  test('poll shows each id once but re-acks every still-pending id each cycle', () async {
    final _FakeRepo repo = _FakeRepo(<List<AppNotification>>[
      <AppNotification>[notif(1)],
      <AppNotification>[notif(1), notif(2)],
    ]);
    final _FakeNotifier notifier = _FakeNotifier();
    final NotificationPoller poller = NotificationPoller(repo, notifier);

    await poller.poll();
    await poller.poll();

    expect(notifier.shown.map((AppNotification n) => n.id), <int>[1, 2]); // each shown once
    // Cycle 2 still lists id 1 (its earlier ack didn't take), so it is re-acked alongside the new id 2.
    expect(repo.acked, <List<int>>[<int>[1], <int>[1, 2]]);
  });

  test('re-acks a still-pending shown item without re-showing it (heals a dropped ack)', () async {
    final _FakeRepo repo = _FakeRepo(<List<AppNotification>>[
      <AppNotification>[notif(1)],
      <AppNotification>[notif(1)], // server still lists id 1 → the earlier ack never landed
    ]);
    final _FakeNotifier notifier = _FakeNotifier();
    final NotificationPoller poller = NotificationPoller(repo, notifier);

    await poller.poll();
    await poller.poll();

    expect(notifier.shown.map((AppNotification n) => n.id), <int>[1]); // shown once, no duplicate
    expect(repo.acked, <List<int>>[<int>[1], <int>[1]]); // acked again to finally clear it
  });

  test('empty fetch shows and acks nothing', () async {
    final _FakeRepo repo = _FakeRepo(<List<AppNotification>>[]);
    final _FakeNotifier notifier = _FakeNotifier();

    await NotificationPoller(repo, notifier).poll();

    expect(notifier.shown, isEmpty);
    expect(repo.acked, isEmpty);
  });

  test('start triggers an immediate poll', () async {
    final _FakeRepo repo = _FakeRepo(<List<AppNotification>>[
      <AppNotification>[notif(1)],
    ]);
    final _FakeNotifier notifier = _FakeNotifier();
    final NotificationPoller poller = NotificationPoller(repo, notifier);

    poller.start();
    await pumpEventQueue();
    poller.stop();

    expect(notifier.shown.map((AppNotification n) => n.id), <int>[1]);
  });
}
