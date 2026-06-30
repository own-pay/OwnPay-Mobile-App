import 'package:equatable/equatable.dart';

/// An inbound SMS exactly as captured on-device, **before** the privacy gate runs.
///
/// A [RawSms] is transient: it is created from the platform capture stream, passed straight to the
/// privacy gate, and either dropped (never persisted) or converted into an encrypted queue item. Its
/// raw [body] must never be logged or persisted in clear text.
class RawSms extends Equatable {
  const RawSms({
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  /// Builds a [RawSms] from the native capture-channel payload `{sender, body, ts}`, where `ts` is
  /// epoch milliseconds. Tolerant of missing/mistyped fields (defaults to empty / epoch) so a
  /// malformed platform message degrades gracefully instead of throwing inside the capture pipeline.
  factory RawSms.fromChannel(Map<Object?, Object?> map) {
    final Object? sender = map['sender'];
    final Object? body = map['body'];
    final Object? ts = map['ts'];
    return RawSms(
      sender: sender is String ? sender : '',
      body: body is String ? body : '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : 0),
    );
  }

  /// Originating sender id / shortcode (e.g. `bKash`, `16247`).
  final String sender;

  /// Full message body. Sensitive — do not log.
  final String body;

  /// Timestamp the SMS was received on the device.
  final DateTime receivedAt;

  @override
  List<Object?> get props => [sender, body, receivedAt];

  /// Intentionally redacts [body] so the type is safe to log.
  @override
  String toString() => 'RawSms(sender: $sender, receivedAt: ${receivedAt.toIso8601String()}, body: <redacted>)';
}
