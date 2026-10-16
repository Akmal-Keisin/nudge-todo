# AGENTS.md
Project: Nudge, a Flutter todo app (Android + Linux). Read docs/plan.md first.

## Targets
- Android: Poco X7 Pro (2412DPC0AG) — HyperOS 3.0 / Android 16 (API 36); Redmi Pad Pro (HyperOS)
- Linux: Arch Linux, niri Wayland compositor, SDDM, Noctalia shell

## Rules
- Architecture: feature-first; layers presentation / application / domain / data.
- State: Riverpod only. setState only for local UI state.
- No logic in widgets. Widgets never call dio, prefs or platform channels.
- No dynamic. No ! without a comment explaining why.
- Use current Flutter APIs (no withOpacity, WillPopScope, MaterialStateProperty).
- Add dependencies only with `flutter pub add`, say why, and make sure they support Android and Linux.
- Every change: dart format, flutter analyze (zero issues), flutter test.
- Add or update tests with each feature.
- Keep changes small. Ask before changing architecture or the API contract.
- Do not edit android/ native code unless the task says so.

## Nudge platform notes
- niri: no built-in tray (use Noctalia/Waybar + SNI), Noctalia handles lock screen via ext-session-lock-v1. Listen on logind Unlock signal for unlock trigger. Window focus requires xdg-activation token; desktop notification fallback is the reliable Tier 2 path.
- HyperOS: BOOT_COMPLETED blocked without Autostart permission. Three battery exemption layers required. Use foregroundServiceType="specialUse". AlarmManager fallback for when the foreground service is killed. Onboarding must walk user through all three layers.
- All platform differences live behind `NudgePlatform` in `lib/core/platform`. `defaultTargetPlatform` is read only in `platform_providers.dart`.
- Never call `NudgePlatform.updateSnapshot` before `initialize()` resolves — the Linux notification manager throws if shown before init. Gate snapshot pushes behind the `_ready` future in `nudge_app.dart`.
- `updateSnapshot` is state sync only; `presentNudge` surfaces the nudge. Do not merge them or every list change re-notifies.
- On Android native is the authority: the service must nudge with Flutter dead, so `presentNudge` there only syncs the cooldown timestamp.
- `tray_manager` is imported via `package:tray_manager/legacy.dart` (the 0.5.x API). The new FFI API has no migration guide yet; the file carries a documented `deprecated_member_use` ignore.
- Android native code lives in `android/app/src/main/kotlin/com/nudge/nudge/`. Bridges: MethodChannel `com.nudge/nudge`, EventChannel `com.nudge/nudge_events`. Logs are tagged `Nudge` (`adb logcat -s Nudge`).
- HyperOS detection: use `Build.MANUFACTURER`/`Build.BRAND` + the `com.miui.securitycenter` package, not `System.getProperty("ro.mi.*")` (Android build props are not Java system properties).
- `adb install` on HyperOS needs "Install via USB" or `adb shell settings put global adb_install_need_confirm 0`.

## Build and verify
```bash
# Flutter app
dart format .
flutter analyze
flutter test
flutter build linux --release
flutter build apk --release

# Backend
cd server && gofmt -l . && go vet ./... && go test ./...
API_TOKEN=devsecret go run ./cmd/nudge

# Client against a real server (start the server first)
dart run tool/smoke_remote.dart http://127.0.0.1:8080 devsecret
```

## Client / server
- `server/openapi.yaml` is the contract. Change it deliberately, and only with the backend.
- The client picks local vs remote in one place: `todoRepositoryProvider` in `features/todos/application/todo_providers.dart`. An empty server URL means local-only.
- `CachingTodoRepository` keeps the backend the source of truth and falls back to the cached list when the network fails; writes are online-only and surface `AppFailure`. There is no offline write queue in v1.
- Repositories throw `AppFailure` from `core/errors`; controllers turn those into `AsyncError`, and the UI renders `failureMessage(...)` rather than a raw exception.
- The API token lives in `flutter_secure_storage`; the URL stays in shared preferences.