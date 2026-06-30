import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/di.dart';
import '../../../core/services/app_refresh_signal.dart';
import '../../../core/storage/secure_store.dart';
import '../../../shared/theme/app_theme.dart';
import '../domain/dashboard_repository.dart';
import '../domain/dashboard_snapshot.dart';
import 'dashboard_cubit.dart';

/// Paired home (mockup #1): the "Active Host Node" header, the monitoring-status block, today's stat
/// tiles, and recent payments — cached for offline with an "as of" banner.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<DashboardCubit>(
      create: (_) => DashboardCubit(sl<DashboardRepository>(), sl<SecureStore>())..load(),
      child: DashboardView(refresh: sl<AppRefreshSignal>()),
    );
  }
}

/// Split from [DashboardScreen] so widget tests can pump it with an injected cubit. Reloads whenever the
/// bottom-nav Refresh action fires ([refresh] is supplied by the screen; null in tests → no subscription).
class DashboardView extends StatefulWidget {
  const DashboardView({this.refresh, super.key});

  final AppRefreshSignal? refresh;

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
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
      context.read<DashboardCubit>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (BuildContext context, DashboardState state) {
            final DashboardCubit cubit = context.read<DashboardCubit>();
            return _body(context, state, cubit);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DashboardState state, DashboardCubit cubit) {
    if (state.loading && !state.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasData) {
      return _ErrorState(message: state.failure?.message ?? 'No data to show.', onRetry: cubit.refresh);
    }
    final DashboardSnapshot snapshot = state.snapshot!;
    return RefreshIndicator(
      onRefresh: cubit.refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: <Widget>[
          _HostCard(host: state.serverHost, online: !state.offline),
          const SizedBox(height: 12),
          const _MonitoringCard(),
          if (state.offline) ...<Widget>[
            const SizedBox(height: 12),
            _OfflineBanner(asOf: snapshot.fetchedAt),
          ],
          const SizedBox(height: 16),
          _StatsRow(snapshot: snapshot),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              const Text('RECENT PAYMENTS', style: AppTheme.overline),
              GestureDetector(
                onTap: () => context.go('/audit'),
                child: const Text(
                  'View Ledger',
                  style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (snapshot.recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('No payments yet.', style: TextStyle(color: AppColors.textMuted)),
              ),
            )
          else
            ...snapshot.recent.map((DashboardTransaction t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PaymentTile(txn: t),
                )),
        ],
      ),
    );
  }
}

/// "Active Host Node" header: server host + a live/offline pill.
class _HostCard extends StatelessWidget {
  const _HostCard({required this.host, required this.online});

  final String host;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        children: <Widget>[
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.dns_rounded, color: AppColors.brand, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Active Host Node',
                  style: TextStyle(color: AppColors.textHi, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Pill(
            label: online ? 'Linked' : 'Offline',
            color: online ? AppColors.brand : AppColors.warning,
            dot: true,
          ),
        ],
      ),
    );
  }
}

/// Operational-status block: capture + sync are running.
class _MonitoringCard extends StatelessWidget {
  const _MonitoringCard();

