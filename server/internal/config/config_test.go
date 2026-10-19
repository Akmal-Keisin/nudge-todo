package config

import (
	"strings"
	"testing"
	"time"
)

// clearEnv unsets every key Load reads, so a test never inherits the ambient
// environment.
func clearEnv(t *testing.T) {
	t.Helper()
	for _, key := range []string{
		"API_TOKEN", "PORT", "BIND_HOST", "DB_PATH",
		"ARCHIVE_RETENTION_DAYS", "RATE_LIMIT_PER_MINUTE",
		"IP_RATE_LIMIT_PER_MINUTE", "BODY_LIMIT_BYTES",
		"TRUSTED_PROXIES", "PRUNE_INTERVAL",
	} {
		t.Setenv(key, "")
	}
}

func TestLoadRequiresAPIToken(t *testing.T) {
	clearEnv(t)

	_, err := Load()
	if err == nil {
		t.Fatal("want an error when API_TOKEN is unset")
	}
	if !strings.Contains(err.Error(), "API_TOKEN") {
		t.Fatalf("error should name API_TOKEN, got %v", err)
	}
}

func TestLoadAppliesDefaults(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if cfg.Addr != ":8080" {
		t.Errorf("Addr: want :8080, got %q", cfg.Addr)
	}
	if cfg.DBPath != "nudge.db" {
		t.Errorf("DBPath: want nudge.db, got %q", cfg.DBPath)
	}
	if cfg.ArchiveRetentionDays != 14 {
		t.Errorf("retention: want 14, got %d", cfg.ArchiveRetentionDays)
	}
	if cfg.RateLimitPerMinute != 60 {
		t.Errorf("rate limit: want 60, got %d", cfg.RateLimitPerMinute)
	}
	if cfg.IPRateLimitPerMinute != 120 {
		t.Errorf("IP rate limit: want 120, got %d", cfg.IPRateLimitPerMinute)
	}
	if cfg.BodyLimitBytes != 4096 {
		t.Errorf("body limit: want 4096, got %d", cfg.BodyLimitBytes)
	}
	if cfg.PruneInterval != time.Hour {
		t.Errorf("prune interval: want 1h, got %s", cfg.PruneInterval)
	}
}

func TestBindHostRestrictsAddr(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")
	t.Setenv("BIND_HOST", "127.0.0.1")
	t.Setenv("PORT", "9999")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if cfg.Addr != "127.0.0.1:9999" {
		t.Fatalf("want 127.0.0.1:9999, got %q", cfg.Addr)
	}
}

func TestLoadReadsOverrides(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")
	t.Setenv("PORT", "9000")
	t.Setenv("DB_PATH", "/var/lib/nudge/nudge.db")
	t.Setenv("ARCHIVE_RETENTION_DAYS", "30")
	t.Setenv("RATE_LIMIT_PER_MINUTE", "5")
	t.Setenv("IP_RATE_LIMIT_PER_MINUTE", "7")
	t.Setenv("BODY_LIMIT_BYTES", "512")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	if cfg.Addr != ":9000" {
		t.Errorf("Addr: got %q", cfg.Addr)
	}
	if cfg.DBPath != "/var/lib/nudge/nudge.db" {
		t.Errorf("DBPath: got %q", cfg.DBPath)
	}
	if cfg.ArchiveRetentionDays != 30 {
		t.Errorf("retention: got %d", cfg.ArchiveRetentionDays)
	}
	if cfg.RateLimitPerMinute != 5 {
		t.Errorf("rate limit: got %d", cfg.RateLimitPerMinute)
	}
	if cfg.IPRateLimitPerMinute != 7 {
		t.Errorf("IP rate limit: got %d", cfg.IPRateLimitPerMinute)
	}
	if cfg.BodyLimitBytes != 512 {
		t.Errorf("body limit: got %d", cfg.BodyLimitBytes)
	}
}

func TestLoadRejectsNonNumericValues(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")
	t.Setenv("PORT", "not-a-port")

	if _, err := Load(); err == nil {
		t.Fatal("want an error for a non-numeric PORT")
	}
}

func TestLoadRejectsNonPositiveRetention(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")
	t.Setenv("ARCHIVE_RETENTION_DAYS", "0")

	if _, err := Load(); err == nil {
		t.Fatal("want an error for ARCHIVE_RETENTION_DAYS=0")
	}
}

func TestRetentionConvertsToDuration(t *testing.T) {
	cfg := Config{ArchiveRetentionDays: 14}
	if got := cfg.Retention().Hours(); got != 14*24 {
		t.Fatalf("want 336h, got %gh", got)
	}
}

func TestTrustedProxiesParseFromCommaSeparatedList(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")
	t.Setenv("TRUSTED_PROXIES", "127.0.0.1, 10.0.0.0/8 ,")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}

	want := []string{"127.0.0.1", "10.0.0.0/8"}
	if len(cfg.TrustedProxies) != len(want) {
		t.Fatalf("want %v, got %v", want, cfg.TrustedProxies)
	}
	for i, w := range want {
		if cfg.TrustedProxies[i] != w {
			t.Errorf("entry %d: want %q, got %q", i, w, cfg.TrustedProxies[i])
		}
	}
}

func TestTrustedProxiesEmptyByDefault(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if len(cfg.TrustedProxies) != 0 {
		t.Errorf("want no trusted proxies, got %v", cfg.TrustedProxies)
	}
}

func TestPruneIntervalOverrideAndValidation(t *testing.T) {
	clearEnv(t)
	t.Setenv("API_TOKEN", "secret")
	t.Setenv("PRUNE_INTERVAL", "15m")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if cfg.PruneInterval != 15*time.Minute {
		t.Errorf("want 15m, got %s", cfg.PruneInterval)
	}

	t.Setenv("PRUNE_INTERVAL", "not-a-duration")
	if _, err := Load(); err == nil {
		t.Fatal("want an error for a malformed PRUNE_INTERVAL")
	}

	t.Setenv("PRUNE_INTERVAL", "0s")
	if _, err := Load(); err == nil {
		t.Fatal("want an error for a non-positive PRUNE_INTERVAL")
	}
}
