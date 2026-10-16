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

func (r *SQLiteRepository) List(
	ctx context.Context,
	status Status,
	now time.Time,
	retention time.Duration,
) ([]Todo, error) {
	cut := now.Add(-retention).UnixMicro()

	query := `SELECT ` + selectColumns + ` FROM todos
		WHERE NOT (is_archived = 1 AND archived_at IS NOT NULL AND archived_at <= ?)`

	switch status {
	case StatusActive:
		query += ` AND is_archived = 0 ORDER BY created_at DESC`
	case StatusArchived:
		query += ` AND is_archived = 1 ORDER BY archived_at DESC`
	default:
		query += ` ORDER BY created_at DESC`
	}

	rows, err := r.db.QueryContext(ctx, query, cut)
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

func (r *SQLiteRepository) Create(ctx context.Context, t Todo) (Todo, bool, error) {
	existing, err := r.Get(ctx, t.ID)
	switch {
	case err == nil:
		return existing, false, nil
	case !errors.Is(err, ErrNotFound):
		return Todo{}, false, err
	}

	_, err = r.db.ExecContext(ctx,
		`INSERT INTO todos (`+selectColumns+`) VALUES (?, ?, ?, ?, ?, ?)`,
		t.ID, t.Text, boolToInt(t.IsArchived), timePtrToMicro(t.ArchivedAt),
		t.CreatedAt.UnixMicro(), t.UpdatedAt.UnixMicro(),
	)
	if err != nil {
		// A concurrent insert of the same id wins; return what is stored.
		if stored, getErr := r.Get(ctx, t.ID); getErr == nil {
			return stored, false, nil
		}
		return Todo{}, false, fmt.Errorf("create todo: %w", err)
	}
	return t, true, nil
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

func (r *SQLiteRepository) Update(
	ctx context.Context,
	id string,
	text *string,
	isArchived *bool,
	now time.Time,
) (Todo, error) {
	current, err := r.Get(ctx, id)
	if err != nil {
		return Todo{}, err
	}

	if text != nil {
		current.Text = *text
	}
	if isArchived != nil {
		current.IsArchived = *isArchived
		switch {
		case *isArchived && current.ArchivedAt == nil:
			at := now
			current.ArchivedAt = &at
		case !*isArchived:
			current.ArchivedAt = nil
		}
	}
	current.UpdatedAt = now

	_, err = r.db.ExecContext(ctx,
		`UPDATE todos SET text = ?, is_archived = ?, archived_at = ?, updated_at = ?
		 WHERE id = ?`,
		current.Text, boolToInt(current.IsArchived), timePtrToMicro(current.ArchivedAt),
		current.UpdatedAt.UnixMicro(), current.ID,
	)
	if err != nil {
		return Todo{}, fmt.Errorf("update todo: %w", err)
	}
	return current, nil
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
