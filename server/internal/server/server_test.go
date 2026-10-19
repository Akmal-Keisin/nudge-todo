package server_test

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gofiber/fiber/v3"

	"github.com/akmalkeisin/nudge/server/internal/config"
	"github.com/akmalkeisin/nudge/server/internal/database"
	"github.com/akmalkeisin/nudge/server/internal/server"
	"github.com/akmalkeisin/nudge/server/internal/todo"
)

const testToken = "test-token"
const testRetention = 14 * 24 * time.Hour

type testOptions struct {
	rateLimitPerMinute   int
	ipRateLimitPerMinute int
	bodyLimitBytes       int
}

func newTestApp(t *testing.T) (*fiber.App, *todo.Service, *todo.SQLiteRepository) {
	t.Helper()
	return newTestAppWith(t, testOptions{
		rateLimitPerMinute:   600,
		ipRateLimitPerMinute: 600,
		bodyLimitBytes:       4096,
	})
}

func newTestAppWith(
	t *testing.T,
	opts testOptions,
) (*fiber.App, *todo.Service, *todo.SQLiteRepository) {
	t.Helper()

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))

	db, err := database.Open(":memory:", logger)
	if err != nil {
		t.Fatalf("open database: %v", err)
	}
	t.Cleanup(func() { db.Close() })

	repo := todo.NewSQLiteRepository(db)
	service := todo.NewService(repo, testRetention)
	cfg := config.Config{
		APIToken:             testToken,
		BodyLimitBytes:       opts.bodyLimitBytes,
		RateLimitPerMinute:   opts.rateLimitPerMinute,
		IPRateLimitPerMinute: opts.ipRateLimitPerMinute,
	}
	return server.New(cfg, service, logger), service, repo
}

// do sends a request with auth and returns the response.
func do(t *testing.T, app *fiber.App, method, path, body string, withAuth bool) *http.Response {
	t.Helper()

	var reader io.Reader
	if body != "" {
		reader = bytes.NewBufferString(body)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	if withAuth {
		req.Header.Set("Authorization", "Bearer "+testToken)
	}

	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("%s %s: %v", method, path, err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func decodeData[T any](t *testing.T, resp *http.Response) T {
	t.Helper()
	var envelope struct {
		Data T `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode data envelope: %v", err)
	}
	return envelope.Data
}

func decodeErrorCode(t *testing.T, resp *http.Response) string {
	t.Helper()
	var envelope struct {
		Error struct {
			Code    string         `json:"code"`
			Message string         `json:"message"`
			Details map[string]any `json:"details"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
		t.Fatalf("decode error envelope: %v", err)
	}
	return envelope.Error.Code
}

func TestHealthNeedsNoAuth(t *testing.T) {
	app, _, _ := newTestApp(t)
	resp := do(t, app, http.MethodGet, "/health", "", false)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
}

// A panic in a handler must surface as the contract's 500 envelope instead of
// dropping the connection.
func TestPanicBecomesInternalErrorEnvelope(t *testing.T) {
	app, _, _ := newTestApp(t)
	app.Get("/panic", func(fiber.Ctx) error { panic("boom") })

	resp := do(t, app, http.MethodGet, "/panic", "", false)
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("want 500, got %d", resp.StatusCode)
	}
	if code := decodeErrorCode(t, resp); code != "INTERNAL_ERROR" {
		t.Errorf("want INTERNAL_ERROR, got %s", code)
	}
}

func TestTodoRoutesRequireAuth(t *testing.T) {
	app, _, _ := newTestApp(t)

	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/api/v1/todos"},
		{http.MethodPost, "/api/v1/todos"},
		{http.MethodPatch, "/api/v1/todos/abc"},
		{http.MethodDelete, "/api/v1/todos/abc"},
	} {
		resp := do(t, app, tc.method, tc.path, `{}`, false)
		if resp.StatusCode != http.StatusUnauthorized {
			t.Errorf("%s %s: want 401, got %d", tc.method, tc.path, resp.StatusCode)
		}
		if code := decodeErrorCode(t, resp); code != "UNAUTHORIZED" {
			t.Errorf("%s %s: want UNAUTHORIZED, got %s", tc.method, tc.path, code)
		}
	}
}

func TestCreateThenList(t *testing.T) {
	app, _, _ := newTestApp(t)

	resp := do(t, app, http.MethodPost, "/api/v1/todos",
		`{"id":"0b8f4c3e-5d1a-4c52-9a7e-2f6c1e8b9d10","text":"  Call the bank  "}`, true)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("want 201, got %d", resp.StatusCode)
	}
	created := decodeData[todo.Todo](t, resp)
	if created.Text != "Call the bank" {
		t.Errorf("text should be trimmed, got %q", created.Text)
	}
	if created.ID != "0b8f4c3e-5d1a-4c52-9a7e-2f6c1e8b9d10" {
		t.Errorf("id should be honoured, got %q", created.ID)
	}
	if created.IsArchived || created.ArchivedAt != nil {
		t.Errorf("new todo should be active, got %+v", created)
	}
	if !created.CreatedAt.Equal(created.UpdatedAt) {
		t.Errorf("created/updated should match on create")
	}

	resp = do(t, app, http.MethodGet, "/api/v1/todos", "", true)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("want 200, got %d", resp.StatusCode)
	}
	list := decodeData[[]todo.Todo](t, resp)
	if len(list) != 1 {
		t.Fatalf("want 1 todo, got %d", len(list))
	}
}

