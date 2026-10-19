package config

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config is the full runtime configuration, read from the environment.
type Config struct {
	// Addr is the listen address, e.g. ":8080" or "127.0.0.1:8080".
	Addr string
	// APIToken is the single bearer token clients must present. Required.
	APIToken string
	// DBPath is the SQLite file. Use ":memory:" in tests.
	DBPath string
	// ArchiveRetentionDays is how long archived todos are kept.
	ArchiveRetentionDays int
	// RateLimitPerMinute caps requests per token.
	RateLimitPerMinute int
	// IPRateLimitPerMinute caps requests per client address, ahead of auth, so
	// token guessing is bounded too.
	IPRateLimitPerMinute int
	// BodyLimitBytes caps request bodies.
	BodyLimitBytes int
	// PruneInterval is how often the retention job runs.
	PruneInterval time.Duration
	// TrustedProxies lists the addresses that may set X-Forwarded-For. Behind
	// Caddy this must name the proxy, or every request looks like it came from
	// the proxy and the per-IP rate limit collapses into one bucket.
	TrustedProxies []string
}

const (
	defaultPort               = 8080
	defaultDBPath             = "nudge.db"
	defaultRetentionDays      = 14
	defaultRateLimitPerMinute = 60
	defaultIPRateLimit        = 120
	defaultBodyLimitBytes     = 4 * 1024
	defaultPruneInterval      = time.Hour
)

// Load reads configuration from the environment, applying defaults.
// API_TOKEN has no default: the server refuses to start without it.
func Load() (Config, error) {
	port, err := envInt("PORT", defaultPort)
	if err != nil {
		return Config{}, err
	}
	retention, err := envInt("ARCHIVE_RETENTION_DAYS", defaultRetentionDays)
	if err != nil {
		return Config{}, err
	}
	rateLimit, err := envInt("RATE_LIMIT_PER_MINUTE", defaultRateLimitPerMinute)
	if err != nil {
		return Config{}, err
	}
	ipRateLimit, err := envInt("IP_RATE_LIMIT_PER_MINUTE", defaultIPRateLimit)
	if err != nil {
		return Config{}, err
	}
	bodyLimit, err := envInt("BODY_LIMIT_BYTES", defaultBodyLimitBytes)
	if err != nil {
		return Config{}, err
	}
	pruneInterval, err := envDuration("PRUNE_INTERVAL", defaultPruneInterval)
	if err != nil {
		return Config{}, err
	}

	token := os.Getenv("API_TOKEN")
	if token == "" {
		return Config{}, fmt.Errorf("API_TOKEN must be set")
	}
	if retention < 1 {
		return Config{}, fmt.Errorf("ARCHIVE_RETENTION_DAYS must be at least 1, got %d", retention)
	}

	return Config{
		// An empty host means every interface. Set BIND_HOST=127.0.0.1 when a
		// reverse proxy on the same host is the only thing that should reach it.
		Addr:                 net.JoinHostPort(envString("BIND_HOST", ""), strconv.Itoa(port)),
		APIToken:             token,
		DBPath:               envString("DB_PATH", defaultDBPath),
		ArchiveRetentionDays: retention,
		RateLimitPerMinute:   rateLimit,
		IPRateLimitPerMinute: ipRateLimit,
		BodyLimitBytes:       bodyLimit,
		PruneInterval:        pruneInterval,
		TrustedProxies:       envList("TRUSTED_PROXIES"),
	}, nil
}

// Retention is the age at which an archived todo becomes eligible for pruning.
func (c Config) Retention() time.Duration {
	return time.Duration(c.ArchiveRetentionDays) * 24 * time.Hour
}

func envString(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// envList reads a comma-separated environment variable into a slice, dropping
// empty entries.
func envList(key string) []string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return nil
	}
	var values []string
	for _, part := range strings.Split(raw, ",") {
		if part = strings.TrimSpace(part); part != "" {
			values = append(values, part)
		}
	}
	return values
}

func envInt(key string, fallback int) (int, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be an integer, got %q", key, raw)
	}
	return value, nil
}

// envDuration reads a Go duration string, e.g. "30m" or "1h".
func envDuration(key string, fallback time.Duration) (time.Duration, error) {
	raw := os.Getenv(key)
	if raw == "" {
		return fallback, nil
	}
	value, err := time.ParseDuration(raw)
	if err != nil {
		return 0, fmt.Errorf("%s must be a duration like 1h, got %q", key, raw)
	}
	if value <= 0 {
		return 0, fmt.Errorf("%s must be positive, got %q", key, raw)
	}
	return value, nil
}
