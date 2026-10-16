# Nudge Todo: Plan, Flutter Guidelines and API Contract

_Working name "Nudge" · Draft v2 · October 14, 2026_

## 1. Overview

A single-user todo list for Android (phone and tablet) and Linux desktop. Its one special trait: it shows itself when you start or unlock a device, so pending tasks can't slip by unnoticed.

**Goals**

- One list of single-line todos: add, edit, delete, check.
- Checked todos go to an archive and are permanently deleted after 14 days.
- Nudge: the list appears on boot/login and on unlock, on all three of your devices.
- Same data on every device through a Go backend.

**Non-goals (v1):** due dates, tags, sub-tasks, detail pages, multiple users, iOS/web/Windows/macOS.

**Key decisions**

- Client: Flutter, Material 3, Riverpod for state, dio for HTTP.
- Backend: Go + Fiber, REST/JSON, SQLite to start, a single bearer token.
- The server is the source of truth; the client caches the list so the nudge works offline.
- Distribution: sideloaded APK on Android, release bundle on Linux. No Play Store, which removes Play policy limits (OS limits still apply).

## 2. The Nudge feature

**Verdict: feasible on both platforms.** Android needs a small amount of native Kotlin and some manual permission grants. Linux is simpler, but Wayland limits how forcefully a window can appear. This is the riskiest part of the project, so Phase 0.5 proves it on your real devices before any UI is built.

### Two tiers

- **Tier 1, passive (very reliable):** a persistent notification listing pending todos (Android); a desktop notification plus tray icon (Linux).
- **Tier 2, active:** the app itself comes to the front on boot, login and unlock, over the lock screen on Android.

Ship Tier 1 first as the baseline. Tier 2 is the goal.

### Triggers

- Android: device boot, screen on, user unlock.
- Linux: login (autostart), resume from suspend, session unlock or screen saver deactivated.

### Behavior rules

- Nudge only if at least one active todo exists.
- Cooldown (default 15 minutes, per device) so repeated unlocks don't spam you. Boot and login ignore the cooldown.
- Optional quiet hours, off by default.
- The nudge is the normal list screen with a banner "You have N things to do" and a "Got it" button that sends the app away (Android: back to the previous app; Linux: hide to tray).
- It must work offline: it uses the cached list and refreshes in the background without delaying the pop-up.
- Settings is the only second screen: nudge on/off, cooldown, quiet hours, start at login/boot, API URL and token.

### Android implementation notes

- Native Kotlin glue of a few hundred lines. A manifest `BootReceiver` (BOOT_COMPLETED) starts a foreground service. The service registers a runtime receiver for screen-on and user-present events, because these can't be declared in the manifest on modern Android.
- Android blocks starting activities from the background. Use a high-priority notification with a full-screen intent (shows the app over the lock screen) and, optionally, the "Display over other apps" permission.
- The main activity sets the show-when-locked and turn-screen-on flags when launched by the nudge.
- Flutter and Kotlin talk through one MethodChannel. Flutter pushes a snapshot (pending count, first few titles) and the config into native SharedPreferences, so the service can decide without starting Flutter.
- Permissions: notifications (Android 13+), boot completed, foreground service (special use type), full-screen intent (Android 14+ may need a manual grant in Settings), plus optional overlay and battery-optimization exemption.
- Biggest risk: manufacturer battery managers kill background services. Add an onboarding screen that deep-links to battery settings, and test after a reboot and again after 24 hours.
- Lock-screen privacy: let the user choose whether notifications show todo text or only the count.

**HyperOS/MIUI-specific (Poco X7 Pro, Redmi Pad Pro):**

- Both devices run HyperOS 2.0 (Android 15). HyperOS is the most aggressive Android skin for killing background services.
- `BOOT_COMPLETED` is **silently blocked** by default. The user MUST enable the Xiaomi-specific Autostart permission via `com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity`.
- Three separate battery layers must all be set to unrestricted: (1) Autostart permission, (2) Battery Saver → No Restrictions, (3) Battery Usage Limits → Unrestricted (HyperOS 2.0+).
- Use `foregroundServiceType="specialUse"` in the manifest — HyperOS is more lenient with specific service types.
- Full-screen intents work IF all battery exemptions are granted AND the FSI permission is manually enabled in Settings on Android 14+.
- Onboarding screen must walk the user through ALL three battery layers with deep links. Detect HyperOS via `ro.miui.ui.version.name` system property.
- Use the `MIUI-autostart` library (github.com/XomaDev/MIUI-autostart) to check autostart state programmatically.
- Consider `AlarmManager.setExactAndAllowWhileIdle` as a fallback to re-fire the nudge if the foreground service is killed.

