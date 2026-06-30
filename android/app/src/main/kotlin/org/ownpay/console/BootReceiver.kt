package org.ownpay.console

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the monitoring foreground service after a device reboot, but only if the user previously
 * enabled monitoring. SMS capture via [SmsReceiver] resumes automatically regardless; this just brings
 * back the ongoing notification and keeps the process warm. Starting a foreground service from
 * BOOT_COMPLETED is permitted by the platform's background-start restrictions.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, "android.intent.action.QUICKBOOT_POWERON" -> {
                if (SmsBridge.isMonitoringEnabled(context)) {
                    SmsMonitorService.start(context)
                }
            }
        }
    }
}
