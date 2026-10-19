package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v3"

	"github.com/akmalkeisin/nudge/server/internal/config"
	"github.com/akmalkeisin/nudge/server/internal/database"
	"github.com/akmalkeisin/nudge/server/internal/server"
	"github.com/akmalkeisin/nudge/server/internal/todo"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	if err := run(logger); err != nil {
		logger.Error("server stopped", slog.String("error", err.Error()))
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	db, err := database.Open(cfg.DBPath, logger)
	if err != nil {
		return err
	}
	defer db.Close()

	service := todo.NewService(todo.NewSQLiteRepository(db), cfg.Retention())
	app := server.New(cfg, service, logger)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Prune once at startup, then on the interval.
	prune(ctx, service, logger)
	go func() {
		ticker := time.NewTicker(cfg.PruneInterval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				prune(ctx, service, logger)
			}
		}
	}()

	go func() {
		<-ctx.Done()
		logger.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := app.ShutdownWithContext(shutdownCtx); err != nil {
			logger.Error("shutdown", slog.String("error", err.Error()))
		}
	}()

	logger.Info("listening",
		slog.String("addr", cfg.Addr),
		slog.String("db", cfg.DBPath),
		slog.Int("retentionDays", cfg.ArchiveRetentionDays),
	)
	// The Fiber banner would interleave with the JSON logs.
	err = app.Listen(cfg.Addr, fiber.ListenConfig{DisableStartupMessage: true})
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	return nil
}

// pruneTimeout bounds a single retention run so a stuck delete cannot hold a
// connection indefinitely.
const pruneTimeout = 30 * time.Second

func prune(ctx context.Context, service *todo.Service, logger *slog.Logger) {
	pruneCtx, cancel := context.WithTimeout(ctx, pruneTimeout)
	defer cancel()

	removed, err := service.Prune(pruneCtx)
	if err != nil {
		logger.Error("prune", slog.String("error", err.Error()))
		return
	}
	if removed > 0 {
		logger.Info("pruned expired todos", slog.Int64("removed", removed))
	}
}
