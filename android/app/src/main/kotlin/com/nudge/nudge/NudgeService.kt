package com.nudge.nudge

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.SystemClock

/**
 * Foreground service that keeps the process alive so screen-on and unlock
 * events can raise the nudge. On HyperOS this survives only if the user grants
 * the Autostart permission and the battery exemptions.
 */
class NudgeService : Service() {

    private var receiver: NudgeScreenReceiver? = null

    override fun onCreate() {
        super.onCreate()
        NudgeNotifications.ensureChannel(this)
        registerScreenReceiver()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val snapshot = NudgePrefs.loadSnapshot(this)
        NudgeLog.d(
            "service start trigger=${intent?.getStringExtra(EXTRA_TRIGGER)} " +
                "pending=${snapshot.pendingCount} enabled=${snapshot.enabled}",
        )
        startForeground(
            PERSISTENT_ID,
            NudgeNotifications.persistent(this, snapshot.pendingCount),
        )

        val trigger = intent?.getStringExtra(EXTRA_TRIGGER)
        if (trigger != null) {
            NudgeEngine.maybeNudge(this, trigger, snapshot)
        }
        NudgeEngine.scheduleAlarm(this, snapshot)
        return START_STICKY
    }

    private fun registerScreenReceiver() {
        if (receiver != null) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        receiver = NudgeScreenReceiver()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
    }

    override fun onDestroy() {
        receiver?.let { runCatching { unregisterReceiver(it) } }
        receiver = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val PERSISTENT_ID = 1001
        const val EXTRA_TRIGGER = "nudge_service_trigger"
        const val ACTION_START = "com.nudge.nudge.START"
        const val ACTION_STOP = "com.nudge.nudge.STOP"

        fun start(context: Context, trigger: String?) {
            val intent = Intent(context, NudgeService::class.java).apply {
                action = ACTION_START
                if (trigger != null) putExtra(EXTRA_TRIGGER, trigger)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, NudgeService::class.java))
        }
    }
}

/** Reacts to screen-on and unlock while the service is running. */
class NudgeScreenReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val trigger = when (intent.action) {
            Intent.ACTION_SCREEN_ON -> "screenOn"
            Intent.ACTION_USER_PRESENT -> "unlock"
            else -> return
        }
        NudgeLog.d("screen receiver trigger=$trigger")
        val snapshot = NudgePrefs.loadSnapshot(context)
        NudgeEngine.maybeNudge(context, trigger, snapshot)
    }
}

/**
 * Decides whether a trigger should actually nudge, applying the enabled flag,
 * quiet-ish cooldown and the pending-todo requirement.
 */
object NudgeEngine {
    private const val ALARM_REQUEST = 2001

    fun maybeNudge(context: Context, trigger: String, snapshot: NudgeSnapshot) {
        if (!snapshot.enabled || snapshot.pendingCount <= 0) {
            NudgeLog.d(
                "engine skip trigger=$trigger enabled=${snapshot.enabled} " +
                    "pending=${snapshot.pendingCount}",
            )
            return
        }

        val now = System.currentTimeMillis()
        val bypassCooldown = trigger == "boot" || trigger == "login"
        val cooldownMs = snapshot.cooldownMinutes.coerceAtLeast(1) * 60_000L
        val elapsed = now - NudgePrefs.lastShownAt(context)
        if (!bypassCooldown && elapsed < cooldownMs) {
            NudgeLog.d(
                "engine cooldown trigger=$trigger elapsedMs=$elapsed " +
                    "cooldownMs=$cooldownMs",
            )
            return
        }

        NudgeLog.d("engine present trigger=$trigger pending=${snapshot.pendingCount}")
        NudgePrefs.setLastShownAt(context, now)
        NudgeNotifications.notifyNudge(context, snapshot, trigger)
        NudgeEvents.emit(trigger)
        launchActivity(context, trigger)
        scheduleAlarm(context, snapshot)
    }

    /** Tier 2 attempt: only works when the overlay permission is granted. */
    private fun launchActivity(context: Context, trigger: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TRIGGER, trigger)
        }
        runCatching { context.startActivity(intent) }
    }

    /**
     * HyperOS can kill the service; a repeating alarm re-arms the nudge if it
     * comes back within the cooldown window.
     */
    fun scheduleAlarm(context: Context, snapshot: NudgeSnapshot) {
        val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
        val triggerAt = SystemClock.elapsedRealtime() +
            snapshot.cooldownMinutes.coerceAtLeast(1) * 60_000L

        val intent = Intent(context, NudgeAlarmReceiver::class.java)
        val pending = PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        runCatching {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAt,
                pending,
            )
        }.onFailure {
            alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pending)
        }
    }
}
