package todo

import (
	"errors"
	"strings"
	"time"
)

// MaxTextLength bounds a todo's text, matching the client-side rule.
const MaxTextLength = 500

// Todo is a single-line task. Timestamps are always UTC.
type Todo struct {
	ID         string     `json:"id"`
	Text       string     `json:"text"`
	IsArchived bool       `json:"isArchived"`
	ArchivedAt *time.Time `json:"archivedAt"`
	CreatedAt  time.Time  `json:"createdAt"`
	UpdatedAt  time.Time  `json:"updatedAt"`
}

// Status filters a listing.
type Status string

const (
	StatusActive   Status = "active"
	StatusArchived Status = "archived"
	StatusAll      Status = "all"
)

// ParseStatus maps a query value to a Status, defaulting to all.
func ParseStatus(raw string) (Status, error) {
	switch Status(strings.ToLower(raw)) {
	case "", StatusAll:
		return StatusAll, nil
	case StatusActive:
		return StatusActive, nil
	case StatusArchived:
		return StatusArchived, nil
	default:
		return "", errors.New("status must be active, archived or all")
	}
}

// ValidationError reports which field failed and why. Handlers turn this into
// the contract's VALIDATION_ERROR response.
type ValidationError struct {
	Field   string
	Message string
}

func (e ValidationError) Error() string { return e.Message }

// ValidateText trims and bounds the text, returning the cleaned value.
func ValidateText(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", ValidationError{Field: "text", Message: "text must be 1 to 500 characters"}
	}
	if len([]rune(trimmed)) > MaxTextLength {
		return "", ValidationError{Field: "text", Message: "text must be 1 to 500 characters"}
	}
	return trimmed, nil
}

// Expired reports whether an archived todo is older than the retention window.
func (t Todo) Expired(now time.Time, retention time.Duration) bool {
	return t.IsArchived && t.ArchivedAt != nil && now.Sub(*t.ArchivedAt) >= retention
}
