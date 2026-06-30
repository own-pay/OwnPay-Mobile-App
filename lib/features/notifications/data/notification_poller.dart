import 'dart:async';

import '../../../core/config/app_config.dart';
import '../domain/app_notification.dart';
import '../domain/notification_repository.dart';
import '../domain/notifier.dart';

/// Polls `GET /notifications` on an interval, raises a local notification for each not-yet-seen id, and
/// acknowledges them so the server stops re-sending. De-dupe is by in-memory seen-set (ack is the durable
/// signal). Hosting this inside the foreground service keeps it polling while backgrounded (device-side).
class NotificationPoller {
  NotificationPoller(
    this._repo,
    this._notifier, [
    this._interval = AppConfig.notificationPollInterval,
  ]);

  final NotificationRepository _repo;
  final Notifier _notifier;
  final Duration _interval;

  final Set<int> _seen = <int>{};
  Timer? _timer;
  bool _polling = false;

  /// One poll cycle: fetch pending → show any not-yet-seen → mark seen → acknowledge them. Serialized so
  /// overlapping ticks can't double-show the same notification.
  Future<void> poll() async {
    if (_polling) {
      return;
    }
    _polling = true;
    try {
      final List<AppNotification> pending = await _repo.fetch();
      if (pending.isEmpty) {
        return;
      }
      // Show only not-yet-seen notifications (dedupe). Then acknowledge EVERY still-pending id — not
      // just the freshly-shown ones. The server only returns un-acknowledged items, so re-acking the
      // already-shown ones is idempotent and self-heals an earlier ack that failed; otherwise a shown
      // item would stay un-acked on the server and re-appear as a duplicate after the next app restart.
      for (final AppNotification n in pending) {
        if (!_seen.contains(n.id)) {
          await _notifier.show(n);
          _seen.add(n.id);
        }
      }
      await _repo.acknowledge(pending.map((AppNotification n) => n.id).toList());
    } finally {
      _polling = false;
    }
  }

  /// Begins polling (an immediate poll, then every [_interval]). Idempotent.
  void start() {
    if (_timer != null) {
      return;
    }
    unawaited(poll());
    _timer = Timer.periodic(_interval, (Timer _) => unawaited(poll()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
