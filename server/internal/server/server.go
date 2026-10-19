package server

import (
	"log/slog"
	"runtime/debug"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/recover"

	"github.com/akmalkeisin/nudge/server/internal/api"
	"github.com/akmalkeisin/nudge/server/internal/config"
	"github.com/akmalkeisin/nudge/server/internal/middleware"
	"github.com/akmalkeisin/nudge/server/internal/todo"
)

// New builds the HTTP app: an unauthenticated /health plus the token-protected,
// rate-limited /api/v1 group.
func New(cfg config.Config, service *todo.Service, logger *slog.Logger) *fiber.App {
	fiberCfg := fiber.Config{
		BodyLimit:    cfg.BodyLimitBytes,
		ErrorHandler: api.ErrorHandler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	}
	// Behind a reverse proxy the real client address is in X-Forwarded-For.
	// Trusting it only when a proxy is configured keeps a direct caller from
	// spoofing its address, and without it the per-IP rate limit would treat
	// every request as coming from the proxy.
	if len(cfg.TrustedProxies) > 0 {
		fiberCfg.TrustProxy = true
		fiberCfg.TrustProxyConfig = fiber.TrustProxyConfig{
			Proxies: cfg.TrustedProxies,
		}
		fiberCfg.ProxyHeader = fiber.HeaderXForwardedFor
	}

	app := fiber.New(fiberCfg)

	// A panic in any handler would otherwise drop the connection; recover turns
	// it into a normal error, which the ErrorHandler renders as a 500 envelope.
	// The stack trace is logged so the panic is still diagnosable.
	app.Use(recover.New(recover.Config{
		EnableStackTrace: true,
		StackTraceHandler: func(c fiber.Ctx, e any) {
			logger.Error("recovered panic",
				slog.Any("panic", e),
				slog.String("method", c.Method()),
				slog.String("path", c.Path()),
				slog.String("stack", string(debug.Stack())),
			)
		},
	}))

	app.Use(accessLog(logger))

	// Root health for infrastructure probes (Caddy, Docker).
	app.Get("/health", todo.Health)
	// The contract puts /health under the versioned base URL, and it must stay
	// unauthenticated, so it is registered outside the group.
	app.Get("/api/v1/health", todo.Health)

	// Edge limiter runs before Auth so token guessing is bounded too; the inner
	// one runs per token afterwards.
	v1 := app.Group(
		"/api/v1",
		middleware.RateLimit(cfg.IPRateLimitPerMinute, middleware.KeyByIP),
		middleware.Auth(cfg.APIToken),
		middleware.RateLimit(cfg.RateLimitPerMinute, middleware.KeyByToken),
	)
	todo.NewHandler(service).Register(v1)

	return app
}

// accessLog writes one structured line per request, apart from the health
// probes, which would otherwise dominate the log.
func accessLog(logger *slog.Logger) fiber.Handler {
	return func(c fiber.Ctx) error {
		start := time.Now()
		err := c.Next()

		path := c.Path()
		if path != "/health" && path != "/api/v1/health" {
			status := c.Response().StatusCode()
			attrs := []any{
				slog.String("method", c.Method()),
				slog.String("path", path),
				slog.Int("status", status),
				slog.Duration("duration", time.Since(start)),
			}
			if err != nil {
				attrs = append(attrs, slog.String("error", err.Error()))
			}
			logger.Info("request", attrs...)
		}
		return err
	}
}
