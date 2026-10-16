package com.nudge.nudge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Boot is blocked on HyperOS unless the user grants the Autostart permission.
 * The service is started here so an immediate nudge can run before any unlock.
 */
class NudgeBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        NudgeLog.d("boot receiver startAtLogin=${NudgePrefs.startAtLogin(context)}")
        if (!NudgePrefs.startAtLogin(context)) return
        NudgeService.start(context, "boot")
    }
}

/** Fallback re-fire when the foreground service was killed. */
class NudgeAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NudgeLog.d("alarm receiver fired")
        val snapshot = NudgePrefs.loadSnapshot(context)
        NudgeEngine.maybeNudge(context, "manual", snapshot)
    }
}
