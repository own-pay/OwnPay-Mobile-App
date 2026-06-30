import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/services/session_status.dart';
import '../features/audit/presentation/audit_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/pairing/presentation/pairing_screen.dart';
import '../features/permissions/presentation/disclosure_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import 'shell_scaffold.dart';

/// Builds the app router. [initialLocation] is resolved once at startup from paired/disclosure state
/// (see `main`); screens then drive navigation explicitly (pairing → `/disclosure`, disclosure → `/`).
/// A [session]-driven redirect forces `/pair` whenever the session needs re-authentication.
///
/// The three primary destinations (`/`, `/audit`, `/settings`) live inside a
/// [StatefulShellRoute.indexedStack] so they share the persistent bottom nav bar and keep per-tab state.
/// `/pair` and `/disclosure` are top-level (full-screen, no bar).
GoRouter buildRouter({required String initialLocation, required SessionStatus session}) {
  return GoRouter(
    initialLocation: initialLocation,
    // When the session can no longer authenticate, force the user to /pair (and re-evaluate on change).
    refreshListenable: session.reauthRequired,
    redirect: (BuildContext context, GoRouterState state) => session.redirect(state.matchedLocation),
    routes: <RouteBase>[
      GoRoute(
        path: '/pair',
        builder: (BuildContext context, GoRouterState state) => const PairingScreen(),
      ),
      GoRoute(
        path: '/disclosure',
        builder: (BuildContext context, GoRouterState state) => const DisclosureScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell navigationShell) =>
            ShellScaffold(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (BuildContext context, GoRouterState state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/audit',
                builder: (BuildContext context, GoRouterState state) => const AuditScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
