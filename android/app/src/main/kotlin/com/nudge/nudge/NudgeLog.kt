package com.nudge.nudge

import android.util.Log

/**
 * Single log tag for the whole nudge pipeline so the trigger chain can be
 * followed with `adb logcat -s Nudge`.
 */
object NudgeLog {
    private const val TAG = "Nudge"

    fun d(message: String) {
        Log.d(TAG, message)
    }

    fun w(message: String) {
        Log.w(TAG, message)
    }
}
