import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/services/app_refresh_signal.dart';
import '../features/sync/domain/syncer.dart';
import '../shared/theme/app_theme.dart';
import 'di.dart';

/// The persistent app shell: the three primary destinations (Home, Activity, Settings) live in a
/// [StatefulNavigationShell] (state preserved per tab) under one bottom nav bar. **Refresh** is a
/// fourth bar item that is an ACTION — it re-fetches the current screen's data and kicks a sync — not a
/// navigation target (see [AppRefreshSignal]). Pairing and the disclosure screen stay OUTSIDE this shell
/// (full-screen, no bar).
class ShellScaffold extends StatelessWidget {
  const ShellScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  Future<void> _refresh(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    sl<AppRefreshSignal>().requestRefresh(); // reload the visible screen's data
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Refreshing…'), duration: Duration(milliseconds: 900)));
    await sl<Syncer>().syncNow(); // push any queued SMS while we're at it
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: _ConsoleNavBar(
        currentIndex: navigationShell.currentIndex,
        onSelectBranch: (int branch) => navigationShell.goBranch(
          branch,
          // Re-tapping the active tab returns it to its initial route (standard bottom-nav behavior).
          initialLocation: branch == navigationShell.currentIndex,
        ),
        onRefresh: () => _refresh(context),
      ),
    );
  }
}

/// One bottom-bar entry. A [branchIndex] of `null` marks the Refresh action (never shown "active").
class _NavItemSpec {
  const _NavItemSpec(this.icon, this.label, this.branchIndex);

  final IconData icon;
  final String label;
  final int? branchIndex;
}

/// Custom bottom bar matching the console mockup: four evenly-spaced icon+label items, the active
/// destination tinted brand-teal. Ordered Home · Activity · Refresh · Settings.
class _ConsoleNavBar extends StatelessWidget {
  const _ConsoleNavBar({
    required this.currentIndex,
    required this.onSelectBranch,
    required this.onRefresh,
  });

  final int currentIndex;
  final ValueChanged<int> onSelectBranch;
  final Future<void> Function() onRefresh;

  static const List<_NavItemSpec> _items = <_NavItemSpec>[
    _NavItemSpec(Icons.home_rounded, 'Home', 0),
    _NavItemSpec(Icons.receipt_long_rounded, 'Activity', 1),
    _NavItemSpec(Icons.sync_rounded, 'Refresh', null),
    _NavItemSpec(Icons.settings_rounded, 'Settings', 2),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: _items.map((_NavItemSpec item) {
              final bool active = item.branchIndex != null && item.branchIndex == currentIndex;
              return Expanded(
                child: _NavButton(
                  icon: item.icon,
                  label: item.label,
                  active: active,
                  onTap: () {
                    final int? branch = item.branchIndex;
                    if (branch == null) {
                      onRefresh();
                    } else {
                      onSelectBranch(branch);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.brand : AppColors.textMuted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
