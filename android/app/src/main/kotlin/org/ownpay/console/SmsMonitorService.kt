package org.ownpay.console

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps OwnPay Console alive to process payment SMS promptly and shows the
 * mandatory ongoing notification ("Monitoring payments").
 *
 * SMS capture itself is handled by the manifest-registered [SmsReceiver] and does NOT depend on this
 * service running; the service exists for timeliness, survivability, and user transparency, and is
 * restarted after reboot by [BootReceiver].
 *
 * Targets API 36 (Android 16). The `dataSync` FGS type is time-capped (~6h/24h) on Android 15+, so we
 * handle the [onTimeout] callbacks by stopping cleanly — capture is unaffected (it runs off the manifest
 * receiver), and monitoring re-arms when the app is next foregrounded.
 */
class SmsMonitorService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        // START_STICKY: if the OS kills us under memory pressure, recreate the service when possible.
        return START_STICKY
    }

    // Android 15 (API 35): a `dataSync` foreground service may run only ~6h per 24h window; when the cap
    // is reached the system calls onTimeout and we MUST stopSelf() within seconds or get a
    // ForegroundServiceDidNotStopInTime ANR. SMS capture does NOT depend on this service (the manifest
    // SmsReceiver fires regardless), so we stop cleanly; monitoring re-arms when the app next comes to the
    // foreground (main._resumeMonitoringIfEnabled) or after reboot (BootReceiver).
    override fun onTimeout(startId: Int) {
        stopSelf()
    }

    // Android 16 (API 36) calls this two-arg overload instead of the API-35 one. Same contract: stop now.
    override fun onTimeout(startId: Int, fgsType: Int) {
        stopSelf()
    }

    private fun startInForeground() {
        createChannel()

        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("OwnPay Console")
            .setContentText("Monitoring payments")
            // Brand monochrome status-bar icon (res/drawable-*/ic_stat_notify.png), tinted white by the OS.
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 14+ can refuse a dataSync foreground service started from the background — e.g.
            // from BOOT_COMPLETED — with ForegroundServiceStartNotAllowedException. SMS capture does not
            // depend on this service (the manifest SmsReceiver fires regardless), so degrade gracefully
            // instead of crashing: stop self; the next user-foreground start re-arms the notification.
            stopSelf()
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Payment monitoring",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Keeps OwnPay Console watching for payment SMS."
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val CHANNEL_ID = "ownpay_payment_monitoring"
        private const val NOTIFICATION_ID = 1001

        fun start(context: Context) {
            val intent = Intent(context, SmsMonitorService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SmsMonitorService::class.java))
        }
    }
}