### Linux implementation notes

- Start at login with an XDG autostart entry (the `launch_at_startup` package writes it).
- Listen on D-Bus (`dbus` package) for the logind `Unlock` signal on the session, `PrepareForSleep(false)` for resume from suspend, and the screen saver `ActiveChanged(false)` signal as a fallback.
- Keep running in the tray (`tray_manager`); closing the window hides it. GNOME needs the AppIndicator extension to show tray icons.
- Show the window with `window_manager`. On Wayland the compositor may refuse to raise or focus it; then fall back to a desktop notification (`flutter_local_notifications`) that opens the app on click.
- Behavior differs by desktop environment and by X11 vs Wayland, so verify on yours.

**niri-specific (Wayland compositor on Arch Linux):**

- **Tray:** niri has no built-in tray. Use Waybar's `tray` module (StatusNotifierItem protocol). The `tray_manager` Flutter package uses SNI, which works through Waybar. Document that Waybar must be running for the tray icon to appear.
- **Window focus:** niri uses `xdg-activation-v1` for focus requests. A background app without a valid activation token gets marked **urgent** (not focused). For the nudge, use a desktop notification that opens the app on click — this provides the valid token needed for focus. Direct window raising from a background service will be marked urgent at best, ignored at worst.
- **Autostart:** works via XDG autostart entries in `~/.config/autostart/`. Niri's systemd user unit brings up `xdg-desktop-autostart.target`. The `launch_at_startup` package writes the correct `.desktop` file.
- **D-Bus signals for unlock/resume:**
  - `org.freedesktop.login1.Manager.PrepareForSleep(false)` — resume from suspend (from logind, not niri)
  - Session unlock: use `org.freedesktop.login1.Session.Unlock` signal on the session path (get via `org.freedesktop.login1.Manager.GetSessionByPID`)
  - Screen saver: niri implements `org.freedesktop.ScreenSaver` for idle inhibit, but does NOT implement a screen saver deactivation signal. Use an external locker (swaylock/hyprlock) and listen for its D-Bus signals, or rely on the login1 unlock signal.
- **Recommended Tier 2 strategy:** Tier 1 (persistent notification) is reliable. For Tier 2, send a desktop notification with an action that opens the app — this gives the compositor a user-initiated reason to focus the window.
- **No built-in screen locker:** niri requires an external locker (swaylock, hyprlock). The unlock signal comes from logind when the locker releases the session.

## 3. Product and UI requirements

### Layout

- One main screen. Top bar: title with pending count, an Active | Archive switch, and an overflow menu (Refresh, Settings).
- Body: the list. The Active tab has a composer pinned to the bottom (text field plus add button).
- On wide screens (desktop, tablet landscape) content is centered with a max width of about 720 px.
- Material 3, following system light/dark.

### Row behavior: seeing the full text without a detail page

Each todo is one row, and the row itself is the detail view.

- **Collapsed:** checkbox, then the text limited to 2 lines with an ellipsis, plus a small chevron.
- **Tap the row (not the checkbox):** it expands in place to show the full text and an action bar (Edit, Delete). Tap again, or tap another row, to collapse. Only one row is expanded at a time.
- Short todos expand too (to reveal the actions), so one gesture always works and there is no "detail button".
- No navigation, no dialogs, no extra screens.

### Actions

- **Add:** type and press Enter or the add button. Trimmed, 1 to 500 characters. New items appear at the top.
- **Edit:** the expanded row turns into a text field with Save and Cancel (Enter saves, Esc cancels on desktop). Empty text can't be saved.
- **Delete:** permanent, with a "Deleted · Undo" message for 5 seconds. Undo re-creates the item with the same id (its created time resets, which is acceptable).
- **Check:** the checkbox archives the item (it animates out) and shows "Archived · Undo".
- **Archive tab:** archived todos, newest first, each showing "Done 3 days ago · deleted in 11 days". Unchecking restores it to Active. Expanded archived rows offer Restore and Delete (no editing; restore first).
- **Retention:** archived todos are permanently deleted 14 days after being archived. The server does the deleting, and the client also hides expired items.

