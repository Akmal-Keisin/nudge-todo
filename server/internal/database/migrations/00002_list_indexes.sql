-- +goose Up
-- Supports the active listing's `WHERE is_archived = 0 ORDER BY created_at DESC`
-- without a temp sort.
CREATE INDEX idx_todos_is_archived_created_at
    ON todos (is_archived, created_at DESC);

-- +goose Down
DROP INDEX idx_todos_is_archived_created_at;
