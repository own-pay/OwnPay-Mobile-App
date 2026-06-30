import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di.dart';
import '../../../core/services/app_refresh_signal.dart';
import '../../../shared/theme/app_theme.dart';
import '../../sync/domain/queued_sms.dart';
import '../../sync/domain/sms_queue_store.dart';
import '../../sync/domain/syncer.dart';
import '../data/sms_body_revealer.dart';
import '../domain/audit_entry.dart';
import 'audit_cubit.dart';

/// On-device audit trail: the offline queue rendered as metadata rows (sender · time · status). The
/// encrypted payload is never shown in the list; tapping a row decrypts the body on demand for the
/// owner (SECURITY.md §7/§9 — owner-only, in-memory, never persisted/logged). Filterable
/// (All | Synced | Issues), with "retry now" and a confirmed "clear failed".
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuditCubit>(
      create: (_) => AuditCubit(sl<SmsQueueStore>(), sl<Syncer>(), sl<SmsBodyRevealer>())..load(),
      child: AuditView(refresh: sl<AppRefreshSignal>()),
    );
  }
}

/// Split from [AuditScreen] so widget tests can pump it with an injected cubit. Reloads when the
/// bottom-nav Refresh action fires ([refresh] is supplied by the screen; null in tests → no subscription).
class AuditView extends StatefulWidget {
  const AuditView({this.refresh, super.key});

  final AppRefreshSignal? refresh;

  @override
  State<AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends State<AuditView> {
  @override
  void initState() {
    super.initState();
    widget.refresh?.tick.addListener(_onRefresh);
  }

  @override
  void dispose() {
    widget.refresh?.tick.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) {
      context.read<AuditCubit>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuditCubit, AuditState>(
      builder: (BuildContext context, AuditState state) {
        final AuditCubit cubit = context.read<AuditCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Activity'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Retry now',
                onPressed: cubit.retryNow,
                icon: const Icon(Icons.sync),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SegmentedButton<AuditFilter>(
                    segments: const <ButtonSegment<AuditFilter>>[
                      ButtonSegment<AuditFilter>(value: AuditFilter.all, label: Text('All')),
                      ButtonSegment<AuditFilter>(value: AuditFilter.synced, label: Text('Synced')),
                      ButtonSegment<AuditFilter>(value: AuditFilter.issues, label: Text('Issues')),
                    ],
                    selected: <AuditFilter>{state.filter},
                    onSelectionChanged: (Set<AuditFilter> selection) => cubit.setFilter(selection.first),
                  ),
                ),
                if (state.failedCount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${state.failedCount} failed to sync',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _confirmClear(context, cubit),
                          icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.danger),
                          label: const Text('Clear failed', style: TextStyle(color: AppColors.danger)),
                        ),
                      ],
                    ),
                  ),
                Expanded(child: _body(context, state)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, AuditState state) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final List<AuditEntry> visible = state.visible;
    if (visible.isEmpty) {
      return _EmptyState(filter: state.filter);
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: visible.length,
      separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) => _AuditTile(
        entry: visible[index],
        onTap: () => _revealBody(context, visible[index]),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AuditCubit cubit) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Clear failed?'),
        content: const Text('Remove all failed entries from the queue. They will no longer be retried.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    // Only `cubit` (captured before the await) is used afterwards — no BuildContext across the async gap.
    if (confirmed ?? false) {
      await cubit.clearFailed();
    }
  }

  /// Opens the owner-only detail sheet, decrypting the body on demand. The plaintext lives only inside
  /// this sheet's widget tree (in memory) and is gone when it closes.
  Future<void> _revealBody(BuildContext context, AuditEntry entry) async {
    final AuditCubit cubit = context.read<AuditCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) => _BodySheet(entry: entry, body: cubit.revealBody(entry.localId)),
    );
  }
}

/// One audit row: sender + time + status, plus failure/retry or server-ref metadata. Never the payload.
/// Tapping reveals the decrypted body.
class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry, required this.onTap});

  final AuditEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    final _StatusStyle s = _styleFor(entry.status);

    final List<String> details = <String>[
      '${l10n.formatMediumDate(entry.receivedAt)}, '
          '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(entry.receivedAt))}',
      if (entry.isIssue && (entry.failureReason?.isNotEmpty ?? false)) entry.failureReason!,
      if (entry.isIssue && entry.retryCount > 0) 'retry ${entry.retryCount}',
      if (entry.isSynced && entry.serverRef != null) 'ref ${entry.serverRef}',
    ];

    return ListTile(
      onTap: onTap,
      leading: Icon(s.icon, color: s.color),
      title: Text(entry.sender, style: const TextStyle(color: AppColors.textHi, fontWeight: FontWeight.w600)),
      subtitle: Text(details.join('  ·  '), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            s.label,
            style: TextStyle(color: s.color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }
}

/// The owner-only "tap to reveal" detail: sender/time/status header, then the decrypted body resolved
/// from the [body] future. Plaintext exists only here, in memory, while the sheet is open.
class _BodySheet extends StatelessWidget {
  const _BodySheet({required this.entry, required this.body});

  final AuditEntry entry;
  final Future<String?> body;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    final _StatusStyle s = _styleFor(entry.status);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(s.icon, color: s.color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.sender,
                    style: const TextStyle(color: AppColors.textHi, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(s.label, style: TextStyle(color: s.color, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.formatMediumDate(entry.receivedAt)}, '
              '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(entry.receivedAt))}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Text('MESSAGE', style: AppTheme.overline.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              child: FutureBuilder<String?>(
                future: body,
                builder: (BuildContext context, AsyncSnapshot<String?> snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final String? text = snap.data;
                  if (text == null || text.isEmpty) {
                    return const Text(
                      'This message can no longer be shown (it may have been cleared, or the key '
                      'changed since it was captured).',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    );
                  }
                  return SelectableText(
                    text,
                    style: const TextStyle(color: AppColors.textHi, fontSize: 14, height: 1.4),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-state copy per filter.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final AuditFilter filter;

  @override
  Widget build(BuildContext context) {
    final String text = switch (filter) {
      AuditFilter.all => 'No activity yet. Confirmed payments will appear here.',
      AuditFilter.synced => 'Nothing synced yet.',
      AuditFilter.issues => 'No issues — everything is synced.',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// Visual treatment for each sync status (label avoids the filter words All/Synced/Issues).
class _StatusStyle {
  const _StatusStyle(this.color, this.label, this.icon);

  final Color color;
  final String label;
  final IconData icon;
}

_StatusStyle _styleFor(SyncStatus status) {
  switch (status) {
    case SyncStatus.approved:
      return const _StatusStyle(AppColors.success, 'Confirmed', Icons.check_circle_outline);
    case SyncStatus.failed:
      return const _StatusStyle(AppColors.danger, 'Failed', Icons.error_outline);
    case SyncStatus.pending:
      return const _StatusStyle(AppColors.warning, 'Queued', Icons.schedule);
  }
}
