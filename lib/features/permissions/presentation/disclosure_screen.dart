import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../shared/theme/app_theme.dart';
import '../../sms_capture/domain/sms_capture.dart';
import '../data/consent_store.dart';
import '../domain/sms_permission.dart';
import 'disclosure_cubit.dart';

/// Compliance-critical prominent disclosure (DESIGN §4.2 / docs/PLAY_STORE.md), styled to mockup #3:
/// shown in-app, **before** the OS SMS permission dialog. States what is accessed, why, where it goes,
/// and what is ignored, then requires an affirmative choice. "Not now" leaves capture off (manual mode)
/// but still proceeds to home.
class DisclosureScreen extends StatelessWidget {
  const DisclosureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DisclosureCubit>(
      create: (_) => DisclosureCubit(sl<PermissionGate>(), sl<ConsentStore>(), sl<SmsCapture>()),
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
                        const Row(
                          children: <Widget>[
                            Icon(Icons.shield_outlined, size: 20, color: AppColors.brand),
                            SizedBox(width: 8),
                            Text('PERMISSION DISCLOSURE', style: AppTheme.overline),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Your Privacy, Under Your Control',
                          style: TextStyle(
                            color: AppColors.textHi,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const _Section(
                          color: AppColors.brand,
                          title: 'WHAT IS ACCESSED',
                          // Keeps the legacy "What is read" facet wording discoverable for accessibility.
                          body: 'Only SMS messages received from whitelisted mobile banking gateways '
                              '(e.g., bKash, Nagad, Rocket).',
                        ),
                        const _Section(
                          color: AppColors.brand,
                          title: 'WHY IT IS NEEDED',
                          body: 'To instantly read transaction IDs and confirm customer payments '
                              'automatically without manual entry.',
                        ),
                        const _Section(
                          color: AppColors.success,
                          title: 'WHERE YOUR DATA GOES',
                          body: 'Directly and securely to your paired OwnPay server. We never sell, '
                              'share, or store your personal texts.',
                        ),
                        const _Section(
                          color: AppColors.textMuted,
                          title: 'WHAT IS IGNORED',
                          body: 'Personal chats, OTPs, recovery codes, and sensitive bank statements '
                              'never leave your device.',
                        ),
                      ],
                    ),
                  ),
                  // Denial notices live OUTSIDE the scroll view so they stay visible next to the
                  // action buttons rather than being buried below the fold of the disclosure list.
                  if (state.phase == DisclosurePhase.denied)
                    const _Notice(
                      color: AppColors.danger,
                      text: 'SMS access was not granted. You can allow it now, or continue without '
                          'automatic capture.',
                    ),
                  if (state.phase == DisclosurePhase.permanentlyDenied)
                    const _Notice(
                      color: AppColors.danger,
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand),
                            )
                          : const Text('Allow SMS Access'),
                    ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: busy ? null : cubit.declineForNow,
                    child: const Text('Not Now (Manual Mode)'),
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

/// One disclosure section: a colored dot + uppercase heading, then the explanatory body.
class _Section extends StatelessWidget {
  const _Section({required this.color, required this.title, required this.body});

  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                height: 7,
                width: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(color: AppColors.textHi, fontSize: 14, height: 1.45),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 13)),
    );
  }
}
