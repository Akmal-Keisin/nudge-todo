package database

import (
	"database/sql"
	"embed"
	"fmt"
	"log/slog"

	"github.com/pressly/goose/v3"
	_ "modernc.org/sqlite" // pure-Go driver, registers as "sqlite"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// Open connects to SQLite, applies the pragmas this workload wants, and runs
// any pending migrations.
func Open(path string, logger *slog.Logger) (*sql.DB, error) {
	dsn := path + "?_pragma=busy_timeout(5000)" +
		"&_pragma=journal_mode(WAL)" +
		"&_pragma=foreign_keys(1)"

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	// SQLite handles one writer at a time; keeping the pool small avoids
	// spurious SQLITE_BUSY under the prune job.
	db.SetMaxOpenConns(1)

	if err := db.Ping(); err != nil {
		db.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}

	if err := migrate(db, logger); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func migrate(db *sql.DB, logger *slog.Logger) error {
	goose.SetBaseFS(migrationsFS)
	goose.SetLogger(gooseLogger{logger: logger})
	if err := goose.SetDialect("sqlite3"); err != nil {
		return fmt.Errorf("set migration dialect: %w", err)
	}
	if err := goose.Up(db, "migrations"); err != nil {
		return fmt.Errorf("run migrations: %w", err)
	}
	return nil
}

// gooseLogger routes goose output through slog.
type gooseLogger struct {
	logger *slog.Logger
}

func (g gooseLogger) Printf(format string, v ...any) {
	g.logger.Debug(fmt.Sprintf(format, v...), slog.String("component", "migrate"))
}

func (g gooseLogger) Fatalf(format string, v ...any) {
	g.logger.Error(fmt.Sprintf(format, v...), slog.String("component", "migrate"))
}
