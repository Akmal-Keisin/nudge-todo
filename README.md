# Nudge

A single-user todo list for Android and Linux whose one defining trait is that
**it shows itself** — the list appears when you start or unlock a device, so
pending tasks can't quietly slip past you.

Todos are single lines. Checked items go to an archive and are deleted after 14
days. A small Go backend keeps every device in sync, but the app is fully usable
with no server at all.

---

## What it does

**Todos.** One screen. Type and press Enter to add; tap a row to expand it for
Edit and Delete — there is no separate detail view. Checking an item archives it
with an "Archived · Undo" snackbar, and undo restores it under its original id.

**Nudge.** At boot, login and unlock the app raises a notification, and on
Android it brings the list itself up over the lock screen. A 15-minute cooldown
stops repeated unlocks from nagging you; quiet hours can silence it entirely.
The list is cached, so a nudge works with the network down.

**Sync.** The server is the source of truth. Leave the server URL empty in
Settings and everything stays on the device; fill it in and the app syncs, keeps
the cached list for offline reading, and shows a banner (with writes disabled)
when the server is unreachable.

**Appearance.** Settings offers six curated palettes — Ocean, Sunset, Forest,
Grape, Rose and Midnight — each with light and dark variants, plus a System /
Light / Dark selector. The choice applies instantly to the whole app and is
remembered on the next launch.

**Layout.** The UI adapts to the window instead of stretching the phone layout.
Below 600 px it keeps the AppBar tabs and bottom composer. From 600 px the
filters move into the content column and the composer becomes a floating card.
From 840 px a persistent rail (Active, Archive, Settings) replaces the AppBar,
and Settings opens beside the list; at 1200 px and wider the rail shows labels.
Settings uses two columns when its pane is at least 900 px wide.
`Ctrl+1` / `Ctrl+2` switch lists, `Ctrl+,` opens Settings, and the Linux window
opens at 1080×720.

---

## Targets

| Device | Platform | State |
| --- | --- | --- |
| Poco X7 Pro (2412DPC0AG) | HyperOS 3.0 / Android 16 | Nudge verified end to end, including full-screen intent over the lock screen |
| Redmi Pad Pro | HyperOS | Not yet tested |
| Desktop | Arch Linux / niri (Wayland) / SDDM / Noctalia shell | Nudge verified: autostart, tray, unlock and resume triggers |

Android needs a few one-time permission grants, because HyperOS is aggressive
about killing background work. The in-app Settings screen walks you through them.

---

## Requirements

| | |
| --- | --- |
| Flutter | 3.47.7 stable (developed and tested on this) |
| Go | 1.27+ — only for the backend |
| Linux build | `clang cmake ninja pkgconf gtk3 libayatana-appindicator libsecret` |
| Android build | Android SDK 36; on HyperOS, "Install via USB" or `adb_install_need_confirm` |

---

## Quick start — the app, no server

```bash
git clone <your-repo> nudge && cd nudge
flutter pub get

flutter run -d linux          # desktop
flutter run -d <device-id>    # Android, with USB debugging on
```

Todos are stored locally and the app works immediately. Open **Settings** to
tune the nudge, then add a todo and press the power button on the phone to see
it work.

Release builds:

```bash
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
flutter build linux --release    # build/linux/x64/release/bundle/nudge
```

---

## Installing on Linux (Arch)

This project is not packaged for Arch: there is no `PKGBUILD` or `make install`
target in the repo. The unrelated `nudge` / `nudge-bin` AUR packages are a
different app. `flutter build linux --release` produces a self-contained
bundle in `build/linux/x64/release/bundle/` (use `arm64` on ARM), so running
it in place is enough for development. Installing means copying that bundle
somewhere permanent and adding a launcher; nothing is registered with pacman.

### Install

```bash
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 libayatana-appindicator libsecret
flutter pub get
flutter build linux --release

install -d ~/.local/opt/nudge ~/.local/bin
cp -a build/linux/x64/release/bundle/. ~/.local/opt/nudge/
ln -sf ~/.local/opt/nudge/nudge ~/.local/bin/nudge

mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/com.nudge.nudge.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Nudge
Exec=$HOME/.local/opt/nudge/nudge
Icon=$HOME/.local/opt/nudge/data/flutter_assets/assets/app_icon.png
Terminal=false
Categories=Utility;
EOF
command -v update-desktop-database >/dev/null && update-desktop-database ~/.local/share/applications
```

