import 'package:flutter/services.dart';

import '../../../shared/models/raw_sms.dart';
import '../domain/sms_capture.dart';

/// [SmsCapture] backed by the native Android channels registered in `SmsBridge.kt`.
///
/// Channel names are shared verbatim with the Kotlin side; keep them in sync.
class PlatformSmsCapture implements SmsCapture {
  const PlatformSmsCapture();

  static const MethodChannel _method = MethodChannel('org.ownpay.console/sms');
  static const EventChannel _events = EventChannel('org.ownpay.console/sms_events');

  @override
  Future<void> startMonitoring() async {
    await _method.invokeMethod<void>('startMonitoring');
  }

  @override
  Future<void> stopMonitoring() async {
    await _method.invokeMethod<void>('stopMonitoring');
  }

  @override
  Future<bool> isMonitoring() async => await _method.invokeMethod<bool>('isMonitoring') ?? false;

  @override
  Future<List<RawSms>> peekPending() async {
    final List<Object?>? raw = await _method.invokeListMethod<Object?>('peekPending');
    if (raw == null) {
      return const <RawSms>[];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(RawSms.fromChannel)
        .toList(growable: false);
  }

  @override
  Future<void> ackProcessed(int count) async {
    if (count <= 0) {
      return;
    }
    await _method.invokeMethod<void>('ackProcessed', <String, dynamic>{'count': count});
  }

  @override
  Stream<void> get onPending => _events.receiveBroadcastStream().map<void>((Object? _) {});
}
