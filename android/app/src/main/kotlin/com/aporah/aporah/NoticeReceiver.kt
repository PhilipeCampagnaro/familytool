package com.aporah.aporah

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/// Posts a scheduled notice when its alarm goes off, and re-arms the whole set
/// after a reboot or an app update — the two moments Android forgets alarms.
///
/// The text arrives in the intent, rendered in the user's language at the time
/// it was scheduled; nothing here reads Flutter or the network.
class NoticeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                LocalNotifications.rearm(context)
            }
            LocalNotifications.ACTION_FIRE -> post(context, intent)
        }
    }

    private fun post(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        val title = intent.getStringExtra("title") ?: return
        val body = intent.getStringExtra("body") ?: ""

        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) return
        LocalNotifications.ensureStoredChannel(context)

        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val tap = launch?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, LocalNotifications.CHANNEL_ID)
        } else {
            Notification.Builder(context).setDefaults(Notification.DEFAULT_SOUND)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_aporah)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .apply { if (tap != null) setContentIntent(tap) }
            .build()

        manager.notify(id.hashCode(), notification)
    }
}
