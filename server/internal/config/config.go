package config

import (
	"fmt"
	"net"
	"os"
	"strconv"
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
		PruneInterval:        defaultPruneInterval,
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
