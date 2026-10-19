package database

import (
	"database/sql"
	"embed"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/pressly/goose/v3"
	_ "modernc.org/sqlite" // pure-Go driver, registers as "sqlite"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// poolSize caps the connection pool. WAL lets readers run while a writer holds
// the write lock, so a handful of connections is safe; one would serialize
// every read behind every write and behind the hourly prune.
const poolSize = 4

// Open connects to SQLite, applies the pragmas this workload wants, and runs
// any pending migrations.
func Open(path string, logger *slog.Logger) (*sql.DB, error) {
	dsn := path + "?_pragma=busy_timeout(5000)" +
		"&_pragma=journal_mode(WAL)" +
		// NORMAL is the recommended WAL pairing: a commit no longer pays an
		// fsync per write, which is the hot path here.
		"&_pragma=synchronous(NORMAL)" +
		"&_pragma=foreign_keys(1)" +
		"&_pragma=temp_store(MEMORY)"

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	// An in-memory database is private to each connection, so a pool would hand
	// every connection its own empty database. Tests use :memory:; pin it to a
	// single connection and pool only the file-backed production database.
	conns := poolSize
	if isMemoryDB(path) {
		conns = 1
	}
	db.SetMaxOpenConns(conns)
	db.SetMaxIdleConns(conns)
	db.SetConnMaxLifetime(time.Hour)

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

// isMemoryDB reports whether path refers to an in-memory database, which cannot
// be shared across pooled connections.
func isMemoryDB(path string) bool {
	return strings.Contains(path, ":memory:") || strings.Contains(path, "mode=memory")
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