The desktop entry uses absolute paths, so it works whether or not
`~/.local/bin` is on `PATH`.

#### Fish shell

Fish has no here-documents, so skip the `cat > ... <<EOF` part. The `install`,
`cp`, `ln`, `pkill` and `secret-tool` commands work unchanged. Create the
desktop entry with:

```fish
mkdir -p ~/.local/share/applications
printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Nudge' \
  "Exec=$HOME/.local/opt/nudge/nudge" \
  "Icon=$HOME/.local/opt/nudge/data/flutter_assets/assets/app_icon.png" \
  'Terminal=false' \
  'Categories=Utility;' \
  > ~/.local/share/applications/com.nudge.nudge.desktop

if command -q update-desktop-database
    update-desktop-database ~/.local/share/applications
end
```

In the uninstall block, replace the tray-icon `rm -rf .../nudge` line with:

```fish
if set -q TMPDIR
    rm -rf "$TMPDIR/nudge"
else
    rm -rf /tmp/nudge
end
```

To upgrade, quit Nudge, remove the old bundle with
`rm -rf ~/.local/opt/nudge`, then repeat the copy step. The launcher and symlink
stay valid; todos and settings stay in `~/.local/share/com.nudge.nudge`.

Enable **Start at login** after copying the bundle into place, not while running
from `build/`: the app writes the resolved executable path into
`~/.config/autostart/Nudge.desktop`, which would otherwise point at the build
directory.

### Uninstall

Quit from the tray menu first — the window's close button only hides it. If no
tray host is running, stop it with `pkill -x nudge`. Then:

```bash
rm -f ~/.config/autostart/Nudge.desktop
rm -rf ~/.local/opt/nudge
rm -f ~/.local/bin/nudge
rm -f ~/.local/share/applications/com.nudge.nudge.desktop
rm -rf ~/.local/share/com.nudge.nudge     # todos, settings, theme
rm -rf "${TMPDIR:-/tmp}/nudge"             # cached tray icon
secret-tool clear account com.nudge.nudge.secureStorage  # API token, if set
```

The last three commands erase local state — skip them to keep the list and
settings across a reinstall. Todos and preferences live in
`~/.local/share/com.nudge.nudge/shared_preferences.json`; the API token is in
the keyring under account `com.nudge.nudge.secureStorage`.

If you only ever ran the bundle from `build/`, deleting `build/` is the entire
uninstall.

---

## Adding the backend

```bash
cd server
API_TOKEN=devsecret go run ./cmd/nudge
```

It listens on `:8080`, creates `nudge.db` next to you, runs its migrations, and
starts a job that prunes archived todos every hour. It refuses to start without
`API_TOKEN`.

Port taken? The error is `listen tcp4 :8080: bind: address already in use` —
pick another with `PORT=8123 API_TOKEN=devsecret go run ./cmd/nudge`, and use
that port in the app below.

Then, in the app: **Settings → Server**

| Field | Value |
| --- | --- |
| Server URL | `http://127.0.0.1` (no `/api/v1` — the app appends it) |
| API token | whatever you set above |

Press **Test connection**. *Connected.* means the server was reached **and** the
token was accepted. Press **Save** and the app switches from local to synced.

To prove the client and the contract agree, rather than just curl the endpoint:

```bash
cd server && API_TOKEN=devsecret go run ./cmd/nudge &   # in one terminal
dart run tool/smoke_remote.dart http://127.0.0.1:8080 devsecret   # in another
```

That drives the real repository through 17 checks against a live server.

---

## Deploying

See **[server/deploy/README.md](server/deploy/README.md)** for the full runbook,
with two paths:

- **[Docker Compose](server/deploy/docker.md)** — Caddy + the app, one `.env`
  file, certificate handled for you.
- **[Bare metal](server/deploy/bare-metal.md)** — a static binary under systemd
  with sandboxing, plus nginx and Certbot. No container runtime.

Both put only the reverse proxy on the internet. The app itself is never
published — Docker keeps it on an internal network, and the systemd unit binds
to loopback.

---

## Configuration

Everything is environment-driven. The client is configured from the in-app
Settings screen.

