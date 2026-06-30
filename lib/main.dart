import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'app/router.dart';
import 'core/config/app_config.dart';
import 'core/network/certificate_pinner.dart';
import 'core/services/session_status.dart';
import 'core/storage/secure_store.dart';
import 'features/permissions/data/consent_store.dart';
import 'features/notifications/data/notification_poller.dart';
import 'features/pairing/data/device_heartbeat.dart';
import 'features/permissions/domain/sms_permission.dart';
import 'features/sms_capture/data/sms_ingest_coordinator.dart';
import 'features/sms_capture/domain/sms_capture.dart';
import 'features/sync/data/sync_worker.dart';
import 'features/sync/domain/sms_queue_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await configureDependencies();
  // Load the TOFU cert pin before any request fires (release pinning; harmless no-op in debug).
  await sl<CertificatePinner>().load();

  // Capture consumer (drain → gate → encrypt → enqueue) and sync worker (queue → POST /sms). Each reacts
  // to its own event stream — the native "items pending" nudge and connectivity-up — and the coordinator
  // kicks the worker right after it enqueues. Here we also drain/sync on app resume and now, on cold start
  // (the durable native buffer and the offline queue may carry items from a previous process). Both no-op
  // safely when the device is unpaired or offline.
  final SmsIngestCoordinator coordinator = sl<SmsIngestCoordinator>()..start();
  final SyncWorker syncWorker = sl<SyncWorker>()..start();
  final NotificationPoller poller = sl<NotificationPoller>()..start();
  // Heartbeat so the admin panel shows this device as online (its window is a few minutes); see #7.
  final DeviceHeartbeat heartbeat = sl<DeviceHeartbeat>()..start();
  WidgetsBinding.instance.addObserver(_ResumeObserver(() async {
    await coordinator.drainNow();
    await syncWorker.syncNow();
    await poller.poll();
    await heartbeat.beat();
  }));
  unawaited(coordinator.drainNow());
  unawaited(syncWorker.syncNow());
  // Retention cleanup (best-effort, cold start): drop synced rows past the retention window.
  unawaited(sl<SmsQueueStore>().purgeApproved(DateTime.now().subtract(AppConfig.syncedRetention)));
  // Resume the capture foreground service if the user previously enabled it (cold start re-arm).
  unawaited(_resumeMonitoringIfEnabled());

  runApp(OwnPayConsoleApp(
    router: buildRouter(initialLocation: await _resolveStart(), session: sl<SessionStatus>()),
  ));
}

/// Re-starts SMS monitoring on cold start when it was previously enabled — i.e. the device is paired and
/// `READ_SMS`/`RECEIVE_SMS` is still granted. Capture is otherwise only started on disclosure-grant, so
/// without this it would stay off after an app relaunch until the next grant.
Future<void> _resumeMonitoringIfEnabled() async {
  if (!await sl<SecureStore>().isPaired()) {
    return;
  }
  if (await sl<PermissionGate>().smsStatus() == SmsPermission.granted) {
    await sl<SmsCapture>().startMonitoring();
  }
}

/// Re-drains the capture buffer and re-attempts queue sync each time the app returns to the foreground.
class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this._onResume);

  final Future<void> Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onResume());
    }
  }
}

/// Resolves the start route once at launch:
/// unpaired → pair · paired but onboarding not finished → disclosure · otherwise → home.
Future<String> _resolveStart() async {
  final bool paired = await sl<SecureStore>().isPaired();
  if (!paired) {
    return '/pair';
  }
  final bool disclosureDone = await sl<ConsentStore>().isDisclosureCompleted();
  return disclosureDone ? '/' : '/disclosure';
}
