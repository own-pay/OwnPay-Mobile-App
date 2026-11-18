import '../../../shared/models/raw_sms.dart';

/// Contract for the native SMS capture layer.
///
/// On Android this is backed by a foreground service + a manifest SMS receiver + a durable,
/// encrypted on-disk buffer (see `android/app/src/main/kotlin/org/ownpay/console/SmsBridge.kt` and
/// `SmsBufferCrypto.kt`). The privacy gate, encryption, and queueing that CONSUME captured messages
/// live in Dart and are layered on top of [peekPending] / [ackProcessed] / [onPending].
abstract interface class SmsCapture {
  /// Enables monitoring: persists the preference and starts the foreground service.
  Future<void> startMonitoring();

  /// Disables monitoring: stops the foreground service. The capture buffer is left intact.
  Future<void> stopMonitoring();

  /// Whether monitoring is currently enabled.
  Future<bool> isMonitoring();

  /// Reads the native buffer of captured messages **without** clearing it (durable across process
  /// death). The consumer must call [ackProcessed] once it has durably handled the leading messages,
  /// so a crash or write failure mid-processing never loses an un-persisted message.
  Future<List<RawSms>> peekPending();

  /// Removes the first [count] messages from the native buffer — the ones the consumer has durably
  /// handled (gate-dropped, or encrypted + enqueued). Anything beyond [count] stays buffered for the
  /// next drain. A [count] of 0 is a no-op.
  Future<void> ackProcessed(int count);

  /// Lifetime count of capture-time SMS the native buffer had to evict unread (buffer full).
  /// 0 unless drops occurred.
  Future<int> getDroppedOverflowCount();

  /// Lifetime count of capture-time SMS the native layer dropped at the door because the sender was
  /// not in the server-provided whitelist (never persisted).
  Future<int> getDroppedFilteredCount();

  /// Mirrors the server-configured sender whitelist into the native layer so the broadcast receiver
  /// can drop non-matching SMS before they ever touch the buffer. [senders] is the exact
  /// [FilterRules.allowedSenders] list from the privacy gate.
  Future<void> setAllowedSenders(List<String> senders);

  /// Emits whenever new messages have been buffered natively — a nudge to call [peekPending].
  Stream<void> get onPending;
}
