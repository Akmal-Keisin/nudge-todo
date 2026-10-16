# Deploying Nudge with Docker

The whole backend is one small container plus Caddy for TLS. This guide assumes
a fresh Ubuntu 24.04 VPS with a public IP and root/sudo access.

For the no-Docker route see [bare-metal.md](bare-metal.md).

---

## 0. What you need

| Thing | Notes |
| --- | --- |
| VPS | 1 vCPU / 1 GB RAM is generous. The app idles at a few MB. |
| Domain | e.g. `nudge.example.com`. A subdomain of one you already own is ideal. |
| SSH access | `ssh you@203.0.113.10` |
| ~10 minutes | Most of it is Docker installing. |

---

## 1. Point DNS at the box, first

Do this **before** starting anything. Caddy validates the domain with an ACME
challenge on port 80, and it will fail if the name does not resolve here yet.

At your DNS provider:

```
Type   Name     Value
A      nudge    203.0.113.10
AAAA   nudge    2001:db8::10      # only if the box actually has IPv6
```

Wait, then check from the server itself:

```bash
dig +short nudge.example.com
# must print your server's IP
```

If that comes back empty, stop here. Nothing below will work.

---

## 2. Open the firewall

Only SSH, HTTP and HTTPS. The app's own port is never exposed — Caddy reaches it
over the internal compose network.

```bash
sudo apt update
sudo apt install -y ufw

sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

> If your provider has a separate cloud firewall (Hetzner, Oracle, AWS security
> groups), open 80 and 443 there too. Cloud firewalls sit in front of `ufw`.

---

## 3. Install Docker

```bash
sudo apt install -y ca-certificates curl gnupg

sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

sudo usermod -aG docker "$USER"    # then log out and back in
docker compose version             # must print v2.x
```

---

## 4. Get the code onto the server

Only `server/` is needed — the Flutter app is built on your own machine.

**If the repo has a remote:**

```bash
sudo mkdir -p /opt/nudge && sudo chown "$USER" /opt/nudge
git clone <your-repo-url> /opt/nudge
cd /opt/nudge/server/deploy
```

**If it does not**, copy just what is needed from your workstation:

```bash
# run this on your workstation, in the project root
rsync -av --delete \
  --exclude build --exclude .dart_tool --exclude '*.db*' \
  server/ you@203.0.113.10:/opt/nudge/server/

# then, back on the server
cd /opt/nudge/server/deploy
```

The compose file builds the image from `server/Dockerfile`, so the source has to
be present on the box.

---

## 5. Configure

```bash
cd /opt/nudge/server/deploy
cp .env.example .env
```

Generate a token and put it in `.env`:

```bash
openssl rand -base64 32
```

```ini
NUDGE_DOMAIN=nudge.example.com
ACME_EMAIL=you@example.com
API_TOKEN=<paste the generated token>
```

The token is the only thing protecting your data, so keep it out of chats,
screenshots and git. `.env` is already gitignored.

Check what compose resolved before starting:

```bash
docker compose config
```

---

## 6. Start it

```bash
docker compose up -d --build
```

Build takes a minute or two. Then watch Caddy get its certificate:

```bash
docker compose logs -f caddy
```

You want to see, roughly:

```
certificate obtained successfully  identifier=nudge.example.com
certificate installed properly in linux trusts
serving initial configuration
```

Press `Ctrl-C` to stop following; the containers keep running.

---

## 7. Verify

From your **laptop** (not the server — this also proves DNS and the firewall):

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

curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/v1/todos"
# the todo you just made
```

If all of that works, the backend is live.

---

## 8. Point the app at it

On each device:

1. Open Nudge → **Settings** → **Server**
2. **Server URL**: `https://nudge.example.com` (no `/api/v1` — the app appends it)
3. **API token**: paste the same token
4. Tap **Test connection** → should say *Connected.*
5. **Save**

"Connected." means it reached the server *and* the token was accepted. If it
says the token was rejected, or the server could not be reached, see
troubleshooting below.

---

