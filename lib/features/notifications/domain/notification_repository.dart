import 'app_notification.dart';

/// Source of device notifications: fetches pending ones and acknowledges the handled ids.
abstract interface class NotificationRepository {
  /// Pending notifications for this device (empty on error / when unpaired — never throws).
  Future<List<AppNotification>> fetch();

  /// Tells the server these ids were handled so it stops returning them.
  Future<void> acknowledge(List<int> ids);
}
