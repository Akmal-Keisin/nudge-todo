# Deploying Nudge without Docker

A single static Go binary under systemd, with Caddy terminating TLS on the same
host. No container runtime, no orchestrator — about 15 MB of software.

For the container route see [docker.md](docker.md).

---

## 0. What you need

| Thing | Notes |
| --- | --- |
| VPS | 1 vCPU / 512 MB RAM is enough. |
| Domain | e.g. `nudge.example.com`, with an A record you can edit. |
| SSH access | `ssh you@203.0.113.10` |
| Go 1.27+ | Only on the machine you *build* on — not necessarily the server. |

The binary is built with `CGO_ENABLED=0` (the SQLite driver is pure Go), so it
is statically linked and runs on any glibc or musl x86_64 Linux without
dependencies.

---

## 1. Point DNS at the box, first

Caddy proves domain ownership with an ACME challenge on port 80. If the name does
not resolve here yet, certificate issuance fails.

```
Type   Name     Value
A      nudge    203.0.113.10
AAAA   nudge    2001:db8::10      # only if the box has IPv6
```

```bash
dig +short nudge.example.com     # must print your server's IP
```

Do not continue until it does.

---

## 2. Open the firewall

```bash
sudo apt update
sudo apt install -y ufw

sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

Port 8080 is deliberately **not** opened. The service will bind to loopback
only, so Caddy is the only thing that can reach it — even if this firewall were
misconfigured, the API would not be exposed directly (which would also mean no
TLS, and the token travelling in cleartext).

If your provider has its own cloud firewall, open 80 and 443 there too.

---

## 3. Build the binary

### Option A — build on your workstation (recommended)

Keeps a Go toolchain off the server entirely.

```bash
# In the project root, on your machine
cd server
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags='-s -w' -o /tmp/nudge ./cmd/nudge

file /tmp/nudge
# ELF 64-bit LSB executable, x86-64, statically linked, stripped

scp /tmp/nudge you@203.0.113.10:/tmp/nudge
```

### Option B — build on the server

```bash
sudo apt install -y golang-go        # or use the official tarball for a newer Go
cd /opt/nudge/server                 # after copying the source
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /tmp/nudge ./cmd/nudge
```

Confirm the architecture matches before copying — `uname -m` on the server
should say `x86_64`. If the VPS is ARM (Ampere, Graviton), build with
`GOARCH=arm64`.

---

## 4. Create the service account and directories

The service runs unprivileged, with no shell and no home of its own.

```bash
sudo useradd --system --home /opt/nudge \
  --shell /usr/sbin/nologin --comment "Nudge backend" nudge

sudo install -d -o nudge -g nudge -m 0755 /opt/nudge
sudo install -d -o root  -g nudge -m 0750 /etc/nudge
sudo install -d -o nudge -g nudge -m 0750 /var/lib/nudge
```

| Path | Holds | Owner |
| --- | --- | --- |
| `/opt/nudge` | the binary | `nudge` |
| `/etc/nudge` | the environment file (secrets) | `root`, group-readable |
| `/var/lib/nudge` | the SQLite database | `nudge` |

---

## 5. Install the binary

```bash
sudo install -o root -g root -m 0755 /tmp/nudge /opt/nudge/nudge
/opt/nudge/nudge --help 2>&1 | head -2 || true    # exists and is executable
```

The binary itself is owned by root and not writable by the service, so a
compromised process cannot replace its own executable.

---

## 6. Configure

Generate a token:

```bash
openssl rand -base64 32
```

Create `/etc/nudge/nudge.env`:

```ini
# The bearer token every device sends.
API_TOKEN=<paste the generated token>

# Where the database lives. This is the only path the service may write.
DB_PATH=/var/lib/nudge/nudge.db

PORT=8080

# Optional.
ARCHIVE_RETENTION_DAYS=14
RATE_LIMIT_PER_MINUTE=60
IP_RATE_LIMIT_PER_MINUTE=120
```

Lock it down. The unit reads this as root, so the service user never needs to
read it itself:

```bash
sudo chown root:nudge /etc/nudge/nudge.env
sudo chmod 0640 /etc/nudge/nudge.env
```

> `BIND_HOST` is not set here on purpose — the unit already defaults it to
> `127.0.0.1`. Add `BIND_HOST=` to this file if you ever need to override that.

---

## 7. Install the systemd unit

```bash
sudo install -o root -g root -m 0644 nudge.service /etc/systemd/system/nudge.service
sudo systemctl daemon-reload
sudo systemctl enable --now nudge
systemctl status nudge --no-pager
```

Expect `Active: active (running)`. If not, jump to troubleshooting — the journal
will say why.

Check it is listening on loopback only:

```bash
ss -lntp | grep 8080
# LISTEN 0 4096 127.0.0.1:8080 ...
```

If it shows `0.0.0.0:8080`, `BIND_HOST` did not take effect.

Sanity check locally, before Caddy is involved:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health   # 200
```

