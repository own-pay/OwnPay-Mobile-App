package org.ownpay.console

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

/**
 * Manifest-registered receiver for `SMS_RECEIVED`. It fires even when the app's UI/engine is not
 * running, so it does the minimum: parse the message and hand it to [SmsBridge] for durable buffering.
 *
 * No filtering happens here — deciding what may leave the device is the job of the on-device privacy
 * gate, which runs later in Dart and is fail-closed by design.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: return
        if (messages.isEmpty()) {
            return
        }

        // A multipart SMS arrives as several PDUs that must be concatenated into one body; they share
        // the originating address and timestamp.
        val first = messages[0]
        val sender = first.displayOriginatingAddress ?: first.originatingAddress ?: ""
        val timestamp = first.timestampMillis
        val body = buildString {
            for (message in messages) {
                append(message.displayMessageBody ?: message.messageBody ?: "")
            }
        }
        if (body.isEmpty()) {
            return
        }

        SmsBridge.onSmsReceived(context, sender, body, timestamp)
    }
}
