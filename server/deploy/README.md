# Deploying Nudge

The backend is one small service — a static Go binary with a SQLite file — plus
Caddy terminating TLS. Everything needed to run it on a single VPS lives in this
directory.

## Which guide?

| | [docker.md](docker.md) | [bare-metal.md](bare-metal.md) |
| --- | --- | --- |
| Runtime | Docker + Compose | systemd + static binary |
| Installed size | ~200 MB (engine + images) | ~15 MB |
| Setup | Copy `.env`, one command | A dozen commands, more moving parts |
| Upgrades | `docker compose up -d --build` | `scp` a binary, `systemctl restart` |
| Isolation | Container | systemd sandboxing (already configured) |
| Pick this if | You already run Docker, or want the least ceremony | You want the smallest footprint or dislike containers |

Both end at the same place: the API on `https://your-domain/api/v1`, with only
Caddy published to the internet.

## Files here

| File | Used by | Purpose |
| --- | --- | --- |
| `docker.md` | — | Step-by-step Docker deployment guide |
| `bare-metal.md` | — | Step-by-step no-Docker deployment guide |
| `docker-compose.yml` | Docker | App + Caddy, volumes, healthcheck, log rotation |
| `Caddyfile` | Docker | Reverse proxy; uses the `nudge` service hostname |
| `nudge.service` | Bare metal | systemd unit with sandboxing |
| `.env.example` | Docker | Template for `.env` (copy it, do not commit it) |

`bare-metal.md` embeds its Caddyfile and environment file inline, since on a host
you edit those in place under `/etc`.

## Before either path

1. **DNS first.** Point an `A` record at the box and confirm with
   `dig +short nudge.example.com`. Caddy's ACME challenge fails until this
   resolves, and that is the single most common way a first deployment stalls.
2. **Firewall.** Allow SSH, 80 and 443. Never open 8080 — Caddy reaches the app
   over an internal network (Docker) or loopback (bare metal).
3. **Token.** `openssl rand -base64 32`. This is the only thing protecting your
   data; it goes in the server's config and in Settings on each device.

## After deploying

Whichever path you took, the verification is the same:

```bash
BASE=https://nudge.example.com
TOKEN=<your token>

curl -s -o /dev/null -w '%{http_code}\n' "$BASE/api/v1/health"   # 200
curl -s -o /dev/null -w '%{http_code}\n' "$BASE/api/v1/todos"    # 401
curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/v1/todos"   # {"data":[]}
```

Then in the app: **Settings → Server**, enter the URL (no `/api/v1` suffix — the
app appends it) and the token, and press **Test connection**. *Connected.* means
it reached the server and the token was accepted.

To exercise the client code against the deployment rather than just curl:

```bash
dart run tool/smoke_remote.dart https://nudge.example.com <token>
```

That runs the same 17 checks CI-style against the live server, covering
idempotent retries, archive/restore, filters, edit, delete, and error mapping.
