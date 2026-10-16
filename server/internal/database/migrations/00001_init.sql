-- +goose Up
CREATE TABLE todos (
    id          TEXT PRIMARY KEY,
    text        TEXT NOT NULL,
    is_archived INTEGER NOT NULL DEFAULT 0,
    archived_at INTEGER,
    created_at  INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
);

CREATE INDEX idx_todos_is_archived_archived_at
    ON todos (is_archived, archived_at);

-- +goose Down
DROP INDEX idx_todos_is_archived_archived_at;
DROP TABLE todos;
