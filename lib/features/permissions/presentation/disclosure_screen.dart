import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../data/consent_store.dart';
import '../domain/sms_permission.dart';
import 'disclosure_cubit.dart';

/// Compliance-critical prominent disclosure (DESIGN §4.2 / docs/PLAY_STORE.md): shown in-app,
/// **before** the OS SMS permission dialog. States what is read, why, where it goes, and what is
/// ignored, then requires an affirmative choice. "Not now" leaves capture off (manual mode) but
/// still proceeds to home.
class DisclosureScreen extends StatelessWidget {
  const DisclosureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DisclosureCubit>(
      create: (_) => DisclosureCubit(sl<PermissionGate>(), sl<ConsentStore>()),
      child: const DisclosureView(),
    );
  }
}

/// Split from [DisclosureScreen] so widget tests can pump it with an injected cubit.
class DisclosureView extends StatelessWidget {
  const DisclosureView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DisclosureCubit, DisclosureState>(
      listener: (BuildContext context, DisclosureState state) {
        if (state.isResolved) {
          context.go('/');
        }
      },
      builder: (BuildContext context, DisclosureState state) {
        final ThemeData theme = Theme.of(context);
        final ColorScheme scheme = theme.colorScheme;
        final bool busy = state.phase == DisclosurePhase.requesting;
        final DisclosureCubit cubit = context.read<DisclosureCubit>();

        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        Icon(Icons.sms_outlined, size: 48, color: scheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Allow OwnPay Console to read payment SMS',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'To confirm your payments automatically, this app reads incoming SMS on '
                          'this device. Here is exactly how that works:',
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        _Point(
                          icon: Icons.account_balance_outlined,
                          color: scheme.primary,
                          title: 'What is read',
                          body: 'Only SMS from whitelisted bank/wallet senders (e.g. bKash, Nagad, '
                              'your bank).',
                        ),
                        _Point(
                          icon: Icons.verified_outlined,
                          color: scheme.primary,
                          title: 'Why',
                          body: 'To automatically match and confirm the payments you receive.',
                        ),
                        _Point(
                          icon: Icons.lock_outline,
                          color: scheme.primary,
                          title: 'Where it goes',
                          body: 'Encrypted and sent only to your own OwnPay server — never to us or '
                              'any third party.',
                        ),
                        _Point(
                          icon: Icons.shield_outlined,
                          color: scheme.tertiary,
                          title: 'What is ignored',
                          body: 'OTPs, PINs, verification codes, and personal messages stay on this '
                              'phone.',
                        ),
                      ],
                    ),
                  ),
                  // Denial notices live OUTSIDE the scroll view so they stay visible next to the
                  // action buttons rather than being buried below the fold of the disclosure list.
                  if (state.phase == DisclosurePhase.denied)
                    _Notice(
                      color: scheme.error,
                      text: 'SMS access was not granted. You can allow it now, or continue without '
                          'automatic capture.',
                    ),
                  if (state.phase == DisclosurePhase.permanentlyDenied)
                    _Notice(
                      color: scheme.error,
                      text: 'SMS access is blocked in system settings. Open Settings to enable it, '
                          'or continue without automatic capture.',
                    ),
                  const SizedBox(height: 12),
                  if (state.phase == DisclosurePhase.permanentlyDenied)
                    OutlinedButton.icon(
                      onPressed: busy ? null : cubit.openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open settings'),
                    )
                  else
                    FilledButton(
                      onPressed: busy ? null : cubit.allow,
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Allow SMS access'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : cubit.declineForNow,
                    child: const Text('Not now'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One disclosure bullet: leading icon + bold title + explanatory body.
class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline status banner shown after a denial.
class _Notice extends StatelessWidget {
  const _Notice({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
    );
  }
}
