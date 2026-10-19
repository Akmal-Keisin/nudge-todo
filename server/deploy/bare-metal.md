# Deploying Nudge without Docker

A single static Go binary under systemd, with nginx terminating TLS on the same
host. No container runtime, no orchestrator.

For the container route — which uses Caddy — see [docker.md](docker.md).

---

## 0. What you need

| Thing | Notes |
| --- | --- |
| VPS | 1 vCPU / 512 MB RAM is enough. |
| Domain | e.g. `nudge.example.com`, with an A record you can edit. |
| SSH access | `ssh you@203.0.113.10` |
| Go 1.27.2+ | Only on the machine you *build* on — not necessarily the server. |

The binary is built with `CGO_ENABLED=0` (the SQLite driver is pure Go), so it
is statically linked and runs on any glibc or musl x86_64 Linux without
dependencies. nginx and Certbot come from the distribution packages; there is
nothing else to install.

---

## 1. Point DNS at the box, first

Certbot proves domain ownership with an HTTP-01 challenge on port 80. If the
name does not resolve here yet, certificate issuance fails.

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
only, so nginx is the only thing that can reach it — even if this firewall were
misconfigured, the API would not be exposed directly (which would also mean no
TLS, and the token travelling in cleartext).

Port 80 must stay open after issuance: Certbot renews the certificate with the
same HTTP-01 challenge.

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
test -x /opt/nudge/nudge && echo "binary installed"
```

The binary itself is owned by root and not writable by the service, so a
compromised process cannot replace its own executable. It takes no command-line
flags; all configuration comes from the environment file below.

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

# nginx is the only client. Trusting its loopback address makes the app use
# X-Forwarded-For for the client IP, so the per-IP rate limit and the access log
# see the real device instead of 127.0.0.1 for every request.
TRUSTED_PROXIES=127.0.0.1

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

Sanity check locally, before nginx is involved:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/health   # 200
```

---

## 8. Install nginx and Certbot

```bash
sudo apt update
sudo apt install -y nginx certbot
nginx -v
certbot --version
```

The distribution packages are enough; no third-party repository is needed.

---

## 9. Configure nginx and issue the certificate

nginx starts on HTTP only, so Certbot can answer the challenge from the webroot.
Once the certificate exists, the same file gains the HTTPS server block.

Create the webroot and `/etc/nginx/sites-available/nudge`:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name nudge.example.com;

    # Certbot writes the HTTP-01 challenge here. This must stay reachable on
    # port 80 for renewals too.
    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

Enable it, replacing the stock default site:

```bash
sudo install -d -o root -g root -m 0755 /var/www/certbot
sudo ln -sf /etc/nginx/sites-available/nudge /etc/nginx/sites-enabled/nudge
sudo rm -f /etc/nginx/sites-enabled/default

sudo nginx -t
sudo systemctl reload nginx
sudo systemctl status nginx --no-pager
```

Issue the certificate:

```bash
sudo certbot certonly --webroot -w /var/www/certbot \
  -d nudge.example.com \
  --email you@example.com --agree-tos --no-eff-email
```

Certbot prints `Successfully received certificate` and writes
`/etc/letsencrypt/live/nudge.example.com/`. Confirm:

```bash
sudo certbot certificates
```

Now replace `/etc/nginx/sites-available/nudge` with the full configuration:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name nudge.example.com;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name nudge.example.com;

    ssl_certificate     /etc/letsencrypt/live/nudge.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/nudge.example.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;

    # Match the app's BODY_LIMIT_BYTES (4096 is the default). Change both if the
    # limit ever moves.
    client_max_body_size 4k;

    # The clients are native apps, so there is no browser and no CORS layer is
    # needed. There are no websockets either.
    location / {
        proxy_pass http://127.0.0.1:8080;

        proxy_http_version 1.1;
        proxy_set_header Host $host;

        # Overwrite, rather than append to, any client-supplied header: a
        # device must not be able to dodge the per-IP rate limit by sending a
        # forged X-Forwarded-For.
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 15s;
    }
}
```

Validate, then load it:

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo systemctl status nginx --no-pager
```

The certificate is valid for 90 days. Ubuntu's Certbot package installs
`certbot.timer`, which checks twice a day and renews within 30 days of expiry.
Because the webroot authenticator does not touch nginx, reload it after a
renewal with a deploy hook:

```bash
sudo install -d -o root -g root -m 0755 /etc/letsencrypt/renewal-hooks/deploy
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh >/dev/null <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
sudo chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh

sudo certbot renew --dry-run
systemctl list-timers 'certbot*'
```

nginx starts independently of `nudge`, so after a reboot it may briefly return
`502` until the app is up. That resolves on its own; to order them strictly, add
a drop-in with `sudo systemctl edit nginx`:

```ini
[Unit]
After=nudge.service
```

Watch the certificate being issued:

```bash
sudo journalctl -u certbot -f
```

---

## 10. Verify

From your **laptop** — this also proves DNS, the firewall and nginx:

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
echo | openssl s_client -connect nudge.example.com:443 \
  -servername nudge.example.com 2>/dev/null \
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
sudo journalctl -u nginx -f
sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log
sudo journalctl -u certbot --since today   # ACME renewals
```

The nginx package ships `/etc/logrotate.d/nginx`, so its access and error logs
rotate on their own. To keep the journal from growing without bound:

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

```bash
echo | openssl s_client -connect nudge.example.com:443 \
  -servername nudge.example.com 2>/dev/null \
  | openssl x509 -noout -dates

sudo certbot certificates
sudo certbot renew --dry-run
sudo journalctl -u certbot | grep -i renew | tail
```

Certbot's timer runs twice a day and renews 30 days before expiry; the deploy
hook reloads nginx so the new certificate is actually served.

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
| Certbot fails the challenge | DNS not pointed here, port 80 blocked, or `/.well-known/acme-challenge/` not routed. `dig +short`, `ufw status`, then `sudo certbot renew --dry-run`. |
| `nginx: [emerg] cannot load certificate` | The certificate has not been issued yet, or the domain in the path differs. `sudo certbot certificates`. |
| `502 Bad Gateway` from nginx | The app is down. `systemctl status nudge`, `journalctl -u nudge`, then `tail /var/log/nginx/error.log`. |
| `502` for a few seconds after boot | nginx started before the app. Harmless; see step 9 for strict ordering. |
| Every request rate-limited as one client; nginx logs show `127.0.0.1` | `TRUSTED_PROXIES` is missing from `nudge.env`, so `X-Forwarded-For` is ignored. Add `TRUSTED_PROXIES=127.0.0.1` and restart. |
| `413 Request Entity Too Large` from nginx | The body exceeds `client_max_body_size`; it should match `BODY_LIMIT_BYTES` (4096 by default). |
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
sudo nginx -t
sudo systemctl status nginx --no-pager
sudo ss -lntp | grep -E '8080|80|443'
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

sudo rm -f /etc/nginx/sites-enabled/nudge /etc/nginx/sites-available/nudge
sudo nginx -t && sudo systemctl reload nginx
sudo certbot delete --cert-name nudge.example.com --non-interactive
sudo rm -rf /var/www/certbot
sudo systemctl disable --now nginx
sudo apt remove -y nginx certbot
sudo apt autoremove -y

sudo userdel nudge
sudo ufw delete allow 80/tcp
sudo ufw delete allow 443/tcp
```