## 9. Day-2 operations

### Logs

```bash
cd /opt/nudge/server/deploy
docker compose logs -f --tail=100 nudge     # JSON, one line per event
docker compose logs -f --tail=100 caddy
```

Both are capped at 3 × 10 MB, so they will not fill the disk.

### Upgrading

```bash
cd /opt/nudge
git pull                      # or re-run the rsync from step 4
cd server/deploy
docker compose up -d --build
```

Database migrations run automatically at startup. There is no separate step.

### Backups

Everything is one SQLite file in the `nudge-data` volume, running in WAL mode —
so a naive `cp` while it is writing can lose recent commits. Stop the app for the
copy, or use SQLite's own backup.

```bash
sudo mkdir -p /var/backups/nudge
```

`/usr/local/bin/nudge-backup`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/nudge/server/deploy

docker compose stop nudge >/dev/null
docker run --rm -v deploy_nudge-data:/data \
  -v /var/backups/nudge:/backup alpine \
  cp /data/nudge.db "/backup/nudge-$(date +%F).db"
docker compose start nudge >/dev/null

# keep 14 days
find /var/backups/nudge -name 'nudge-*.db' -mtime +14 -delete
```

```bash
sudo chmod +x /usr/local/bin/nudge-backup
sudo /usr/local/bin/nudge-backup        # run it once to check
```

Nightly at 03:30 via `/etc/cron.d/nudge-backup`:

```
30 3 * * * root /usr/local/bin/nudge-backup >> /var/log/nudge-backup.log 2>&1
```

> The volume name is `<project>_nudge-data`. `docker compose config` will show
> the real one if you renamed the directory. Confirm with `docker volume ls`.

Note the retention rule deletes archived todos after 14 days permanently, so
keep more than one backup generation.

### Restoring

```bash
cd /opt/nudge/server/deploy
docker compose stop nudge
docker run --rm -v deploy_nudge-data:/data -v /var/backups/nudge:/backup \
  alpine cp "/backup/nudge-2026-10-15.db" /data/nudge.db
docker compose start nudge
```

### Rotating the token

1. Edit `API_TOKEN` in `.env`
2. `docker compose up -d`
3. Re-enter it in Settings on every device

Until you do, those devices get `401` and the app shows *"Token rejected."*

### Checking the certificate

Caddy renews automatically, 30 days before expiry. To confirm:

```bash
echo | openssl s_client -connect nudge.example.com:443 2>/dev/null \
  | openssl x509 -noout -dates
```

---

## 10. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Caddy logs ACME failures | DNS not pointing here, or port 80 blocked. Check `dig +short` and `ufw status`. |
| `curl` from outside times out | Cloud firewall / security group still closed on 443. |
| `502` from Caddy | The app container is down or unhealthy: `docker compose ps`, then `docker compose logs nudge`. |
| App says *"Token rejected"* | `.env` token and the token in Settings differ. Rotate and re-enter. |
| App says *"Could not reach the server"* | Wrong URL, missing `https://`, or the device is on a network blocking it. Try `curl` from that same network. |
| `429` | Hit `RATE_LIMIT_PER_MINUTE` (per token) or `IP_RATE_LIMIT_PER_MINUTE` (per address). |
| Todos vanish after a redeploy | `DB_PATH` is not under `/data`, or the volume was recreated. Run `docker compose config` and check the volume. |
| Container restarts in a loop | `docker compose logs nudge`. Usually a bad `API_TOKEN` or an unbindable port. |

Useful:

```bash
docker compose ps                 # health and uptime
docker compose config             # what compose actually resolved
docker compose exec nudge ls -la /data
docker compose exec nudge wget -qO- http://127.0.0.1:8080/health
```

---

## 11. Uninstalling

```bash
cd /opt/nudge/server/deploy
docker compose down -v      # -v also deletes the database volume

docker image rm deploy-nudge:latest
sudo rm -rf /opt/nudge

# optional
sudo docker system prune -a
```

`down -v` is irreversible for your todos. Back up first if there is any doubt.
