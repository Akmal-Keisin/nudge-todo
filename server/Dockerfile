# Build stage. CGO is off because the SQLite driver is pure Go.
FROM golang:1.27-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/nudge ./cmd/nudge

# Runtime stage. No libc needed for a static binary.
FROM alpine:3.22

RUN adduser -D -u 10001 nudge

WORKDIR /app

COPY --from=build /out/nudge /app/nudge

# The SQLite file lives here; mount a volume to keep it across restarts.
RUN mkdir -p /data && chown nudge:nudge /data
VOLUME /data

USER nudge
EXPOSE 8080

ENV PORT=8080 \
    DB_PATH=/data/nudge.db \
    ARCHIVE_RETENTION_DAYS=14

ENTRYPOINT ["/app/nudge"]
