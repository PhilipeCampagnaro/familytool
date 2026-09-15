package com.aporah.aporah

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/// Scheduled, on-device notifications — the Android half of the
/// "aporah/notifications" channel `ios/Runner/LocalNotifications.swift`
/// implements for iOS. Same four methods, same contract.
///
/// **By hand rather than `flutter_local_notifications`**, and not for taste: the
/// iOS app builds through Swift Package Manager with no Podfile, and a plugin
/// ships an iOS half whether we call it or not. That half would also install
/// its own notification-centre delegate over ours. Android needs an alarm, a
/// receiver and a notification, none of which is much code.
///
/// **The Dart side owns the schedule; this side replaces it wholesale.** The set
/// is written to preferences as well as armed, because Android clears every
/// alarm on reboot and the receiver re-arms from that copy.
object LocalNotifications {
    const val NAME = "aporah/notifications"
    const val CHANNEL_ID = "aporah.reminders"
    const val PERMISSION_REQUEST = 7041
    const val ACTION_FIRE = "com.aporah.aporah.NOTICE"

    private const val PREFS = "aporah_notifications"
    private const val KEY_ITEMS = "items"
    private const val KEY_CHANNEL_NAME = "channel_name"
    private const val KEY_ASKED = "asked"

    private var pendingPermission: MethodChannel.Result? = null

    data class Item(val id: String, val at: Long, val title: String, val body: String)

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        val context = activity.applicationContext
        when (call.method) {
            "status" -> result.success(status(context))
            "request" -> request(activity, result)
            "openSettings" -> {
                openSettings(activity)
                result.success(null)
            }
            "replaceAll" -> {
                @Suppress("UNCHECKED_CAST")
                val raw = call.argument<List<Map<String, Any?>>>("items") ?: emptyList()
                val items = raw.mapNotNull { map ->
                    val id = map["id"] as? String ?: return@mapNotNull null
                    val at = (map["at"] as? Number)?.toLong() ?: return@mapNotNull null
                    val title = map["title"] as? String ?: return@mapNotNull null
                    Item(id, at, title, map["body"] as? String ?: "")
                }
                replaceAll(context, items, call.argument<String>("channelName") ?: "Aporah")
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /// Android has no "provisional". Below 13 a grant is the default; from 13 it
    /// is a runtime permission, and "never asked" is told apart from "refused"
    /// by a flag we set when we ask, because the platform does not say.
    fun status(context: Context): String {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 33) {
            val granted = context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
            if (!granted) {
                val asked = prefs(context).getBoolean(KEY_ASKED, false)
                return if (asked) "denied" else "notDetermined"
            }
        }
        return if (manager.areNotificationsEnabled()) "authorized" else "denied"
    }

    private fun request(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(status(activity))
            return
        }
        prefs(activity).edit().putBoolean(KEY_ASKED, true).apply()
        // A second ask while the first dialog is up answers the first with the
        // current state rather than leaving it waiting forever.
        pendingPermission?.success(status(activity))
        pendingPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
    }

    fun onPermissionResult(activity: Activity) {
        pendingPermission?.success(status(activity))
        pendingPermission = null
    }

    private fun openSettings(activity: Activity) {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", activity.packageName, null))
        }
        activity.startActivity(intent)
    }

    private fun replaceAll(context: Context, items: List<Item>, channelName: String) {
        ensureChannel(context, channelName)
        val alarms = context.getSystemService(AlarmManager::class.java)
        for (old in stored(context)) alarms.cancel(pendingIntent(context, old))

        val json = JSONArray()
        for (item in items) {
            json.put(
                JSONObject().put("id", item.id).put("at", item.at).put("title", item.title).put("body", item.body)
            )
        }
        prefs(context).edit()
            .putString(KEY_ITEMS, json.toString())
            .putString(KEY_CHANNEL_NAME, channelName)
            .apply()
        arm(context, items)
    }

    /// After a reboot or an app update, from the stored copy.
    fun rearm(context: Context) {
        ensureStoredChannel(context)
        arm(context, stored(context))
    }

    /// The channel under the name it was last given from Dart, in the user's
    /// language. "Aporah" only before anything was ever scheduled.
    fun ensureStoredChannel(context: Context) {
        ensureChannel(context, prefs(context).getString(KEY_CHANNEL_NAME, null) ?: "Aporah")
    }

    private fun arm(context: Context, items: List<Item>) {
        val alarms = context.getSystemService(AlarmManager::class.java)
        val now = System.currentTimeMillis()
        for (item in items) {
            if (item.at <= now) continue
            val intent = pendingIntent(context, item)
            // Exact when the user has let us, inexact otherwise. Android 14 denies
            // exact alarms to new installs by default; an inexact one can land a
            // few minutes late in Doze, which is a late reminder rather than a
            // missing one.
            if (Build.VERSION.SDK_INT >= 31 && !alarms.canScheduleExactAlarms()) {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.at, intent)
            } else {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.at, intent)
            }
        }
    }

    /// The id rides in the intent's data, not only its extras: `PendingIntent`
    /// equality ignores extras, so two notices differing only there would be one
    /// alarm, and cancelling one would cancel the other.
    private fun pendingIntent(context: Context, item: Item): PendingIntent {
        val intent = Intent(context, NoticeReceiver::class.java)
            .setAction(ACTION_FIRE)
            .setData(Uri.fromParts("aporah-notice", item.id, null))
            .putExtra("id", item.id)
            .putExtra("title", item.title)
            .putExtra("body", item.body)
        return PendingIntent.getBroadcast(
            context,
            item.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun ensureChannel(context: Context, name: String) {
        if (Build.VERSION.SDK_INT < 26) return
        // Creating an existing channel again only updates its name, which is how
        // a language change reaches the system settings screen.
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    private fun stored(context: Context): List<Item> {
        val raw = prefs(context).getString(KEY_ITEMS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { i ->
                val o = array.getJSONObject(i)
                Item(o.getString("id"), o.getLong("at"), o.getString("title"), o.optString("body"))
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
