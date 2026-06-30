package org.ownpay.console

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Bridges native SMS capture to the Flutter layer.
 *
 * Durability model: every captured SMS is appended to a persistent on-disk buffer (SharedPreferences)
 * BEFORE any attempt to notify Dart. Delivery to Dart is a two-step handshake: [peek] returns the
 * buffer WITHOUT clearing it, and [ackProcessed] removes only the leading messages Dart confirms it
 * has durably handled. So if Dart crashes or fails to persist mid-batch, the unacked messages remain
 * for the next peek — no loss. The EventChannel only emits a lightweight "items pending" nudge so a
 * live app drains promptly; if the app is dead when an SMS arrives, the item still waits in the buffer
 * for the next peek on launch. This yields at-least-once delivery across process death (the on-device
 * privacy gate + the server's dedupe make redelivery harmless).
 *
 * The buffer holds raw bodies only transiently and is never logged; the on-device privacy gate (which
 * decides what may leave the phone) runs later, in Dart, and is fail-closed.
 */
object SmsBridge {
    private const val PREFS = "ownpay_sms_buffer"
    private const val KEY_BUFFER = "buffer"
    private const val KEY_MONITORING = "monitoring_enabled"

    /** Hard cap so a never-draining client cannot grow storage without bound; oldest are dropped. */
    private const val MAX_BUFFERED = 500

    private const val METHOD_CHANNEL = "org.ownpay.console/sms"
    private const val EVENT_CHANNEL = "org.ownpay.console/sms_events"

    private val mainHandler = Handler(Looper.getMainLooper())

    // Read on the SMS-receiver thread, written on the main thread — @Volatile guarantees visibility.
    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    /** Wire the method + event channels onto a Flutter engine (called from [MainActivity]). */
    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    setMonitoringEnabled(appContext, true)
                    SmsMonitorService.start(appContext)
                    result.success(null)
                }
                "stopMonitoring" -> {
                    setMonitoringEnabled(appContext, false)
                    SmsMonitorService.stop(appContext)
                    result.success(null)
                }
                "isMonitoring" -> result.success(isMonitoringEnabled(appContext))
                "peekPending" -> result.success(peek(appContext))
                "ackProcessed" -> {
                    ackProcessed(appContext, call.argument<Int>("count") ?: 0)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                // Nudge immediately so a freshly-attached listener drains anything already buffered.
                val pending = bufferedCount(appContext)
                if (pending > 0) {
                    events?.success(pending)
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    /** Called by [SmsReceiver] for each captured message. Safe to call from any thread. */
    fun onSmsReceived(context: Context, sender: String, body: String, timestampMillis: Long) {
        val appContext = context.applicationContext
        append(appContext, sender, body, timestampMillis)
        val sink = eventSink ?: return
        val pending = bufferedCount(appContext)
        mainHandler.post { sink.success(pending) }
    }

    @Synchronized
    private fun append(context: Context, sender: String, body: String, ts: Long) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = JSONArray(prefs.getString(KEY_BUFFER, "[]") ?: "[]")
        current.put(
            JSONObject()
                .put("sender", sender)
                .put("body", body)
                .put("ts", ts)
        )
        val capped = if (current.length() > MAX_BUFFERED) {
            val trimmed = JSONArray()
            for (i in (current.length() - MAX_BUFFERED) until current.length()) {
                trimmed.put(current.get(i))
            }
            trimmed
        } else {
            current
        }
        prefs.edit().putString(KEY_BUFFER, capped.toString()).apply()
    }

    /** Returns all buffered messages as a List<Map> for Flutter WITHOUT clearing the buffer. */
    @Synchronized
    fun peek(context: Context): List<Map<String, Any?>> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = JSONArray(prefs.getString(KEY_BUFFER, "[]") ?: "[]")
        val out = ArrayList<Map<String, Any?>>(stored.length())
        for (i in 0 until stored.length()) {
            val obj = stored.getJSONObject(i)
            out.add(
                mapOf(
                    "sender" to obj.optString("sender"),
                    "body" to obj.optString("body"),
                    "ts" to obj.optLong("ts"),
                )
            )
        }
        return out
    }

    /**
     * Removes the first [count] buffered messages — the ones Dart has durably handled (gate-dropped or
     * encrypted + enqueued). Messages that arrived after the matching [peek] were appended to the end,
     * so dropping the leading [count] preserves them: capture stays lossless even if Dart fails partway
     * through a batch (it simply re-peeks the unacked tail next time).
     */
    @Synchronized
    fun ackProcessed(context: Context, count: Int) {
        if (count <= 0) {
            return
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = JSONArray(prefs.getString(KEY_BUFFER, "[]") ?: "[]")
        val remaining = JSONArray()
        for (i in count until stored.length()) {
            remaining.put(stored.get(i))
        }
        prefs.edit().putString(KEY_BUFFER, remaining.toString()).apply()
    }

    @Synchronized
    private fun bufferedCount(context: Context): Int {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return JSONArray(prefs.getString(KEY_BUFFER, "[]") ?: "[]").length()
    }

    fun setMonitoringEnabled(context: Context, enabled: Boolean) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_MONITORING, enabled).apply()
    }

    fun isMonitoringEnabled(context: Context): Boolean =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_MONITORING, false)
}