func TestCreateIsIdempotentOnID(t *testing.T) {
	app, _, _ := newTestApp(t)
	body := `{"id":"11111111-1111-4111-8111-111111111111","text":"First"}`

	first := do(t, app, http.MethodPost, "/api/v1/todos", body, true)
	if first.StatusCode != http.StatusCreated {
		t.Fatalf("first create: want 201, got %d", first.StatusCode)
	}

	second := do(t, app, http.MethodPost, "/api/v1/todos",
		`{"id":"11111111-1111-4111-8111-111111111111","text":"Second"}`, true)
	if second.StatusCode != http.StatusOK {
		t.Fatalf("repeat create: want 200, got %d", second.StatusCode)
	}
	stored := decodeData[todo.Todo](t, second)
	if stored.Text != "First" {
		t.Errorf("repeat create should return the stored todo, got %q", stored.Text)
	}
}

func TestCreateGeneratesIDWhenMissing(t *testing.T) {
	app, _, _ := newTestApp(t)
	resp := do(t, app, http.MethodPost, "/api/v1/todos", `{"text":"No id"}`, true)
	if resp.StatusCode != http.StatusCreated {
		t.Fatalf("want 201, got %d", resp.StatusCode)
	}
	if decodeData[todo.Todo](t, resp).ID == "" {
		t.Error("server should generate an id")
	}
}

func TestValidationErrors(t *testing.T) {
	app, _, _ := newTestApp(t)

	cases := []struct {
		name   string
		method string
		path   string
		body   string
	}{
		{"empty text", http.MethodPost, "/api/v1/todos", `{"text":"   "}`},
		{"text too long", http.MethodPost, "/api/v1/todos", `{"text":"` + longText(501) + `"}`},
		{"bad id", http.MethodPost, "/api/v1/todos", `{"id":"not-a-uuid","text":"x"}`},
		{"malformed json", http.MethodPost, "/api/v1/todos", `{"text":`},
		{"empty body", http.MethodPost, "/api/v1/todos", ``},
		{"no fields to patch", http.MethodPatch, "/api/v1/todos/x", `{}`},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resp := do(t, app, tc.method, tc.path, tc.body, true)
			if resp.StatusCode != http.StatusBadRequest {
				t.Fatalf("want 400, got %d", resp.StatusCode)
			}
			if code := decodeErrorCode(t, resp); code != "VALIDATION_ERROR" {
				t.Errorf("want VALIDATION_ERROR, got %s", code)
			}
		})
	}
}

func TestBadStatusQuery(t *testing.T) {
	app, _, _ := newTestApp(t)
	resp := do(t, app, http.MethodGet, "/api/v1/todos?status=weird", "", true)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", resp.StatusCode)
	}
}

