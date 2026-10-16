package server

import (
	"time"

	"github.com/gofiber/fiber/v3"

	"github.com/akmalkeisin/nudge/server/internal/api"
	"github.com/akmalkeisin/nudge/server/internal/config"
	"github.com/akmalkeisin/nudge/server/internal/middleware"
	"github.com/akmalkeisin/nudge/server/internal/todo"
)

// New builds the HTTP app: an unauthenticated /health plus the token-protected,
// rate-limited /api/v1 group.
func New(cfg config.Config, service *todo.Service) *fiber.App {
	app := fiber.New(fiber.Config{
		BodyLimit:    cfg.BodyLimitBytes,
		ErrorHandler: api.ErrorHandler,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  60 * time.Second,
	})

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