### States

- Loading skeleton, an empty state per tab, and an error banner with Retry.
- Offline banner: shows the saved list; add, edit, delete and check are disabled in v1.
- Refresh: pull-to-refresh, on app resume, a refresh button on desktop, and every 60 seconds while the window is visible.

### Desktop and accessibility

- Shortcuts: Ctrl+N focuses the composer, Enter submits, Esc cancels or collapses, Ctrl+R refreshes.
- 48 dp minimum touch targets, semantic labels, large-text support, full keyboard navigation.

## 4. Development plan

### Implementation status (as built)

| Area | Status |
| --- | --- |
| Phase 0 setup | Done — toolchain clean, repo scaffolded, `AGENTS.md`, `analysis_options.yaml` |
| Todo list UI (composer, expand, edit, delete, archive, undo, retention) | Done |
| Nudge platform layer (`NudgePlatform` + Android/Linux/no-op) | Done |
| Android native glue (boot receiver, foreground service, full-screen intent, HyperOS onboarding, AlarmManager fallback) | Done and verified on the Poco X7 Pro |
| Linux nudge (autostart, logind D-Bus, tray, notification) | Done and verified on niri |
| Settings screen (nudge, cooldown, quiet hours, lock-screen privacy, Android permissions) | Done |
| Desktop shortcuts (Ctrl+N, Ctrl+R, Esc) | Done |
| Refresh on resume / every 60s | Done |
| Loading skeleton | Not yet (plain spinner) |
| Go backend (`server/`), Fiber v3, SQLite, goose, auth, rate limit, prune, tests, Dockerfile | Done and exercised end to end |
| `openapi.yaml` | Written at `server/openapi.yaml` |
| Flutter `RemoteTodoRepository` (dio) + cache + offline fallback | Done |
| Settings: server URL + token, with a connection test | Done |
| Offline banner + writes disabled offline | Done |
| Verified: client code against a real running server | Done (`tool/smoke_remote.dart`, 17 checks) |
| Deployment: Caddy + Docker Compose, systemd unit, runbook | Done at `server/deploy/`, stack verified end to end over HTTPS |
| End-to-end on all three devices against a deployed server | Needs a real host + domain |

### Phase 0: Setup (about half a day)

- Install the Flutter stable SDK and Android Studio. On Linux install `clang cmake ninja-build pkg-config libgtk-3-dev`. The tray and secure-storage plugins need extra system packages later (for example `libayatana-appindicator3-dev`, `libsecret-1-dev`); their READMEs list them.
- `flutter doctor` must be clean. Create the repo, add `analysis_options.yaml` and `AGENTS.md` (section 6).
- Run the default Flutter app on your real Android device (USB debugging) and on Linux.

### Phase 0.5: Nudge spike (1 to 2 days)

A tiny app that only proves the trigger works.

- Android: after a reboot and after unlock, the app or notification appears. Test on both phone and tablet.
- Linux: autostart at login, and unlock or resume brings up the window or a notification on your desktop environment.
- Exit criteria: it still works after a reboot and after 24 hours on the phone. You now know which tier each device can achieve.

### Phase 1: Flutter client with local data (no backend)

1. Scaffold, theme, folder structure.
2. `TodoRepository` interface plus `LocalTodoRepository` (shared_preferences). The backend client will implement the same interface later.
3. List UI: composer, expand, edit, delete, check, archive tab, 14-day prune rule applied locally.
4. Unit and widget tests.
5. Nudge integration and Settings screen.
6. Release builds: `flutter build apk --release`, `flutter build linux --release`.

Exit criteria: you use it daily by itself, with local data.

### Phase 2: Go backend and integration

1. Finalize `openapi.yaml` (section 7).
2. Go Fiber service: handlers, validation, storage, prune job, auth, tests, Dockerfile, deployment behind HTTPS.
3. Flutter: `RemoteTodoRepository` (dio) plus cache, swapped in with one provider override. Add URL/token settings and offline handling.
4. End-to-end test on all three devices.

## 5. Flutter code guidelines

### Architecture

Feature-first folders with layers inside each feature. Dependencies point inward: presentation → application → domain, and data implements domain.