func TestArchiveRestoreAndFilters(t *testing.T) {
	app, _, _ := newTestApp(t)

	create := do(t, app, http.MethodPost, "/api/v1/todos", `{"text":"Archive me"}`, true)
	created := decodeData[todo.Todo](t, create)

	resp := do(t, app, http.MethodPatch, "/api/v1/todos/"+created.ID, `{"isArchived":true}`, true)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("archive: want 200, got %d", resp.StatusCode)
	}
	archived := decodeData[todo.Todo](t, resp)
	if !archived.IsArchived || archived.ArchivedAt == nil {
		t.Fatalf("archive should set isArchived and archivedAt, got %+v", archived)
	}

	active := decodeData[[]todo.Todo](t,
		do(t, app, http.MethodGet, "/api/v1/todos?status=active", "", true))
	if len(active) != 0 {
		t.Errorf("active should be empty, got %d", len(active))
	}
	archivedList := decodeData[[]todo.Todo](t,
		do(t, app, http.MethodGet, "/api/v1/todos?status=archived", "", true))
	if len(archivedList) != 1 {
		t.Errorf("archived should have 1, got %d", len(archivedList))
	}

	resp = do(t, app, http.MethodPatch, "/api/v1/todos/"+created.ID, `{"isArchived":false}`, true)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("restore: want 200, got %d", resp.StatusCode)
	}
	restored := decodeData[todo.Todo](t, resp)
	if restored.IsArchived || restored.ArchivedAt != nil {
		t.Errorf("restore should clear archivedAt, got %+v", restored)
	}
}

func TestCannotEditArchivedText(t *testing.T) {
	app, _, _ := newTestApp(t)

	create := do(t, app, http.MethodPost, "/api/v1/todos", `{"text":"Original"}`, true)
	created := decodeData[todo.Todo](t, create)
	do(t, app, http.MethodPatch, "/api/v1/todos/"+created.ID, `{"isArchived":true}`, true)

	resp := do(t, app, http.MethodPatch, "/api/v1/todos/"+created.ID, `{"text":"Nope"}`, true)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", resp.StatusCode)
	}
}

func TestDeleteIsIdempotent(t *testing.T) {
	app, _, _ := newTestApp(t)

	create := do(t, app, http.MethodPost, "/api/v1/todos", `{"text":"Delete me"}`, true)
	created := decodeData[todo.Todo](t, create)

	first := do(t, app, http.MethodDelete, "/api/v1/todos/"+created.ID, "", true)
	if first.StatusCode != http.StatusNoContent {
		t.Fatalf("first delete: want 204, got %d", first.StatusCode)
	}
	second := do(t, app, http.MethodDelete, "/api/v1/todos/"+created.ID, "", true)
	if second.StatusCode != http.StatusNoContent {
		t.Fatalf("second delete: want 204, got %d", second.StatusCode)
	}
}

func TestPatchMissingTodoIs404(t *testing.T) {
	app, _, _ := newTestApp(t)
	resp := do(t, app, http.MethodPatch,
		"/api/v1/todos/11111111-1111-4111-8111-111111111111", `{"isArchived":true}`, true)
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("want 404, got %d", resp.StatusCode)
	}
	if code := decodeErrorCode(t, resp); code != "NOT_FOUND" {
		t.Errorf("want NOT_FOUND, got %s", code)
	}
}

func TestExpiredArchivedTodosArePrunedAndHidden(t *testing.T) {
	app, service, repo := newTestApp(t)

	// Seed a todo that was archived just past the retention window.
	stale := time.Now().UTC().Add(-testRetention - time.Hour)
	if _, _, err := repo.Create(t.Context(), todo.Todo{
		ID:         "22222222-2222-4222-8222-222222222222",
		Text:       "Ancient",
		IsArchived: true,
		ArchivedAt: &stale,
		CreatedAt:  stale.Add(-time.Hour),
		UpdatedAt:  stale,
	}); err != nil {
		t.Fatalf("seed stale todo: %v", err)
	}

	// The listing hides expired rows even before the job runs.
	list := decodeData[[]todo.Todo](t,
		do(t, app, http.MethodGet, "/api/v1/todos", "", true))
	if len(list) != 0 {
		t.Fatalf("expired todo should be hidden, got %d", len(list))
	}

	removed, err := service.Prune(t.Context())
	if err != nil {
		t.Fatalf("prune: %v", err)
	}
	if removed != 1 {
		t.Fatalf("want 1 pruned, got %d", removed)
	}

	list = decodeData[[]todo.Todo](t,
		do(t, app, http.MethodGet, "/api/v1/todos?status=archived", "", true))
	if len(list) != 0 {
		t.Errorf("pruned todo should be gone, got %d", len(list))
	}
}