  @override
  Widget build(BuildContext context) {
    return const _Card(
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Monitoring Active',
                  style: TextStyle(color: AppColors.textHi, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 2),
                Text(
                  'Monitoring mobile gateway rules',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          _Pill(label: 'Sync Enabled', color: AppColors.brand, outlined: true),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.asOf});

  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off_outlined, color: AppColors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Showing saved data as of ${l10n.formatMediumDate(asOf)}, '
              '${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(asOf))}.',
              style: const TextStyle(color: AppColors.warning, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final String currency = _dominantCurrency(snapshot.recent);
    final DashboardTransaction? last = snapshot.recent.isNotEmpty ? snapshot.recent.first : null;
    final MaterialLocalizations l10n = MaterialLocalizations.of(context);
    // IntrinsicHeight bounds the cross-axis so the three tiles stretch to a shared (equal) height
    // instead of being asked for an infinite height inside the scrolling list.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
        Expanded(
          child: _StatTile(
            label: 'TODAY RECEIVED',
            value: _money(currency, snapshot.todayRevenue),
            footer: 'Synced',
            footerColor: AppColors.success,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'TXN COUNT',
            value: '${snapshot.todayTotal}',
            footer: 'Live Node',
            footerColor: AppColors.textMuted,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            label: 'LAST PAYMENT',
            value: last != null ? _money(currency, last.amount) : '—',
            footer: last != null
                ? l10n.formatTimeOfDay(TimeOfDay.fromDateTime(last.createdAt))
                : 'No data',
            footerColor: AppColors.textMuted,
          ),
        ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.footer,
    required this.footerColor,
  });

  final String label;
  final String value;
  final String footer;
  final Color footerColor;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: AppTheme.overline.copyWith(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textHi, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 6),
          Text(footer, style: TextStyle(color: footerColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// One recent payment row: gateway badge · amount + trx id · status pill.
class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.txn});

  final DashboardTransaction txn;

  @override
  Widget build(BuildContext context) {
    final _PayStatus s = _statusFor(txn.status);
    final String gateway = (txn.gateway.isNotEmpty ? txn.gateway : 'SMS').toUpperCase();
    final String currency = txn.currency.isNotEmpty ? txn.currency : '';
    return _Card(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.outline),
            ),
            child: Text(
              gateway,
              style: const TextStyle(
                color: AppColors.textHi,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _money(currency, txn.amount),
                  style: const TextStyle(color: AppColors.textHi, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  txn.trxId.isNotEmpty ? txn.trxId : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Pill(label: s.label, color: s.color),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.warning),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textHi)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// A bordered dark surface card — the app's base container.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: child,
    );
  }
}

/// A status pill (filled-tint or outlined), optionally with a leading status dot.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color, this.dot = false, this.outlined = false});

  final String label;
  final Color color;
  final bool dot;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: outlined ? color.withValues(alpha: 0.6) : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dot) ...<Widget>[
            Container(
              height: 6,
              width: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Visual treatment for a payment's status.
class _PayStatus {
  const _PayStatus(this.label, this.color);

  final String label;
  final Color color;
}

_PayStatus _statusFor(String raw) {
  switch (raw.toLowerCase()) {
    case 'completed':
    case 'accepted':
    case 'success':
    case 'synced':
      return const _PayStatus('Synced', AppColors.success);
    case 'failed':
    case 'cancelled':
    case 'canceled':
    case 'rejected':
      return const _PayStatus('Failed', AppColors.danger);
    case '':
      return const _PayStatus('Pending', AppColors.warning);
    default:
      return _PayStatus(_titleCase(raw), AppColors.warning);
  }
}

String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

/// The currency shared by the recent transactions, if they agree; else '' (no prefix). Avoids
/// presuming a single platform currency — OwnPay is multi-currency.
String _dominantCurrency(List<DashboardTransaction> txns) {
  String? code;
  for (final DashboardTransaction t in txns) {
    if (t.currency.isEmpty) continue;
    if (code == null) {
      code = t.currency;
    } else if (code != t.currency) {
      return '';
    }
  }
  return code ?? '';
}

/// Formats a [Decimal] to exactly two decimals (string-only — no double, no precision drift), with an
/// optional currency-code prefix.
String _money(String currency, Decimal d) {
  final String s = d.toString();
  final int dot = s.indexOf('.');
  final String formatted;
  if (dot < 0) {
    formatted = '$s.00';
  } else {
    final String whole = s.substring(0, dot);
    final String frac = s.substring(dot + 1);
    formatted = frac.length >= 2 ? '$whole.${frac.substring(0, 2)}' : '$whole.${frac.padRight(2, '0')}';
  }
  return currency.isEmpty ? formatted : '$currency $formatted';
}