| Variable | Default | Notes |
| --- | --- | --- |
| `API_TOKEN` | *required* | The server will not start without it. |
| `PORT` | `8080` | |
| `BIND_HOST` | *all interfaces* | Set `127.0.0.1` when a proxy on the same host is all that should reach it. |
| `DB_PATH` | `./nudge.db` | |
| `ARCHIVE_RETENTION_DAYS` | `14` | Archived todos are deleted after this. |
| `RATE_LIMIT_PER_MINUTE` | `60` | Per token. |
| `IP_RATE_LIMIT_PER_MINUTE` | `120` | Per client address, checked before auth. |
| `BODY_LIMIT_BYTES` | `4096` | |
| `TRUSTED_PROXIES` | *none* | Comma-separated proxy IPs/CIDRs whose `X-Forwarded-For` is trusted. Set this to `127.0.0.1` when behind nginx or Caddy on the same host, or every request is rate-limited as one client. |
| `PRUNE_INTERVAL` | `1h` | How often the retention job runs. |

---

## Repository layout

```
lib/
  main.dart
  app/                    MaterialApp
    theme/                theme catalog, component themes, theme providers
  core/
    errors/               typed AppFailure, so the UI never shows a raw exception
    network/              shared dio client
    platform/             NudgePlatform interface + android / linux / no-op
    storage/              shared preferences
  features/
    todos/                domain, data, application, presentation
    nudge/                nudge config, cooldown gate, Settings screen
    settings/             server URL and token, shared settings section
    appearance/           theme id + mode, persistence, theme picker
server/                   Go backend, Fiber v3 + SQLite + goose
  cmd/nudge/              entrypoint
  internal/               api, config, database, middleware, server, todo
  openapi.yaml            the API contract — change it deliberately
  deploy/                 deployment guides, compose file, systemd unit
tool/smoke_remote.dart    drives the client against a live server
test/                     mirrors lib/; 9 files, 55 tests
docs/                     the plan and platform-specific notes
```

Feature folders each carry the same four layers. Dependencies point inward:
presentation → application → domain, and data implements domain. Widgets watch
providers and never call dio, preferences or platform channels.

---

## Development

The three checks that gate every change:

```bash
dart format .
flutter analyze        # zero issues
flutter test

cd server
gofmt -l . && go vet ./... && go test ./...
```

`AGENTS.md` has the conventions the code follows, and is worth reading before
touching either side.

Platform-specific behaviour is all behind `NudgePlatform` in
`lib/core/platform`, so `defaultTargetPlatform` is read in exactly one place.
Native Android code lives in `android/app/src/main/kotlin/com/nudge/nudge/`;
follow the trigger chain with `adb logcat -s Nudge`.

---

## Platform notes

**Android (HyperOS).** `BOOT_COMPLETED` is silently dropped until the user
enables the Xiaomi-specific Autostart permission, and there are three separate
battery settings to exempt the app from. The Settings screen deep-links into
each one. `POST_NOTIFICATIONS` is requested on first launch; without it every
notification is silently discarded.

**Linux (niri).** niri has no built-in tray or screen locker; Noctalia provides
both. Nudge listens on logind's `Unlock` and `PrepareForSleep` D-Bus signals,
which is the same thing Noctalia does. A window raised from the background is
marked urgent rather than focused, so the notification — not the window — is the
reliable Tier 2 path.

**Timestamps** are UTC and microsecond-precision end to end, so a create response
matches a later read byte for byte.

---

## Documentation

| File | What it holds |
| --- | --- |
| [docs/plan.md](docs/plan.md) | The full specification: requirements, the API contract, the development plan, and a live status table |
| [docs/nudge-platform-notes.md](docs/nudge-platform-notes.md) | Nudge implementation details per platform |
| [server/README.md](server/README.md) | Backend architecture and local development |
| [server/openapi.yaml](server/openapi.yaml) | The API contract, source of truth for client and server |
| [server/deploy/](server/deploy/README.md) | Deployment guides |
| [AGENTS.md](AGENTS.md) | Conventions for working in this codebase |

---

## Status

Phase 0 (setup), 0.5 (nudge spike), 1 (client) and 2 (backend and sync) are
done and verified. What remains:

- End-to-end on the Redmi Pad Pro, and against a real deployed server
- A real reboot and a 24-hour survival test on Android — the exit criteria for
  the nudge spike, which only a person can do

[docs/plan.md](docs/plan.md) carries the detailed status table.
