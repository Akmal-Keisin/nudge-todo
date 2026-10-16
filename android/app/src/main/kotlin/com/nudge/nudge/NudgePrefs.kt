package com.nudge.nudge

import android.content.Context
import org.json.JSONArray

/**
 * The snapshot Flutter pushes to native so the service can decide whether to
 * nudge without starting the Flutter engine.
 */
data class NudgeSnapshot(
    val pendingCount: Int,
    val titles: List<String>,
    val enabled: Boolean,
    val cooldownMinutes: Int,
    val showTextInNotifications: Boolean,
)

/** Persists the snapshot, the nudge config and the cooldown timestamp. */
object NudgePrefs {
    private const val FILE = "nudge_native"
    private const val KEY_PENDING = "pending_count"
    private const val KEY_TITLES = "titles"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_COOLDOWN = "cooldown_minutes"
    private const val KEY_SHOW_TEXT = "show_text"
    private const val KEY_LAST_SHOWN = "last_shown_at"
    private const val KEY_START_AT_LOGIN = "start_at_login"

    private fun prefs(context: Context) =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun saveSnapshot(context: Context, snapshot: NudgeSnapshot) {
        prefs(context).edit()
            .putInt(KEY_PENDING, snapshot.pendingCount)
            .putString(KEY_TITLES, JSONArray(snapshot.titles).toString())
            .putBoolean(KEY_ENABLED, snapshot.enabled)
            .putInt(KEY_COOLDOWN, snapshot.cooldownMinutes)
            .putBoolean(KEY_SHOW_TEXT, snapshot.showTextInNotifications)
            .apply()
    }

    fun loadSnapshot(context: Context): NudgeSnapshot {
        val p = prefs(context)
        val rawTitles = p.getString(KEY_TITLES, "[]") ?: "[]"
        val titles = mutableListOf<String>()
        runCatching {
            val array = JSONArray(rawTitles)
            for (i in 0 until array.length()) titles.add(array.getString(i))
        }
        return NudgeSnapshot(
            pendingCount = p.getInt(KEY_PENDING, 0),
            titles = titles,
            enabled = p.getBoolean(KEY_ENABLED, false),
            cooldownMinutes = p.getInt(KEY_COOLDOWN, 15),
            showTextInNotifications = p.getBoolean(KEY_SHOW_TEXT, true),
        )
    }

    fun lastShownAt(context: Context): Long =
        prefs(context).getLong(KEY_LAST_SHOWN, 0L)

    fun setLastShownAt(context: Context, value: Long) {
        prefs(context).edit().putLong(KEY_LAST_SHOWN, value).apply()
    }

    fun startAtLogin(context: Context): Boolean =
        prefs(context).getBoolean(KEY_START_AT_LOGIN, true)

    fun setStartAtLogin(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_START_AT_LOGIN, value).apply()
    }
}
