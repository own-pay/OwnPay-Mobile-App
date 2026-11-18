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
 * Durability model: every captured message is appended to a persistent on-disk buffer (SharedPreferences)
 * BEFORE any attempt to notify Dart. Delivery to Dart is a two-step handshake: [peek] returns the
 * buffer WITHOUT clearing it, and [ackProcessed] removes only the leading messages Dart confirms it
 * has durably handled. So if Dart crashes or fails to persist mid-batch, the unacked messages remain
 * for the next peek — no loss. The EventChannel only emits a lightweight "items pending" nudge so a
 * live app drains promptly; if the app is dead when an SMS arrives, the item still waits in the buffer
 * for the next peek on launch. This yields at-least-once delivery across process death (the on-device
 * privacy gate + the server's dedupe make redelivery harmless).
 *
 * At-rest protection: the buffer itself is AES-256-GCM encrypted with a non-extractable key held in the
 * Android Keystore (alias [SmsBufferCrypto.KEY_ALIAS]). The value in SharedPreferences is
 * `v2:` + base64(iv || ciphertext) over the JSON array bytes, so even a root reader of the app's
 * private preferences sees only ciphertext. Pre-upgrade legacy plaintext buffers are adopted on first
 * access and rewritten encrypted on the next mutation.
 *
 * Sender filtering: the admin pushes the whitelist of sender IDs over the authenticated API
 * (`/api/mobile/v1/config/filter-rules`); Dart mirrors it here via setAllowedSenders(). The native
 * receiver drops any SMS whose sender does NOT match the cached list and never persists it. If the
 * list has never been synced (fresh install before first rules sync), everything is kept so we never
 * silently lose a payment confirmation; rejection happens in that case at the Dart privacy gate
 * (fail-closed).
 *
 * The buffer holds raw bodies only transiently (decrypted in memory during append/peek/ack/trim) and is
 * never logged; the on-device privacy gate (which decides what may leave the phone) runs later, in Dart,
 * and is fail-closed.
 */
object SmsBridge {
    private const val PREFS = "ownpay_sms_buffer"
    private const val KEY_BUFFER = "buffer"
    private const val KEY_MONITORING = "monitoring_enabled"

    /** Lifetime counter of capture-time messages the buffer had to evict unread (storage overflow). */
    private const val KEY_DROPPED_OVERFLOW = "dropped_overflow_count"

    /** Lifetime counter of capture-time messages dropped at the door (sender not in whitelist). */
    private const val KEY_DROPPED_FILTERED = "dropped_filtered_count"

    /** JSON array of whitelisted sender IDs as synced from the server. Absent until first sync. */
    private const val KEY_ALLOWED_SENDERS = "allowed_senders_json"

    /** Hard cap so a never-draining client cannot grow storage without bound; oldest are dropped. */
    private const val MAX_BUFFERED = 500

    /** v2 marker prefix for the Keystore AES-GCM encrypted buffer format. */
    private const val BUFFER_FORMAT_PREFIX = "v2:"

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
                "setAllowedSenders" -> {
                    val raw = call.argument<List<String>>("senders")
                    result.success(setAllowedSenders(appContext, raw))
                }
                "getDroppedOverflowCount" -> result.success(droppedOverflowCount(appContext))
                "getDroppedFilteredCount" -> result.success(droppedFilteredCount(appContext))
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

    /**
     * Mirrors the server-side sender whitelist from Dart into the native cache. Returns how many
     * senders were stored (0 clears the cache back to "not yet synced / keep everything").
     */
    fun setAllowedSenders(context: Context, senders: List<String>?): Int {
        val clean = (senders ?: emptyList())
            .map { normalizeSender(it) }
            .filter { it.isNotEmpty() }
            .distinct()
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (clean.isEmpty()) {
            prefs.edit().remove(KEY_ALLOWED_SENDERS).apply()
            return 0
        }
        val arr = JSONArray()
        for (s in clean) {
            arr.put(s)
        }
        prefs.edit().putString(KEY_ALLOWED_SENDERS, arr.toString()).apply()
        return clean.size
    }

    /** Returns the normalized cached whitelist, or null if it has never been synced. */
    fun allowedSenders(context: Context): List<String>? {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        if (!prefs.contains(KEY_ALLOWED_SENDERS)) {
            return null
        }
        val raw = prefs.getString(KEY_ALLOWED_SENDERS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            val out = ArrayList<String>(arr.length())
            for (i in 0 until arr.length()) {
                val s = arr.optString(i, "")
                if (s.isNotEmpty()) {
                    out.add(s)
                }
            }
            out
        } catch (_: Exception) {
            emptyList()
        }
    }

    /** Normalize for comparison: lowercase alphanumerics only. */
    private fun normalizeSender(raw: String): String =
        raw.lowercase().filter { it.isLetterOrDigit() }

    @Synchronized
    private fun append(context: Context, sender: String, body: String, ts: Long) {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        // Door filter: never persist an SMS from a sender the server did not whitelist.
        val cached = allowedSenders(appContext)
        if (cached != null) {
            val normalized = normalizeSender(sender)
            if (cached.none { it == normalized }) {
                prefs.edit()
                    .putLong(KEY_DROPPED_FILTERED, prefs.getLong(KEY_DROPPED_FILTERED, 0L) + 1L)
                    .apply()
                return
            }
        }

        val current = readBufferArray(prefs)
        current.put(
            JSONObject()
                .put("sender", sender)
                .put("body", body)
                .put("ts", ts)
        )
        val capped = if (current.length() > MAX_BUFFERED) {
            val evicted = current.length() - MAX_BUFFERED
            // Overflow almost always means a hostile SMS flood or a wedged drain path — either way,
            // unread payment confirmations may be lost. Count the loss so Dart can surface it instead
            // of failing silently.
            prefs.edit()
                .putLong(KEY_DROPPED_OVERFLOW, prefs.getLong(KEY_DROPPED_OVERFLOW, 0L) + evicted)
                .apply()
            val trimmed = JSONArray()
            for (i in (current.length() - MAX_BUFFERED) until current.length()) {
                trimmed.put(current.get(i))
            }
            trimmed
        } else {
            current
        }
        writeBufferArray(prefs, capped)
    }

    /** Returns all buffered messages as a List<Map> for Flutter WITHOUT clearing the buffer. */
    @Synchronized
    fun peek(context: Context): List<Map<String, Any?>> {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = readBufferArray(prefs)
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
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val stored = readBufferArray(prefs)
        val remaining = JSONArray()
        for (i in count until stored.length()) {
            remaining.put(stored.get(i))
        }
        writeBufferArray(prefs, remaining)
    }

    @Synchronized
    private fun bufferedCount(context: Context): Int {
        val appContext = context.applicationContext
        val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return readBufferArray(prefs).length()
    }

    fun setMonitoringEnabled(context: Context, enabled: Boolean) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_MONITORING, enabled).apply()
    }

    fun isMonitoringEnabled(context: Context): Boolean =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_MONITORING, false)

    fun droppedOverflowCount(context: Context): Long =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_DROPPED_OVERFLOW, 0L)

    fun droppedFilteredCount(context: Context): Long =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getLong(KEY_DROPPED_FILTERED, 0L)

    /** Reads the buffer as a JSONArray, transparently decrypting v2 (or adopting legacy plaintext). */
    private fun readBufferArray(prefs: android.content.SharedPreferences): JSONArray {
        val raw = prefs.getString(KEY_BUFFER, null)
        if (raw.isNullOrBlank()) {
            return JSONArray()
        }
        return try {
            if (raw.startsWith(BUFFER_FORMAT_PREFIX)) {
                JSONArray(SmsBufferCrypto.decryptBuffer(raw.removePrefix(BUFFER_FORMAT_PREFIX)))
            } else {
                // Legacy plaintext from before the encrypted buffer landed — adopt once, re-encrypt on next write.
                JSONArray(raw)
            }
        } catch (_: Exception) {
            // Damaged or foreign ciphertext — start empty rather than crash the capture path.
            JSONArray()
        }
    }

    /** Writes the JSONArray as an encrypted (v2) buffer entry; an empty array clears the slot. */
    private fun writeBufferArray(prefs: android.content.SharedPreferences, value: JSONArray) {
        if (value.length() == 0) {
            prefs.edit().remove(KEY_BUFFER).apply()
            return
        }
        val encrypted = SmsBufferCrypto.encryptBuffer(value.toString())
        prefs.edit().putString(KEY_BUFFER, BUFFER_FORMAT_PREFIX + encrypted).apply()
    }
}
