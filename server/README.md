# Nudge server

The Go backend for the Nudge clients. Single user, REST/JSON, SQLite storage,
one shared bearer token. `openapi.yaml` is the contract and the source of truth
for the client.

Stack: **Go 1.27**, **Fiber v3**, **SQLite** via the pure-Go `modernc.org/sqlite`
driver (no cgo, so the Docker image is a static binary on Alpine), migrations
with **goose**, structured logs with `slog`.

## Layout

```
cmd/nudge/            entrypoint: config, database, wiring, prune job, shutdown
internal/
  api/                response envelope and error rendering
  config/             environment configuration
  database/           SQLite open plus embedded goose migrations
  middleware/         bearer auth, per-token rate limiting
  server/             builds the Fiber app from config + service
  todo/               domain, repository, service, handlers
openapi.yaml          the API contract
```

Layers run handler → service → repository. The service holds the rules (text
validation, the archived-edit restriction) and the repository is the only thing
that knows about SQL.

## Configuration

Every setting comes from the environment; see `.env.example`.

| Variable | Default | Notes |
| --- | --- | --- |
| `API_TOKEN` | *required* | Server refuses to start without it. |
| `PORT` | `8080` | |
| `DB_PATH` | `./nudge.db` | |
| `ARCHIVE_RETENTION_DAYS` | `14` | Pruned hourly and at startup. |
| `RATE_LIMIT_PER_MINUTE` | `60` | Per token; a burst of this size is allowed. |
| `IP_RATE_LIMIT_PER_MINUTE` | `120` | Per client address, checked before auth. |
| `BODY_LIMIT_BYTES` | `4096` | |

## Run locally

```bash
cd server
API_TOKEN=$(openssl rand -base64 32) go run ./cmd/nudge
```

Then:

```bash
TOKEN=...
curl -s localhost:8080/health
curl -s -H "Authorization: Bearer $TOKEN" localhost:8080/api/v1/todos
```

## Test

```bash
go vet ./...
go test ./...
```

The HTTP tests drive the real Fiber app against an in-memory SQLite database and
cover every endpoint, the response envelope, validation, idempotency, auth,
rate limiting and the retention rules.

## Docker

```bash
docker build -t nudge-server .
docker run -d --name nudge \
  -p 8080:8080 \
  -e API_TOKEN="$(openssl rand -base64 32)" \
  -v nudge-data:/data \
  nudge-server
```

## Deploying

See **[deploy/README.md](deploy/README.md)** for the full runbook (DNS, firewall,
Docker Compose or systemd, backups, upgrades, token rotation).

The short version, on a host with Docker:

```bash
cd deploy
cp .env.example .env      # set NUDGE_DOMAIN, ACME_EMAIL, API_TOKEN
docker compose up -d --build
```

Caddy obtains and renews the certificate over ACME, and the app is never
published directly — only Caddy can reach it.

CORS is not needed: the clients are native apps, not browsers.

## Notes

- The server is the source of truth. `GET /todos` returns everything; the list
  is expected to stay well under 1,000 rows, so there is no pagination.
- Writes are online-only and last-write-wins.
- Retention deletes archived rows past `ARCHIVE_RETENTION_DAYS`. `GET /todos`
  also hides expired rows, so a lagging prune job never exposes stale data.
- Timestamps are stored as Unix microseconds and serialised as RFC 3339 UTC.
