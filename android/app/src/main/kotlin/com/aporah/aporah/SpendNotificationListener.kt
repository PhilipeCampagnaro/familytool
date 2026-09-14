package com.aporah.aporah

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/// Android's half of automatic spend capture.
///
/// **What it is a replacement for, and what it is not.** On iOS a Personal
/// Automation hands an App Intent the transaction itself, typed. Android has no
/// such trigger and no wallet API that reads transactions — Google's Wallet API
/// issues passes. What it does have is the notification the wallet posts to the
/// user the moment a tap goes through, carrying the shop, the amount and the
/// card. This service reads that one notification and files it, which is the
/// same payment arriving by a worse road.
///
/// **The privacy cost is real and is the reason the setup screen says so out
/// loud.** Notification access is all-or-nothing: the system offers no way to
/// subscribe to one app, so granting it means this process is handed every
/// notification on the phone, messages and one-time codes included. Two things
/// follow, and both are enforced here rather than promised in copy:
///
/// - [onNotificationPosted] returns immediately for every package that is not a
///   wallet, before it reads a single extra. Nothing else is looked at, logged,
///   buffered or counted.
/// - What leaves the phone is a shop name, an amount, a card's last four digits
///   and a timestamp. Never the notification text, never the package list.
///
/// It posts straight to `spend-ingest` with the device token, exactly as the
/// Swift intent does, because there is no Flutter engine here either: the system
/// starts this service on its own and keeps it alive across app launches, which
/// is what makes capture work while Aporah has not been opened for a week.
class SpendNotificationListener : NotificationListenerService() {
    companion object {
        private const val TAG = "AporahSpend"

        /// Same window the ingest function dedupes on. Both are needed: this one
        /// stops a notification the wallet *updates* from becoming a second
        /// spend, and the server's stops two devices in one household filing the
        /// same tap.
        private const val DEDUPE_WINDOW_MS = 120_000L
        private const val DEDUPE_MEMORY = 32

        /// Whether the user has granted notification access to *this* service.
        ///
        /// Read from the system's own setting rather than remembered, because
        /// the user can revoke it in Settings at any time and a remembered
        /// "granted" would leave the app claiming a capture that has silently
        /// stopped.
        fun hasAccess(context: Context): Boolean {
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            val us = ComponentName(context, SpendNotificationListener::class.java)
            return enabled.split(':').any {
                val component = ComponentName.unflattenFromString(it)
                component != null && component.packageName == us.packageName
            }
        }

        /// The system screen that grants it. There is no runtime permission
        /// dialog for notification access and there never has been — the user
        /// has to find this app in a system list and switch it on, which is why
        /// the setup page spells the step out instead of just opening this.
        fun accessSettingsIntent(): Intent =
            Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private val network = Executors.newSingleThreadExecutor()
    private val recent = LinkedHashMap<String, Long>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // The first line of the privacy promise above. Everything below this
        // point only ever runs for a wallet.
        if (!WalletNotifications.isSource(sbn.packageName)) return

        val credential = SpendCredential.load(applicationContext) ?: return

        val notification = sbn.notification ?: return
        // A group summary repeats what its children already said, and an ongoing
        // notification is a progress bar rather than a completed payment.
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (notification.flags and Notification.FLAG_ONGOING_EVENT != 0) return

        val extras = notification.extras ?: return
        val payment = WalletNotifications.parse(
            title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
        ) ?: return

        val occurredAt = if (sbn.postTime > 0L) sbn.postTime else System.currentTimeMillis()
        if (!remember(payment, occurredAt)) return

        network.execute { post(credential, payment, occurredAt) }
    }

    /// False when this exact payment has just been filed. Keyed on what the user
    /// would call the same payment rather than on the notification's own id: a
    /// wallet that edits its notification in place keeps the id, and one that
    /// replaces it does not, so the id answers the wrong question either way.
    private fun remember(payment: WalletPayment, occurredAt: Long): Boolean {
        val key = payment.merchant.lowercase() + "|" + payment.amountCents + "|" + payment.currency
        synchronized(recent) {
            val seen = recent[key]
            if (seen != null && occurredAt - seen < DEDUPE_WINDOW_MS) return false
            recent[key] = occurredAt
            while (recent.size > DEDUPE_MEMORY) {
                recent.remove(recent.keys.first())
            }
        }
        return true
    }

    /// Deliberately dumb, like the Swift side: no retry, no queue, no interest in
    /// the answer beyond whether the server took it. The endpoint dedupes and
    /// repairs on its side, and a retry loop in a background service is how a
    /// duplicate spend gets filed twice.
    private fun post(credential: SpendCredential.Stored, payment: WalletPayment, occurredAt: Long) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(credential.endpoint).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 15_000
                readTimeout = 20_000
                setRequestProperty("Content-Type", "application/json")
                // The function runs with `verify_jwt = false`, so this identifies
                // the project to the gateway rather than the user to the
                // function. The device token in the body is what authorises the
                // write.
                setRequestProperty("apikey", credential.apiKey)
            }

            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use {
                it.write(body(credential.token, payment, occurredAt))
            }

            val code = connection.responseCode
            if (code !in 200..299) {
                // No merchant, no amount, nothing that could name a household.
                Log.w(TAG, "spend-ingest refused a capture: HTTP $code")
            }
        } catch (e: Exception) {
            Log.w(TAG, "spend-ingest could not be reached")
        } finally {
            connection?.disconnect()
        }
    }

    private fun body(token: String, payment: WalletPayment, occurredAt: Long): String {
        val fields = StringBuilder()
        fields.append("{")
        fields.append("\"token\":").append(quote(token))
        fields.append(",\"merchant\":").append(quote(payment.merchant))
        fields.append(",\"amount_cents\":").append(payment.amountCents)
        fields.append(",\"currency\":").append(quote(payment.currency))
        fields.append(",\"occurred_at\":").append(quote(iso8601(occurredAt)))
        fields.append(",\"card_label\":")
            .append(payment.cardLabel?.let(::quote) ?: "null")
        // Only ever sent as true. The function decides `needs_review` for itself
        // from the payload it can see; this adds the one thing it cannot, which
        // is that the shop name was inferred rather than read.
        if (payment.needsReview) fields.append(",\"needs_review\":true")
        fields.append("}")
        return fields.toString()
    }

    /// `SimpleDateFormat` rather than `java.time`, because the minimum SDK is 24
    /// and `Instant` arrived at 26. Pinned to UTC and `Locale.US` so a phone set
    /// to a non-Gregorian calendar cannot emit a timestamp Postgres reads as a
    /// different year.
    private fun iso8601(millis: Long): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date(millis))
    }

    private fun quote(value: String): String {
        val out = StringBuilder("\"")
        for (c in value) {
            when (c) {
                '"' -> out.append("\\\"")
                '\\' -> out.append("\\\\")
                '\n' -> out.append("\\n")
                '\r' -> out.append("\\r")
                '\t' -> out.append("\\t")
                else -> if (c < ' ') out.append(String.format("\\u%04x", c.code)) else out.append(c)
            }
        }
        return out.append("\"").toString()
    }
}
