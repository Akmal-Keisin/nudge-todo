package todo

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// SQLiteRepository stores todos in SQLite. Timestamps are held as Unix
// microseconds so ordering and comparisons are plain integer work.
type SQLiteRepository struct {
	db *sql.DB
}

func NewSQLiteRepository(db *sql.DB) *SQLiteRepository {
	return &SQLiteRepository{db: db}
}

const selectColumns = `id, text, is_archived, archived_at, created_at, updated_at`

// Queries are package constants so no SQL string is rebuilt per call.
//
// The listing uses positive predicates so SQLite can walk an index instead of
// scanning and sorting the whole table: active uses (is_archived, created_at),
// archived uses (is_archived, archived_at).
const (
	listActiveQuery = `SELECT ` + selectColumns + ` FROM todos
		WHERE is_archived = 0 ORDER BY created_at DESC`

	listArchivedQuery = `SELECT ` + selectColumns + ` FROM todos
		WHERE is_archived = 1 AND archived_at IS NOT NULL AND archived_at > ?
		ORDER BY archived_at DESC`

	// Both kinds, still hiding expired rows. The list is small, so the
	// scan-and-sort this costs is not worth a UNION of two indexed reads.
	listAllQuery = `SELECT ` + selectColumns + ` FROM todos
		WHERE is_archived = 0
		   OR (is_archived = 1 AND archived_at IS NOT NULL AND archived_at > ?)
		ORDER BY created_at DESC`
)

func (r *SQLiteRepository) List(
	ctx context.Context,
	status Status,
	now time.Time,
	retention time.Duration,
) ([]Todo, error) {
	cut := now.Add(-retention).UnixMicro()

	var (
		query string
		args  []any
	)
	switch status {
	case StatusActive:
		// Active rows are never expired, so no retention cut is needed.
		query = listActiveQuery
	case StatusArchived:
		query, args = listArchivedQuery, []any{cut}
	default:
		query, args = listAllQuery, []any{cut}
	}

	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list todos: %w", err)
	}
	defer rows.Close()

	todos := make([]Todo, 0)
	for rows.Next() {
		t, err := scanTodo(rows)
		if err != nil {
			return nil, err
		}
		todos = append(todos, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list todos: %w", err)
	}
	return todos, nil
}

// Create inserts a todo in one statement. A repeat of an existing id inserts
// nothing and returns the stored todo with created=false, so a retried create
// is idempotent without a read up front.
func (r *SQLiteRepository) Create(ctx context.Context, t Todo) (Todo, bool, error) {
	row := r.db.QueryRowContext(ctx,
		`INSERT INTO todos (`+selectColumns+`) VALUES (?, ?, ?, ?, ?, ?)
		 ON CONFLICT(id) DO NOTHING
		 RETURNING `+selectColumns,
		t.ID, t.Text, boolToInt(t.IsArchived), timePtrToMicro(t.ArchivedAt),
		t.CreatedAt.UnixMicro(), t.UpdatedAt.UnixMicro(),
	)
	stored, err := scanTodo(row)
	if errors.Is(err, sql.ErrNoRows) {
		existing, getErr := r.Get(ctx, t.ID)
		if getErr != nil {
			return Todo{}, false, fmt.Errorf("create todo: %w", getErr)
		}
		return existing, false, nil
	}
	if err != nil {
		return Todo{}, false, fmt.Errorf("create todo: %w", err)
	}
	return stored, true, nil
}

func (r *SQLiteRepository) Get(ctx context.Context, id string) (Todo, error) {
	row := r.db.QueryRowContext(ctx,
		`SELECT `+selectColumns+` FROM todos WHERE id = ?`, id)
	t, err := scanTodo(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Todo{}, ErrNotFound
	}
	if err != nil {
		return Todo{}, fmt.Errorf("get todo: %w", err)
	}
	return t, nil
}

// Update applies the change in a single statement, so there is no window
// between reading the row and writing it. Nil fields are left untouched; a
// missing id is reported as ErrNotFound via RETURNING no rows.
func (r *SQLiteRepository) Update(
	ctx context.Context,
	id string,
	text *string,
	isArchived *bool,
	now time.Time,
) (Todo, error) {
	var (
		textArg   any // nil leaves text alone
		archArg   any // nil leaves is_archived and archived_at alone
		archiveAt any // the timestamp to stamp when archiving, else nil
	)
	if text != nil {
		textArg = *text
	}
	if isArchived != nil {
		archArg = boolToInt(*isArchived)
		if *isArchived {
			archiveAt = now.UnixMicro()
		}
	}

	row := r.db.QueryRowContext(ctx,
		`UPDATE todos SET
			text = COALESCE(?, text),
			is_archived = COALESCE(?, is_archived),
			archived_at = CASE
				WHEN ? IS NULL THEN archived_at
				WHEN ? = 1 THEN COALESCE(archived_at, ?)
				ELSE NULL
			END,
			updated_at = ?
		 WHERE id = ?
		 RETURNING `+selectColumns,
		textArg, archArg, archArg, archArg, archiveAt, now.UnixMicro(), id,
	)
	updated, err := scanTodo(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Todo{}, ErrNotFound
	}
	if err != nil {
		return Todo{}, fmt.Errorf("update todo: %w", err)
	}
	return updated, nil
}

func (r *SQLiteRepository) Delete(ctx context.Context, id string) error {
	result, err := r.db.ExecContext(ctx, `DELETE FROM todos WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete todo: %w", err)
	}
	affected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete todo: %w", err)
	}
	if affected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *SQLiteRepository) PruneExpired(ctx context.Context, cut time.Time) (int64, error) {
	result, err := r.db.ExecContext(ctx,
		`DELETE FROM todos WHERE is_archived = 1 AND archived_at IS NOT NULL AND archived_at <= ?`,
		cut.UnixMicro(),
	)
	if err != nil {
		return 0, fmt.Errorf("prune todos: %w", err)
	}
	removed, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("prune todos: %w", err)
	}
	return removed, nil
}

// scanner covers both *sql.Row and *sql.Rows.
type scanner interface {
	Scan(dest ...any) error
}

func scanTodo(s scanner) (Todo, error) {
	var (
		t          Todo
		archived   int
		archivedAt sql.NullInt64
		createdAt  int64
		updatedAt  int64
	)
	if err := s.Scan(&t.ID, &t.Text, &archived, &archivedAt, &createdAt, &updatedAt); err != nil {
		return Todo{}, err
	}
	t.IsArchived = archived == 1
	if archivedAt.Valid {
		at := time.UnixMicro(archivedAt.Int64).UTC()
		t.ArchivedAt = &at
	}
	t.CreatedAt = time.UnixMicro(createdAt).UTC()
	t.UpdatedAt = time.UnixMicro(updatedAt).UTC()
	return t, nil
}

func boolToInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func timePtrToMicro(t *time.Time) any {
	if t == nil {
		return nil
	}
	return t.UnixMicro()
}
