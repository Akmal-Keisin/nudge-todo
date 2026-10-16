package com.nudge.nudge

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val EXTRA_TRIGGER = "nudge_trigger"
        private const val METHOD_CHANNEL = "com.nudge/nudge"
        private const val EVENT_CHANNEL = "com.nudge/nudge_events"
        private const val REQUEST_NOTIFICATIONS = 3001
    }

    private var methodChannel: MethodChannel? = null
    private var pendingTrigger: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Notifications are the whole point of the app, so ask for the runtime
        // grant on first launch instead of waiting for the user to find
        // Settings. The dialog appears once; later launches are a no-op.
        window.decorView.post { requestNotificationPermission() }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pendingTrigger = intent?.getStringExtra(EXTRA_TRIGGER)
        intent?.removeExtra(EXTRA_TRIGGER)
        applyNudgeWindowFlags(pendingTrigger != null)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialTrigger" -> {
                    NudgeLog.d("getInitialTrigger=$pendingTrigger")
                    result.success(pendingTrigger)
                    pendingTrigger = null
                }
                "updateSnapshot" -> {
                    handleUpdateSnapshot(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                "presentNudge" -> {
                    // Native owns presentation on Android because the service
                    // has to nudge while Flutter is dead — and it has already
                    // posted by the time this call arrives. Only align the
                    // cooldown timestamp so both sides agree.
                    NudgeLog.d("presentNudge (native already posted)")
                    NudgePrefs.setLastShownAt(this, System.currentTimeMillis())
                    result.success(null)
                }
                "setStartAtLogin" -> {
                    val enabled =
                        (call.arguments as? Map<*, *>)?.get("enabled") as? Boolean ?: true
                    NudgePrefs.setStartAtLogin(this, enabled)
                    if (enabled) NudgeService.start(this, null) else NudgeService.stop(this)
                    result.success(null)
                }
                "dismiss" -> {
                    NudgeNotifications.cancelNudge(this)
                    moveTaskToBack(true)
                    result.success(null)
                }
                "isHyperOs" -> result.success(isHyperOs())
                "openAutostartSettings" -> {
                    openAutostartSettings()
                    result.success(null)
                }
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    requestNotificationPermission()
                    result.success(null)
                }
                "requestFullScreenIntentPermission" -> {
                    openFullScreenIntentSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    NudgeEvents.attach(events)
                }

                override fun onCancel(arguments: Any?) {
                    NudgeEvents.attach(null)
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val trigger = intent.getStringExtra(EXTRA_TRIGGER) ?: return
        intent.removeExtra(EXTRA_TRIGGER)
        applyNudgeWindowFlags(true)
        NudgeEvents.emit(trigger)
    }

    private fun parseSnapshot(arguments: Map<*, *>?): NudgeSnapshot? {
        if (arguments == null) return null
        val titles = (arguments["titles"] as? List<*>)
            ?.mapNotNull { it as? String } ?: emptyList()
        return NudgeSnapshot(
            pendingCount = (arguments["pendingCount"] as? Int) ?: 0,
            titles = titles,
            enabled = (arguments["enabled"] as? Boolean) ?: false,
            cooldownMinutes = (arguments["cooldownMinutes"] as? Int) ?: 15,
            showTextInNotifications =
                (arguments["showTextInNotifications"] as? Boolean) ?: true,
        )
    }

    private fun handleUpdateSnapshot(arguments: Map<*, *>?) {
        val snapshot = parseSnapshot(arguments) ?: return
        NudgeLog.d(
            "updateSnapshot pending=${snapshot.pendingCount} " +
                "enabled=${snapshot.enabled}",
        )
        NudgePrefs.saveSnapshot(this, snapshot)
        NudgeNotifications.notifyPersistent(this, snapshot.pendingCount)
        if (snapshot.enabled) NudgeService.start(this, null) else NudgeService.stop(this)
    }

    private fun applyNudgeWindowFlags(launchedByNudge: Boolean) {
        if (!launchedByNudge) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    /**
     * Detects Xiaomi's HyperOS. Cannot read the `ro.mi.*` build properties:
     * those live in the Android property service and `System.getProperty` only
     * sees Java system properties. Brand plus the security-center package is
     * what the Autostart deep link depends on anyway.
     */
    private fun isHyperOs(): Boolean {
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val isXiaomiFamily = manufacturer.contains("xiaomi") ||
            brand.contains("redmi") ||
            brand.contains("poco")
        val result = isXiaomiFamily && isPackageInstalled("com.miui.securitycenter")
        NudgeLog.d(
            "isHyperOs=$result manufacturer=$manufacturer brand=$brand " +
                "release=${Build.VERSION.RELEASE}",
        )
        return result
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
        }.isSuccess
    }

    private fun openAutostartSettings() {
        val component = ComponentName(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        val intent = Intent().setComponent(component)
        if (intent.resolveActivity(packageManager) != null) {
            runCatching { startActivity(intent) }.onFailure { openAppDetails() }
        } else {
            openAppDetails()
        }
    }

    private fun openBatterySettings() {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$packageName")
        }
        if (intent.resolveActivity(packageManager) != null) {
            runCatching { startActivity(intent) }
        } else {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }

    private fun openAppDetails() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        runCatching { startActivity(intent) }
    }

    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
            }
            runCatching { startActivity(intent) }.onFailure { openAppDetails() }
        } else {
            openAppDetails()
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQUEST_NOTIFICATIONS,
            )
        }
    }
}
