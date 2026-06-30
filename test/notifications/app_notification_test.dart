import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/features/notifications/domain/app_notification.dart';

void main() {
  test('fromApi parses the notification fields', () {
    final AppNotification n = AppNotification.fromApi(<String, dynamic>{
      'id': 42,
      'type': 'payment',
      'title': 'Payment received',
      'body': 'Tk 1,500 from bKash',
      'created_at': '2026-06-24T10:00:00Z',
    });

    expect(n.id, 42);
    expect(n.type, 'payment');
    expect(n.title, 'Payment received');
    expect(n.body, 'Tk 1,500 from bKash');
    expect(n.createdAt, DateTime.utc(2026, 6, 24, 10));
  });

  test('fromApi tolerates a string id and missing fields', () {
    final AppNotification n = AppNotification.fromApi(<String, dynamic>{'id': '7'});

    expect(n.id, 7);
    expect(n.title, '');
    expect(n.body, '');
  });
}