---

## 8. Install Caddy

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg

curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  | sudo tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null

sudo apt update
sudo apt install -y caddy
caddy version
```

---

## 9. Configure Caddy

Replace `/etc/caddy/Caddyfile` with the following, editing the domain:

```caddyfile
nudge.example.com {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8080

	log {
		output file /var/log/caddy/nudge.log
		format json
	}
}
```

Caddy's package ships a `caddy` user. For the file log to work, that user needs
the directory:

```bash
sudo install -d -o caddy -g caddy -m 0755 /var/log/caddy
```

Validate, then load it:

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo systemctl status caddy --no-pager
```

The Caddy unit is `After=` nothing in particular, so if it starts before `nudge`
it may briefly return `502`. That resolves on its own; add
`After=nudge.service` to `/etc/systemd/system/caddy.service.d/override.conf` if
you want it ordered strictly.

Watch the certificate being issued:

```bash
sudo journalctl -u caddy -f
```

You want `certificate obtained successfully` and `serving initial configuration`.

---

## 10. Verify

From your **laptop** — this also proves DNS and the firewall:

```bash
BASE=https://nudge.example.com
TOKEN=<your token>

curl -s -o /dev/null -w '%{http_code}\n' "$BASE/api/v1/health"
# 200

curl -s -o /dev/null -w '%{http_code}\n' "$BASE/api/v1/todos"
# 401  (no token)

curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/v1/todos"
# {"data":[]}

curl -s -X POST -H "Authorization: Bearer $TOKEN" \
     -H 'Content-Type: application/json' \
     -d '{"text":"Deployed it"}' "$BASE/api/v1/todos"
# {"data":{"id":"...","text":"Deployed it",...}}
```

Also confirm the certificate is real, not self-signed:

```bash
echo | openssl s_client -connect nudge.example.com:443 2>/dev/null \
  | openssl x509 -noout -issuer -dates
# issuer=C=US, O=Let's Encrypt, ...
```

---

## 11. Point the app at it

On each device:

1. Nudge → **Settings** → **Server**
2. **Server URL**: `https://nudge.example.com` (no `/api/v1` — the app appends it)
3. **API token**: the same token
4. **Test connection** → *Connected.*
5. **Save**

---

## 12. Day-2 operations

### Logs

```bash
sudo journalctl -u nudge -f            # structured JSON, one line per event
sudo journalctl -u nudge --since today
sudo journalctl -u caddy -f            # TLS, ACME renewals, access log
tail -f /var/log/caddy/nudge.log
```

To keep the journal from growing without bound:

```bash
sudo sed -i 's/^#SystemMaxUse=.*/SystemMaxUse=200M/' /etc/systemd/journald.conf
sudo systemctl restart systemd-journald
```

### Upgrading

```bash
# On your workstation
cd server
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -trimpath -ldflags='-s -w' -o /tmp/nudge ./cmd/nudge
scp /tmp/nudge you@203.0.113.10:/tmp/nudge

# On the server
sudo systemctl stop nudge
sudo install -o root -g root -m 0755 /tmp/nudge /opt/nudge/nudge
sudo systemctl start nudge
sudo journalctl -u nudge -n 20 --no-pager
```

Migrations run automatically at startup, so there is no separate step. The
service is down for well under a second.

### Backups

Everything is one SQLite file in WAL mode. Copying it while the service writes
can lose recent commits, so either stop the service or let SQLite do it.

```bash
sudo apt install -y sqlite3
sudo install -d -o nudge -g nudge -m 0750 /var/backups/nudge
```

`/usr/local/bin/nudge-backup`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# .backup is safe to run against a live database.
sudo -u nudge sqlite3 /var/lib/nudge/nudge.db \
  ".backup '/var/backups/nudge/nudge-$(date +%F).db'"