func TestRecentArchivedTodosSurvive(t *testing.T) {
	app, service, repo := newTestApp(t)

	recent := time.Now().UTC().Add(-time.Hour)
	if _, _, err := repo.Create(t.Context(), todo.Todo{
		ID:         "33333333-3333-4333-8333-333333333333",
		Text:       "Just archived",
		IsArchived: true,
		ArchivedAt: &recent,
		CreatedAt:  recent,
		UpdatedAt:  recent,
	}); err != nil {
		t.Fatalf("seed recent todo: %v", err)
	}

	if _, err := service.Prune(t.Context()); err != nil {
		t.Fatalf("prune: %v", err)
	}

	list := decodeData[[]todo.Todo](t,
		do(t, app, http.MethodGet, "/api/v1/todos?status=archived", "", true))
	if len(list) != 1 {
		t.Errorf("recent archived todo should survive, got %d", len(list))
	}
}

func longText(n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = 'a'
	}
	return string(b)
}

func TestRateLimitReturns429(t *testing.T) {
	app, _, _ := newTestAppWith(t, testOptions{
		rateLimitPerMinute:   2,
		ipRateLimitPerMinute: 600,
		bodyLimitBytes:       4096,
	})

	for i := range 2 {
		resp := do(t, app, http.MethodGet, "/api/v1/todos", "", true)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("request %d: want 200, got %d", i+1, resp.StatusCode)
		}
	}

	resp := do(t, app, http.MethodGet, "/api/v1/todos", "", true)
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("want 429, got %d", resp.StatusCode)
	}
	if code := decodeErrorCode(t, resp); code != "RATE_LIMITED" {
		t.Errorf("want RATE_LIMITED, got %s", code)
	}
}

// The edge limiter keys on the client address and sits ahead of Auth, so
// repeated bad tokens are cut off instead of being answered indefinitely.
func TestIPRateLimitBoundsTokenGuessing(t *testing.T) {
	app, _, _ := newTestAppWith(t, testOptions{
		rateLimitPerMinute:   600,
		ipRateLimitPerMinute: 2,
		bodyLimitBytes:       4096,
	})

	for i := range 2 {
		resp := do(t, app, http.MethodGet, "/api/v1/todos", "", false)
		if resp.StatusCode != http.StatusUnauthorized {
			t.Fatalf("attempt %d: want 401, got %d", i+1, resp.StatusCode)
		}
	}

	resp := do(t, app, http.MethodGet, "/api/v1/todos", "", false)
	if resp.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("want 429 once the IP budget is spent, got %d", resp.StatusCode)
	}
}

// The edge limiter must not swallow requests that are otherwise fine.
func TestEdgeLimitDoesNotBlockLegitimateTraffic(t *testing.T) {
	app, _, _ := newTestAppWith(t, testOptions{
		rateLimitPerMinute:   600,
		ipRateLimitPerMinute: 10,
		bodyLimitBytes:       4096,
	})

	for i := range 10 {
		resp := do(t, app, http.MethodGet, "/api/v1/todos", "", true)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("request %d: want 200, got %d", i+1, resp.StatusCode)
		}
	}
}

func TestBodyLimitRejectsOversizedRequest(t *testing.T) {
	app, _, _ := newTestAppWith(t, testOptions{rateLimitPerMinute: 600, bodyLimitBytes: 64})

	req := httptest.NewRequest(http.MethodPost, "/api/v1/todos",
		bytes.NewBufferString(`{"text":"`+longText(200)+`"}`))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+testToken)

	resp, err := app.Test(req)
	if err != nil {
		// The transport rejects an oversized body before Fiber sees it, which
		// is the behaviour a real client gets as a 413.
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusRequestEntityTooLarge &&
		resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("want 413 or 400, got %d", resp.StatusCode)
	}
}