```
lib/
  main.dart
  app/               # MaterialApp, theme, top-level providers
  core/
    errors/          # AppFailure types
    network/         # dio client, interceptors
    platform/        # NudgePlatform interface + android/linux/noop impls
    utils/
  features/
    todos/
      domain/        # Todo entity, TodoRepository interface
      data/          # LocalTodoRepository, RemoteTodoRepository, DTOs
      application/   # Riverpod controllers
      presentation/  # screens and widgets
    nudge/
    settings/
test/                # mirrors lib/
android/app/src/main/kotlin/.../nudge/   # native glue
```

- `domain` is pure Dart: entities and repository interfaces, with no Flutter, dio or storage imports.
- Widgets never call dio, shared_preferences or platform channels. They watch providers.
- Every external dependency sits behind an interface so tests and Phase 1 can swap it.

### State management (Riverpod)

- `AsyncNotifier` for the todo list, one controller per feature.
- `ref.watch` in `build`, `ref.read` in callbacks, never `ref.read` inside `build`.
- `setState` only for purely local UI state (which row is expanded, text controllers).
- The repository is exposed through a provider, so Phase 2 swaps `LocalTodoRepository` for `RemoteTodoRepository` with one override.

### Dart style

- Follow Effective Dart: files `snake_case.dart`, types `UpperCamelCase`, members `lowerCamelCase`.
- `final` by default, `const` constructors and literals wherever possible, no `dynamic`, and no `!` unless a comment justifies it.
- Immutable models with `copyWith` and value equality. Use `freezed` + `json_serializable`, or plain Dart 3 classes; pick one and stay consistent.
- Use sealed classes and pattern matching for results and failures.
- Small files and functions. Comments explain why, not what; public APIs get `///` docs.
- No `print`; use a small logger.

### Widgets

- Split UI into small widget classes, not helper methods that return widgets.
- No business logic in `build`, and no network or storage calls in widgets.
- Use `ListView.builder` for lists and `ValueKey(todo.id)` on rows.
- Dispose controllers and focus nodes.
- After every `await`, check `context.mounted` before using `BuildContext`.
- Take colors, text styles and spacing from `Theme.of(context)` and a small constants file. No magic numbers or hard-coded colors.
- Make layouts responsive with `LayoutBuilder` and constraints, not by checking the platform.

### Async, errors and data

- Repositories throw typed exceptions. Controllers convert them to `AppFailure` values. The UI shows human-readable messages, never raw exceptions.
- Use optimistic updates with rollback on failure.
- Keep all dates in UTC internally and format them at the edge.
- Validate input in the domain (trim, 1 to 500 characters) as well as in the UI.

### Platform code

- All platform differences live in `core/platform` behind a `NudgePlatform` interface with Android, Linux and no-op implementations. `defaultTargetPlatform` is checked in exactly one place.
- Kotlin code stays small, documented and free of business logic. It only listens for system events and launches the app.

### Testing

- Unit tests for repositories and controllers (`mocktail`).
- Widget tests for the todo row: truncation, expand/collapse, edit, delete, check.
- One `integration_test` smoke test for the add → check → archive flow.
- `flutter analyze` and `flutter test` must pass before every commit.

### Tooling and dependencies

`analysis_options.yaml` starting point:

```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
linter:
  rules:
    - always_declare_return_types
    - avoid_print
    - prefer_const_constructors
    - prefer_const_declarations
    - prefer_final_locals
    - unawaited_futures
```

- Add packages with `flutter pub add`, commit the lockfile, and justify each dependency. Confirm on pub.dev that it supports both Android and Linux.
- Starting set: `flutter_riverpod`, `dio`, `shared_preferences`, `uuid`, `window_manager`, `tray_manager`, `launch_at_startup`, `dbus`, `flutter_local_notifications`, `flutter_secure_storage` (for the token; needs libsecret on Linux), `mocktail`, and optionally `freezed`, `json_serializable`, `build_runner`.

### Common AI-generated mistakes to watch for

- Deprecated APIs: `withOpacity` (use `withValues(alpha: ...)`), `WillPopScope` (use `PopScope`), `MaterialStateProperty` (use `WidgetStateProperty`), `textScaleFactor` (use `textScaler`). Treat analyzer deprecation warnings as errors.
- Invented packages or outdated versions. Always verify on pub.dev.
- Plugins that only support mobile, which then break the Linux build.
- Giant files, logic inside widgets, hard-coded strings and colors.

## 6. Vibe-coding workflow

