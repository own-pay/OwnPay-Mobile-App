import 'package:flutter_test/flutter_test.dart';
import 'package:ownpay_console/core/services/session_status.dart';

void main() {
  test('redirect → /pair only when reauth is required and not already there', () {
    final SessionStatus s = SessionStatus();

    expect(s.reauthRequired.value, isFalse);
    expect(s.redirect('/'), isNull);

    s.requireReauth();
    expect(s.reauthRequired.value, isTrue);
    expect(s.redirect('/'), '/pair');
    expect(s.redirect('/audit'), '/pair');
    expect(s.redirect('/pair'), isNull); // already there — no redirect loop

    s.clear();
    expect(s.reauthRequired.value, isFalse);
    expect(s.redirect('/'), isNull);
  });

  test('reauthRequired notifies listeners on each change', () {
    final SessionStatus s = SessionStatus();
    int notifications = 0;
    s.reauthRequired.addListener(() => notifications++);

    s.requireReauth();
    s.clear();

    expect(notifications, 2);
  });
}
