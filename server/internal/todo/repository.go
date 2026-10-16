package todo

import (
	"context"
	"errors"
	"time"
)

// ErrNotFound is returned when a todo id does not exist.
var ErrNotFound = errors.New("todo not found")

// Repository is the storage boundary. Only the SQLite implementation lives
// behind it today; a Postgres one would slot in without touching the service.
type Repository interface {
	// List returns todos matching status, sorted per the API contract.
	List(ctx context.Context, status Status, now time.Time, retention time.Duration) ([]Todo, error)

	// Create inserts a todo. If the id already exists the stored todo is
	// returned unchanged with created=false, which makes retries idempotent.
	Create(ctx context.Context, t Todo) (stored Todo, created bool, err error)

	// Get returns a single todo, or ErrNotFound.
	Get(ctx context.Context, id string) (Todo, error)

	// Update applies a partial change. Nil fields are left alone.
	Update(ctx context.Context, id string, text *string, isArchived *bool, now time.Time) (Todo, error)

	// Delete removes a todo. ErrNotFound if it was already gone.
	Delete(ctx context.Context, id string) error

	// PruneExpired deletes archived todos whose archivedAt is at or before cut.
	PruneExpired(ctx context.Context, cut time.Time) (int64, error)
}
