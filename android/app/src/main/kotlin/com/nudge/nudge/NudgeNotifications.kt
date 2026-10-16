package com.nudge.nudge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat

/** Builds the persistent notification and the full-screen nudge notification. */
object NudgeNotifications {
    private const val CHANNEL_ID = "nudge_alerts"
    private const val PERSISTENT_ID = 1001
    private const val NUDGE_ID = 1002

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Nudge",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Reminds you about pending todos"
            enableLights(true)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun contentIntent(context: Context, trigger: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TRIGGER, trigger)
        }
        return PendingIntent.getActivity(
            context,
            trigger.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** Silent, ongoing notification that keeps the service alive. */
    fun persistent(context: Context, pending: Int): Notification {
        val text = if (pending > 0) {
            "$pending pending"
        } else {
            "All clear"
        }
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_nudge)
            .setContentTitle("Nudge")
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent(context, "manual"))
            .build()
    }

    /** High-priority nudge; a full-screen intent shows it over the lockscreen. */
    fun nudge(context: Context, snapshot: NudgeSnapshot, trigger: String): Notification {
        val count = snapshot.pendingCount
        val noun = if (count == 1) "thing" else "things"
        val body = if (snapshot.showTextInNotifications && snapshot.titles.isNotEmpty()) {
            snapshot.titles.take(5).joinToString("\n")
        } else {
            "Open Nudge to see your list."
        }
        val pendingIntent = contentIntent(context, trigger)
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_nudge)
            .setContentTitle("You have $count $noun to do")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()
    }

    fun notifyPersistent(context: Context, pending: Int) {
        context.getSystemService(NotificationManager::class.java)
            .notify(PERSISTENT_ID, persistent(context, pending))
    }

    fun notifyNudge(context: Context, snapshot: NudgeSnapshot, trigger: String) {
        context.getSystemService(NotificationManager::class.java)
            .notify(NUDGE_ID, nudge(context, snapshot, trigger))
    }

    fun cancelNudge(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NUDGE_ID)
    }
}