- Work in small vertical slices, for example "add todo end to end". Each prompt states the goal, acceptance criteria, which files may change, and how to verify.
- After every slice: `dart format .`, `flutter analyze`, `flutter test`, run on Linux and on Android, then commit with a conventional message (`feat: add archive tab`).
- Put this document in `docs/plan.md` and tell the AI to read it first.
- Ask before letting the AI change the architecture, add a dependency, or change the API contract.

**Definition of done for every slice:** it works on both platforms, analyzer has zero issues, tests are added or updated, no TODOs left behind, and the spec in this document is still true.

## 7. API contract

The contract is the single source of truth between the two projects. Write it as `openapi.yaml`, keep a copy in both repos, and change it only deliberately.

### Conventions

- Base URL: `https://<host>/api/v1`. JSON, UTF-8.
- Field names are `camelCase`. Timestamps are RFC 3339 in UTC. Id are UUIDs generated by the client, so retries and undo are safe.
- Auth: `Authorization: Bearer <token>` on every endpoint except `/health`.
- Successful responses wrap the payload as `{ "data": ... }`. Failures use `{ "error": { ... } }`.

### Todo object

```json
{
  "id": "0b8f4c3e-5d1a-4c52-9a7e-2f6c1e8b9d10",
  "text": "Call the bank about the card",
  "isArchived": false,
  "archivedAt": null,
  "createdAt": "2026-10-14T03:12:45Z",
  "updatedAt": "2026-10-14T03:12:45Z"
}
```

- `text`: trimmed, 1 to 500 characters.
- `archivedAt`: set by the server when `isArchived` becomes true, cleared when it becomes false.
- `createdAt` never changes. `updatedAt` changes on every write.

### Endpoints

| Method | Path          | Purpose                          | Success                 |
| ------ | ------------- | -------------------------------- | ----------------------- |
| GET    | `/health`     | Liveness check, no auth          | 200                     |
| GET    | `/todos`      | List todos                       | 200 with `data: [Todo]` |
| POST   | `/todos`      | Create a todo                    | 201 with `data: Todo`   |
| PATCH  | `/todos/{id}` | Edit text and/or archive/restore | 200 with `data: Todo`   |
| DELETE | `/todos/{id}` | Delete permanently               | 204                     |

Details:

- `GET /todos?status=` accepts `active`, `archived` or `all` (default `all`). Active is sorted by `createdAt` descending, archived by `archivedAt` descending.
- `POST /todos` body: `{ "id": "<uuid>", "text": "..." }`. `id` is optional (the server generates one if missing). If the id already exists, the existing todo is returned with 200, which makes retries idempotent.
- `PATCH /todos/{id}` body: `text` and/or `isArchived`. Changing the text of an archived todo returns 400.
- `DELETE /todos/{id}`: a 404 means it is already gone, and the client treats that as success.

