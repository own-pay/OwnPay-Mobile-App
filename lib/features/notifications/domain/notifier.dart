import 'app_notification.dart';

/// Raises a native local notification. The data-layer `LocalNotifier` uses `flutter_local_notifications`;
/// tests substitute a fake so the poll/de-dupe logic is verifiable without a device.
abstract interface class Notifier {
  Future<void> show(AppNotification notification);
}
