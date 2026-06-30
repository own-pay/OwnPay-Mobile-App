import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/config/app_config.dart';
import '../../../core/storage/local_wipe.dart';
import '../../../core/storage/secure_store.dart';
import '../../../shared/theme/app_theme.dart';
import '../../pairing/data/device_repository.dart';
import '../../privacy_gate/data/sender_overrides.dart';
import '../../privacy_gate/domain/filter_rules_repository.dart';
import 'settings_cubit.dart';

/// Device settings: connection info, the SMS-source whitelist (toggle each source on/off on this device,
/// plus "sync from admin panel"), re-pair, and the destructive "revoke & wipe".
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SettingsCubit>(
      create: (_) => SettingsCubit(
        sl<SecureStore>(),
        sl<DeviceRepository>(),
        sl<LocalWipe>(),
        sl<FilterRulesRepository>(),
        sl<SenderOverrides>(),
      )..load(),
      child: const SettingsView(),
    );
  }
}

/// Split from [SettingsScreen] so widget tests can pump it with an injected cubit.
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SettingsCubit, SettingsState>(
      listener: (BuildContext context, SettingsState state) {
        if (state.status == SettingsStatus.wiped) {
          context.go('/pair'); // wiped → unpaired → back to pairing
        }
      },
      builder: (BuildContext context, SettingsState state) {
        final SettingsCubit cubit = context.read<SettingsCubit>();
        final bool wiping = state.status == SettingsStatus.wiping;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text('THIS DEVICE', style: AppTheme.overline.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 10),
                _InfoCard(
                  children: <Widget>[
                    _InfoTile(label: 'Server', value: state.serverUrl ?? '—'),
                    _InfoTile(label: 'Device ID', value: state.deviceUuid ?? '—'),
                    const _InfoTile(label: 'App version', value: AppConfig.appVersion),
                  ],
                ),
                const SizedBox(height: 24),
                _SmsSourcesSection(state: state, cubit: cubit),
                const SizedBox(height: 24),
                Text('CONNECTION', style: AppTheme.overline.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: wiping ? null : () => context.push('/pair'),
                  icon: const Icon(Icons.link),
                  label: const Text('Re-pair device'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: wiping ? null : () => _confirmWipe(context, cubit),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: Colors.white,
                  ),
                  icon: wiping
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_forever_outlined),
                  label: const Text('Revoke & wipe this device'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Removes this device from your server and erases all local data (tokens, encryption key, '
                  'and the offline queue). You will need to pair again.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmWipe(BuildContext context, SettingsCubit cubit) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Revoke & wipe?'),
        content: const Text(
          'This removes the device from your OwnPay server and erases all local data on this phone. '
          'This cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    // Only `cubit` (captured before the await) is used afterwards — no BuildContext across the gap.
    if (confirmed ?? false) {
      await cubit.revokeAndWipe();
    }
  }
}

/// The SMS-source whitelist: each server-whitelisted sender with an on/off switch (off = disabled on
/// this device), plus a "sync from admin panel" force-refresh.
class _SmsSourcesSection extends StatelessWidget {
  const _SmsSourcesSection({required this.state, required this.cubit});

  final SettingsState state;
  final SettingsCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text('SMS SOURCES', style: AppTheme.overline.copyWith(color: AppColors.textMuted)),
            ),
            if (state.syncing)
              const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton.icon(
                onPressed: cubit.syncFromAdmin,
                icon: const Icon(Icons.cloud_sync_outlined, size: 18, color: AppColors.brand),
                label: const Text('Sync from admin', style: TextStyle(color: AppColors.brand)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.senders.isEmpty)
          _InfoCard(
            children: <Widget>[
              Text(
                state.rulesLoaded
                    ? 'No SMS sources configured yet. Add senders in your OwnPay admin panel, then tap '
                        '"Sync from admin".'
                    : 'Loading sources…',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          )
        else
          _InfoCard(
            children: <Widget>[
              for (int i = 0; i < state.senders.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1),
                _SenderTile(
                  sender: state.senders[i],
                  enabled: state.isEnabled(state.senders[i]),
                  onChanged: (bool value) => cubit.toggleSender(state.senders[i], value),
                ),
              ],
            ],
          ),
        const SizedBox(height: 8),
        const Text(
          'Disabling a source stops this device from forwarding its SMS. You can only narrow the list set '
          'by your server — never add senders here.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _SenderTile extends StatelessWidget {
  const _SenderTile({required this.sender, required this.enabled, required this.onChanged});

  final String sender;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.outline),
            ),
            child: Icon(
              Icons.sms_outlined,
              size: 18,
              color: enabled ? AppColors.brand : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  sender,
                  style: const TextStyle(color: AppColors.textHi, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  enabled ? 'Active' : 'Disabled on this device',
                  style: TextStyle(
                    color: enabled ? AppColors.success : AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// A bordered dark card grouping rows.
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.textHi, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
