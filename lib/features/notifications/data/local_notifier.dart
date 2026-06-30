import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../domain/app_notification.dart';
import '../domain/notifier.dart';

/// [Notifier] backed by `flutter_local_notifications`, posting to a single "Payments" channel. The
/// channel is created lazily on first use. The actual on-device display is verified on hardware.
class LocalNotifier implements Notifier {
  LocalNotifier() : _plugin = FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static const String _channelId = 'ownpay_payments';
  static const String _channelName = 'Payment notifications';

  Future<void> _ensureInit() async {
    if (_initialized) {
      return;
    }
    // Monochrome status-bar icon (white silhouette on transparent): Android tints notification small
    // icons, so the full-color launcher icon would render as a white blob. ic_stat_notify is the brand
    // ring drawn for that constraint (res/drawable-*/ic_stat_notify.png).
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@drawable/ic_stat_notify');
    await _plugin.initialize(settings: const InitializationSettings(android: android));
    _initialized = true;
  }

  @override
  Future<void> show(AppNotification notification) async {
    await _ensureInit();
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Payment confirmations and alerts from your OwnPay server',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      id: notification.id,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}
