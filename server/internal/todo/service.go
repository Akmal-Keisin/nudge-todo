package todo

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Service holds the business rules. It is the only place that decides what a
// valid todo change is; handlers stay thin.
type Service struct {
	repo      Repository
	retention time.Duration
	now       func() time.Time
	newID     func() string
}

func NewService(repo Repository, retention time.Duration) *Service {
	return &Service{
		repo:      repo,
		retention: retention,
		// Truncated to microseconds because that is the storage resolution;
		// otherwise a create response would not match a later read.
		now:   func() time.Time { return time.Now().UTC().Truncate(time.Microsecond) },
		newID: uuid.NewString,
	}
}

// CreateRequest is the POST /todos body. ID is optional so a client can supply
// its own UUID and retry safely.
type CreateRequest struct {
	ID   string
	Text string
}

// UpdateRequest is the PATCH /todos/{id} body. Nil fields are untouched.
type UpdateRequest struct {
	Text       *string
	IsArchived *bool
}

func (s *Service) List(ctx context.Context, status Status) ([]Todo, error) {
	return s.repo.List(ctx, status, s.now(), s.retention)
}

// Create returns the stored todo and whether it was newly created. A repeat of
// an existing id reports created=false so the handler can answer 200.
func (s *Service) Create(ctx context.Context, req CreateRequest) (Todo, bool, error) {
	text, err := ValidateText(req.Text)
	if err != nil {
		return Todo{}, false, err
	}

	id := strings.TrimSpace(req.ID)
	if id == "" {
		id = s.newID()
	}

	now := s.now()
	candidate := Todo{
		ID:        id,
		Text:      text,
		CreatedAt: now,
		UpdatedAt: now,
	}
	return s.repo.Create(ctx, candidate)
}

func (s *Service) Update(ctx context.Context, id string, req UpdateRequest) (Todo, error) {
	if req.Text != nil {
		text, err := ValidateText(*req.Text)
		if err != nil {
			return Todo{}, err
		}
		current, err := s.repo.Get(ctx, id)
		if err != nil {
			return Todo{}, err
		}
		if current.IsArchived {
			return Todo{}, ValidationError{
				Field:   "text",
				Message: "cannot edit an archived todo; restore it first",
			}
		}
		req.Text = &text
	}

	return s.repo.Update(ctx, id, req.Text, req.IsArchived, s.now())
}

// Delete treats an already-missing todo as success, so a retried delete is
// idempotent.
func (s *Service) Delete(ctx context.Context, id string) error {
	err := s.repo.Delete(ctx, id)
	if err == ErrNotFound {
		return nil
	}
	return err
}

// Prune removes archived todos past the retention window.
func (s *Service) Prune(ctx context.Context) (int64, error) {
	return s.repo.PruneExpired(ctx, s.now().Add(-s.retention))
}
