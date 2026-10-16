# Nudge Platform Implementation Guide

Detailed implementation notes for each target platform. Read alongside `docs/plan.md`.

---

## Android (HyperOS 2.0 — Poco X7 Pro, Redmi Pad Pro)

### Manifest declarations

```xml
<!-- Permissions -->
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
<uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />

<!-- Boot receiver -->
<receiver android:name=".BootReceiver" android:exported="true">
  <intent-filter>
    <action android:name="android.intent.action.BOOT_COMPLETED" />
  </intent-filter>
</receiver>

<!-- Foreground service -->
<service
  android:name=".NudgeService"
  android:foregroundServiceType="specialUse"
  android:exported="false" />
```

### HyperOS battery exemption onboarding

The onboarding screen must walk the user through three layers:

1. **Autostart permission** — open `com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity` via intent. Detect HyperOS with `Build.MANUFACTURER` + `ro.miui.ui.version.name` system property.

2. **Battery saver** — open `Settings.ACTION_APPLICATION_DETAILS_SETTINGS`, instruct user to set Battery Saver to "No restrictions".

3. **Battery usage limits** (HyperOS 2.0+) — Settings → Battery → Battery Usage Limits → Unrestricted. No reliable deep link exists; show instructions.

Use the `MIUI-autostart` library to check autostart state programmatically. If state is `DISABLED`, show the onboarding.

### Full-screen intent

```kotlin
val intent = Intent(context, MainActivity::class.java).apply {
  flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION
  putExtra("nudge", true)
}
val pendingIntent = PendingIntent.getActivity(
  context, 0, intent,
  PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
)

val notification = NotificationCompat.Builder(context, CHANNEL_ID)
  .setSmallIcon(R.drawable.ic_nudge)
  .setContentTitle("You have $count things to do")
  .setFullScreenIntent(pendingIntent, true)
  .setPriority(NotificationCompat.PRIORITY_HIGH)
  .setCategory(NotificationCompat.CATEGORY_ALARM)
  .build()
```

On Android 14+, the user must manually grant `USE_FULL_SCREEN_INTENT` in Settings. Use `canUseFullScreenIntent()` to check and deep-link to `Settings.ACTION_MANAGE_FULL_SCREEN_INTENT` if not granted.

### Fallback: AlarmManager re-fire

If HyperOS kills the foreground service, `AlarmManager.setExactAndAllowWhileIdle` can re-fire the nudge after the cooldown period. Store the next alarm time in SharedPreferences. Use `ScheduleExactAlarm` permission on Android 12+.

### MethodChannel contract

Flutter → Kotlin:
- `updateSnapshot(int pendingCount, List<String> titles, Map config)` — called whenever the todo list or nudge config changes.
- `dismissNudge()` — "Got it" button pressed.

Kotlin → Flutter:
- `nudgeTriggered(String trigger)` — boot/unlock/screenOn, so Flutter shows the nudge screen.

---

## Linux (niri Wayland compositor, Arch Linux)

### Autostart

The `launch_at_startup` package writes `~/.config/autostart/nudge.desktop`:

```ini
[Desktop Entry]
Type=Application
Name=Nudge
Exec=/path/to/nudge
X-GNOME-Autostart-enabled=true
```

Niri's systemd user unit (`niri.service`) brings up `xdg-desktop-autostart.target`, which executes autostart entries.

### D-Bus signals to listen for

```dart
// 1. Resume from suspend (from logind)
// Interface: org.freedesktop.login1.Manager
// Signal: PrepareForSleep(false)

// 2. Session unlock (from logind)
// Interface: org.freedesktop.login1.Session
// Signal: Unlock
// Get session path: GetSessionByPID(getpid())

// 3. Screen lock fallback (if using external locker)
// Interface: org.freedesktop.ScreenSaver
// Signal: ActiveChanged(false)
// Note: niri implements ScreenSaver for idle inhibit, but
// ActiveChanged comes from the locker, not niri.
```

### Window focus strategy

niri uses `xdg-activation-v1` for focus transfer. A background app without a valid token gets marked urgent, not focused.

**Recommended approach for Tier 2:**
1. Send a desktop notification (`flutter_local_notifications`) with an action button.
2. When the user clicks the notification, the action provides a valid activation token.
3. The app receives the token and uses it to request focus — niri will focus the window because the request came from user interaction.

**Direct window raising** (Tier 2 aggressive):
```dart
// window_manager can raise the window, but niri will mark it
// urgent instead of focused if there's no valid token.
// This is acceptable — the urgent indicator in the bar is visible.
await WindowManager.instance.show();
```

### Tray icon (Waybar)

The `tray_manager` package implements StatusNotifierItem (SNI). For the tray to appear, the user must have an SNI host running — on niri this is typically Waybar with the `tray` module enabled.

If no SNI host is detected, fall back gracefully (the app still runs, just no tray icon).

### Screen locker integration (Noctalia shell)

Noctalia is a full desktop shell for niri (bar, launcher, notifications, lock screen, etc.). It uses the standard Wayland `ext-session-lock-v1` protocol for locking and integrates with logind for D-Bus signals.

**Noctalia D-Bus behavior:**
- Listens for `org.freedesktop.login1.Session.Lock` signal to engage lock screen
- Listens for `org.freedesktop.login1.Session.Unlock` to dismiss lock screen
- Listens for `org.freedesktop.login1.Manager.PrepareForSleep` to lock before suspend
- Calls `org.freedesktop.login1.Session.SetLockedHint(bool)` to tell logind the lock state
- Does NOT emit custom D-Bus signals — all communication is through standard logind

**For Nudge, listen on logind D-Bus signals (system bus):**
```dart
// Session unlock (from logind — triggered by Noctalia unlocking)
// Interface: org.freedesktop.login1.Session
// Signal: Unlock

// Resume from suspend (from logind)
// Interface: org.freedesktop.login1.Manager
// Signal: PrepareForSleep(false)
```

This is the universal approach — works with Noctalia, swaylock, hyprlock, or any locker that integrates with logind.

**Lock commands:**
- Lock: `noctalia msg session lock` or `loginctl lock-session`
- Lock and suspend: `noctalia msg session lock-and-suspend`

### System dependencies

Arch Linux packages needed:
```bash
pacman -S clang cmake ninja pkgconf gtk3
pacman -S libayatana-appindicator libsecret
```

For tray support, ensure Waybar is configured with the `tray` module:
```jsonc
// waybar config
{
  "modules-right": ["tray", ...]
}
```