find /var/backups/nudge -name 'nudge-*.db' -mtime +14 -delete
```

```bash
sudo chmod +x /usr/local/bin/nudge-backup
sudo /usr/local/bin/nudge-backup
ls -la /var/backups/nudge/
```

Nightly at 03:30 via `/etc/cron.d/nudge-backup`:

```
30 3 * * * root /usr/local/bin/nudge-backup >> /var/log/nudge-backup.log 2>&1
```

Archived todos are deleted permanently after the retention window, so keep more
than one generation.

### Restoring

```bash
sudo systemctl stop nudge
sudo -u nudge cp /var/backups/nudge/nudge-2026-10-15.db /var/lib/nudge/nudge.db
sudo -u nudge rm -f /var/lib/nudge/nudge.db-wal /var/lib/nudge/nudge.db-shm
sudo systemctl start nudge
```

Removing the `-wal` and `-shm` files matters: a stale write-ahead log paired
with an older database will be replayed and corrupt it.

### Rotating the token

```bash
sudo editor /etc/nudge/nudge.env      # change API_TOKEN
sudo systemctl restart nudge
```

Then re-enter the token in Settings on every device. Until you do, those devices
get `401` and the app shows *"Token rejected."*

### Checking the certificate

Caddy renews automatically, 30 days before expiry.

```bash
echo | openssl s_client -connect nudge.example.com:443 2>/dev/null \
  | openssl x509 -noout -dates
sudo journalctl -u caddy | grep -i renew | tail
```

---

## 13. What the hardening actually does

`nudge.service` ships with a set of sandboxing directives. Worth knowing what
they buy you, and what they cost:

| Directive | Effect |
| --- | --- |
| `User=nudge` / `Group=nudge` | No privileges at all. |
| `NoNewPrivileges=true` | Cannot gain privileges via setuid binaries. |
| `ProtectSystem=strict` | The entire filesystem is read-only except `ReadWritePaths`. |
| `ReadWritePaths=/var/lib/nudge` | The one writable location. |
| `ProtectHome=true` | `/home`, `/root` and `/run/user` are invisible. |
| `PrivateTmp=true` | Its own `/tmp`; cannot read or race with other services'. |
| `PrivateDevices=true` | No access to raw devices. |
| `ProtectKernelTunables/Modules/ControlGroups` | Cannot touch kernel state. |
| `RestrictAddressFamilies=AF_INET AF_INET6` | No raw sockets, no netlink. |
| `RestrictNamespaces`, `RestrictSUIDSGID`, `LockPersonality` | Blocks common escalation paths. |
| `MemoryDenyWriteExecute=true` | Blocks JIT-style code injection. |
| `StateDirectory=nudge` | systemd creates and owns `/var/lib/nudge`. |

If you move the database somewhere else, you must add that path to
`ReadWritePaths` — `ProtectSystem=strict` will otherwise make the service fail to
start with a permission error. Check with:

```bash
sudo systemd-analyze security nudge.service
```

---

## 14. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| `Active: failed` right after start | `sudo journalctl -u nudge -n 50`. Usually a missing/invalid `API_TOKEN`, or `DB_PATH` outside `ReadWritePaths`. |
| `status=200/CHDIR` | `/opt/nudge` missing — redo step 4. |
| Service fails with `Read-only file system` | `DB_PATH` is not under `/var/lib/nudge`. Move it or extend `ReadWritePaths`. |
| `ss -lntp` shows `0.0.0.0:8080` | `BIND_HOST` overridden in `nudge.env`; remove it. |
| Caddy logs ACME failures | DNS not pointed here, or port 80 blocked. `dig +short`, `ufw status`. |
| `502 Bad Gateway` from Caddy | The app is down. `systemctl status nudge`, `journalctl -u nudge`. |
| `502` for a few seconds after boot | Caddy started before the app. Harmless; see step 9 for strict ordering. |
| App says *"Token rejected"* | Token mismatch between `nudge.env` and Settings. |
| App says *"Could not reach the server"* | Wrong URL, missing `https://`, or the device's network blocks it. |
| `curl` from outside times out | Cloud firewall still closed on 443. |
| `429` | Hit `RATE_LIMIT_PER_MINUTE` (per token) or `IP_RATE_LIMIT_PER_MINUTE` (per address). |
| Database corrupt after a restore | `-wal`/`-shm` leftovers. Delete them, as in the restore step. |

Useful:

```bash
sudo systemctl status nudge --no-pager
sudo journalctl -u nudge -n 100 --no-pager
sudo journalctl -u nudge -p err --since '1 hour ago'
sudo ss -lntp | grep -E '8080|443'
sudo -u nudge sqlite3 /var/lib/nudge/nudge.db '.tables'
sudo -u nudge sqlite3 /var/lib/nudge/nudge.db 'select count(*) from todos;'
```

---

## 15. Uninstalling

```bash
sudo systemctl disable --now nudge
sudo rm -f /etc/systemd/system/nudge.service
sudo systemctl daemon-reload

sudo rm -rf /opt/nudge /etc/nudge
# This deletes your todos. Back up first if there is any doubt.
sudo rm -rf /var/lib/nudge

sudo systemctl disable --now caddy
sudo apt remove -y caddy
sudo rm -rf /var/log/caddy /var/lib/caddy /etc/caddy

sudo userdel nudge
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
```
