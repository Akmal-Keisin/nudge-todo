package todo

import (
	"errors"
	"net/http"

	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"

	"github.com/akmalkeisin/nudge/server/internal/api"
)

// Handler adapts HTTP requests onto the todo service.
type Handler struct {
	service *Service
}

func NewHandler(service *Service) *Handler {
	return &Handler{service: service}
}

// Register mounts the todo routes on the given router.
func (h *Handler) Register(router fiber.Router) {
	router.Get("/todos", h.list)
	router.Post("/todos", h.create)
	router.Patch("/todos/:id", h.update)
	router.Delete("/todos/:id", h.delete)
}

type createBody struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}

type updateBody struct {
	Text       *string `json:"text"`
	IsArchived *bool   `json:"isArchived"`
}

func (h *Handler) list(c fiber.Ctx) error {
	status, err := ParseStatus(c.Query("status"))
	if err != nil {
		return api.Validation(err.Error(), map[string]any{"field": "status"})
	}

	todos, err := h.service.List(c.Context(), status)
	if err != nil {
		return err
	}
	return api.OK(c, todos)
}

func (h *Handler) create(c fiber.Ctx) error {
	var body createBody
	if err := api.DecodeBody(c, &body); err != nil {
		return err
	}
	if id := body.ID; id != "" {
		if _, err := uuid.Parse(id); err != nil {
			return api.Validation("id must be a UUID", map[string]any{"field": "id"})
		}
	}

	created, wasCreated, err := h.service.Create(c.Context(), CreateRequest{
		ID:   body.ID,
		Text: body.Text,
	})
	if err != nil {
		return mapDomainError(err)
	}
	if !wasCreated {
		return api.OK(c, created)
	}
	return api.Created(c, created)
}

func (h *Handler) update(c fiber.Ctx) error {
	var body updateBody
	if err := api.DecodeBody(c, &body); err != nil {
		return err
	}
	if body.Text == nil && body.IsArchived == nil {
		return api.Validation("provide text and/or isArchived", nil)
	}

	updated, err := h.service.Update(c.Context(), c.Params("id"), UpdateRequest{
		Text:       body.Text,
		IsArchived: body.IsArchived,
	})
	if err != nil {
		return mapDomainError(err)
	}
	return api.OK(c, updated)
}

func (h *Handler) delete(c fiber.Ctx) error {
	if err := h.service.Delete(c.Context(), c.Params("id")); err != nil {
		return mapDomainError(err)
	}
	return api.NoContent(c)
}

// mapDomainError converts domain errors into renderable API errors.
func mapDomainError(err error) error {
	var validation ValidationError
	if errors.As(err, &validation) {
		return api.Validation(validation.Message, map[string]any{"field": validation.Field})
	}
	if errors.Is(err, ErrNotFound) {
		return api.NotFound("todo not found")
	}
	return err
}

// Health is the unauthenticated liveness endpoint.
func Health(c fiber.Ctx) error {
	return c.SendStatus(http.StatusOK)
}
