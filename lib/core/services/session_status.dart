import 'package:flutter/foundation.dart';

/// App-wide auth/session signal. The sync worker flips [reauthRequired] when the device can no longer
/// authenticate (a 401 the interceptor could not refresh); the router watches it and redirects to
/// `/pair` so the user isn't stranded on a dead session. A successful (re-)pair clears it.
class SessionStatus {
  final ValueNotifier<bool> reauthRequired = ValueNotifier<bool>(false);

  void requireReauth() => reauthRequired.value = true;

  void clear() => reauthRequired.value = false;

  /// Pure redirect rule for go_router: force `/pair` while re-auth is pending (without looping once
  /// already there). Returns null to allow the requested [location].
  String? redirect(String location) {
    if (reauthRequired.value && location != '/pair') {
      return '/pair';
    }
    return null;
  }
}
