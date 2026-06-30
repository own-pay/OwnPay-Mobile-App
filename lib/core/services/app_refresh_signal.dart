import 'package:flutter/foundation.dart';

/// App-wide "refresh now" signal fired by the bottom-nav **Refresh** action.
///
/// Refresh is an action, not a destination: tapping it must re-fetch the data on whatever screen is
/// visible (dashboard, activity) rather than navigate anywhere — the earlier bug was Refresh routing to
/// `/pair`. Screens that show server-backed data listen to [tick] and reload when it changes; this keeps
/// the nav bar decoupled from each screen's cubit.
class AppRefreshSignal {
  final ValueNotifier<int> tick = ValueNotifier<int>(0);

  /// Bumps the counter so every listening screen reloads once.
  void requestRefresh() => tick.value = tick.value + 1;
}