### Errors

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "text must be 1 to 500 characters",
    "details": { "field": "text" }
  }
}
```

- 400 `VALIDATION_ERROR` (also used for malformed JSON), 401 `UNAUTHORIZED`, 404 `NOT_FOUND`, 429 `RATE_LIMITED`, 500 `INTERNAL_ERROR`.
- Messages are for developers. The app shows its own user-facing text.

### Auth

- Single user: the server holds one secret in the `API_TOKEN` environment variable and compares it in constant time.
- HTTPS is mandatory. To rotate, change the variable and re-enter the token in each device's Settings.
- Upgrade path if it ever becomes multi-user: login endpoint plus JWT. Not needed now.

### Retention (pruning)

- A server job runs at startup and then hourly, deleting rows where `isArchived` is true and `archivedAt` is older than `ARCHIVE_RETENTION_DAYS` (default 14).
- `GET /todos` also filters out expired rows, in case the job lags.
- The client also drops expired archived items from its cache, so no tombstones are needed.

### Sync strategy (v1)

- The server is the source of truth. `GET /todos` returns everything (the list is small), and the client replaces its cache with the result.
- The client refreshes on launch, on resume, manually, and every 60 seconds while visible.
- Writes are online-only. Concurrent edits from two devices are last-write-wins.
- Later, if needed: an offline write queue, `?updatedSince=` delta sync, ETags, or SSE for live updates.
- No pagination in v1 (expect well under 1,000 rows). Add `limit` and `cursor` if that changes.

### Data model and backend notes (Phase 2)

- Table `todos`: `id` (text, primary key), `text`, `is_archived` (default false), `archived_at` (nullable), `created_at`, `updated_at`, with an index on `(is_archived, archived_at)`.
- Pin the Fiber major version in `go.mod` and tell your AI which one you chose, because v2 and v3 APIs differ.
- Layers: handler → service → repository. Migrations with golang-migrate or goose. Config from environment (`API_TOKEN`, `DB_PATH` or `DATABASE_URL`, `ARCHIVE_RETENTION_DAYS`, `PORT`).
- Structured logging with `slog`, graceful shutdown, tests with Fiber's `app.Test`, a Dockerfile, and deployment behind an HTTPS reverse proxy (Caddy, Nginx, or a tunnel). CORS is not needed for native clients.
- Limits: request body 4 KB, about 60 requests per minute per token.

## 8. Resolved questions and device matrix

### Target devices

| Device | Type | OS | Notes |
| --- | --- | --- | --- |
| Poco X7 Pro (2412DPC0AG) | Phone | HyperOS 3.0 / Android 16 (API 36) | Tested on device. The most aggressive HyperOS; Autostart plus the battery exemptions are mandatory. |
| Redmi Pad Pro | Tablet | HyperOS (verify) | Same HyperOS behavior expected. |
| Linux desktop | Desktop | Arch Linux / niri (Wayland) / SDDM / Noctalia shell | Tiling compositor, Noctalia handles tray + lock screen. |

### Verified on device (Poco X7 Pro)

| Check | Result |
| --- | --- |
| Boot receiver invoked on `BOOT_COMPLETED` | pass |
| Screen-on trigger (`ACTION_SCREEN_ON`) | pass |
| Unlock trigger (`ACTION_USER_PRESENT`) | pass |
| Cooldown suppresses repeats | pass (50 s elapsed vs 15 min cooldown → skipped) |
| Nudge notification, correct title and body | pass |
| Persistent foreground notification (`specialUse`) | pass |
| Full-screen intent shows the app **over the lock screen** | pass |
| In-app banner, and "Got it" returns to the previous screen | pass |
| Autostart deep link opens the MIUI Autostart manager | pass |
| HyperOS detection | pass (after the fix noted below) |

Still to verify by hand: a **real reboot** (the shell cannot spoof `BOOT_COMPLETED`) and the "still works after 24 hours" criterion.

### Device-testing notes

- HyperOS blocks `adb install` with `INSTALL_FAILED_USER_RESTRICTED` until either "Install via USB" is enabled (needs a Mi account) or `adb shell settings put global adb_install_need_confirm 0` is set.
- Native logs are tagged `Nudge`; follow the whole chain with `adb logcat -s Nudge`.
- `POST_NOTIFICATIONS` is a runtime grant. The app requests it on launch and Settings has a button too. Re-check on a genuinely fresh install.
- The nudge decision exists twice: `NudgeGate` in Dart and `NudgeEngine` in Kotlin. On Android native is authoritative because the service has to work with Flutter dead, so `presentNudge` there only syncs the cooldown timestamp and does not post again (that would double-alert).
- HyperOS detection uses `Build.MANUFACTURER`/`Build.BRAND` plus the `com.miui.securitycenter` package. Do not reach for `System.getProperty("ro.mi.*")` — Android build properties are not Java system properties.

### Nudge tier per device

| Device | Tier 1 (notification) | Tier 2 (app to front) |
| --- | --- | --- |
| Poco X7 Pro | Verified working | Verified working — app appears over the lock screen |
| Redmi Pad Pro | Reliable with Autostart + battery exemptions | Possible with full-screen intent + all exemptions |
| Linux/niri | Reliable (desktop notification + tray) | Partial — notification click opens app, direct focus marked urgent |

### Backend hosting

VPS with Caddy (or Nginx) for HTTPS reverse proxy. Deploy the Go + Fiber service behind it.

### Screen locker on Linux

Noctalia shell (full desktop shell for niri). Uses the standard Wayland `ext-session-lock-v1` protocol. Listens for logind `Lock`/`Unlock` D-Bus signals and calls `SetLockedHint`. Nudge should listen on the same logind `Unlock` signal — this is the universal unlock trigger regardless of which locker is used.

### Android AlarmManager fallback

Confirmed: add `AlarmManager.setExactAndAllowWhileIdle` fallback to re-fire the nudge if HyperOS kills the foreground service. Store next alarm time in SharedPreferences.