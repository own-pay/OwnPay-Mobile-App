import '../../../shared/models/raw_sms.dart';

/// Contract for the native SMS capture layer.
///
/// On Android this is backed by a foreground service + a manifest SMS receiver + a durable on-disk
/// buffer (see `android/app/src/main/kotlin/org/ownpay/console/SmsBridge.kt`). The privacy gate,
/// encryption, and queueing that CONSUME captured messages live in Dart and are layered on top of
/// [peekPending] / [ackProcessed] / [onPending].
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

  /// Emits whenever new messages have been buffered natively — a nudge to call [peekPending].
  Stream<void> get onPending;
}
