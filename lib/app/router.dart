import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/pairing/presentation/pairing_screen.dart';
import '../features/permissions/presentation/disclosure_screen.dart';

/// Builds the app router. [initialLocation] is resolved once at startup from paired/disclosure state
/// (see `main`); screens then drive navigation explicitly (pairing → `/disclosure`, disclosure → `/`).
GoRouter buildRouter({required String initialLocation}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/pair',
        builder: (BuildContext context, GoRouterState state) => const PairingScreen(),
      ),
      GoRoute(
        path: '/disclosure',
        builder: (BuildContext context, GoRouterState state) => const DisclosureScreen(),
      ),
    ],
  );
}
