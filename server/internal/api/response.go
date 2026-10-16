package api

import (
	"net/http"

	"github.com/gofiber/fiber/v3"
)

// dataResponse wraps a successful payload as { "data": ... }.
type dataResponse struct {
	Data any `json:"data"`
}

type errorBody struct {
	Code    string         `json:"code"`
	Message string         `json:"message"`
	Details map[string]any `json:"details,omitempty"`
}

type errorResponse struct {
	Error errorBody `json:"error"`
}

// OK writes 200 with the data envelope.
func OK(c fiber.Ctx, data any) error {
	return c.Status(http.StatusOK).JSON(dataResponse{Data: data})
}

// Created writes 201 with the data envelope.
func Created(c fiber.Ctx, data any) error {
	return c.Status(http.StatusCreated).JSON(dataResponse{Data: data})
}

// NoContent writes a bare 204.
func NoContent(c fiber.Ctx) error {
	return c.SendStatus(http.StatusNoContent)
}

// DecodeBody parses a JSON request body, mapping malformed input to the
// contract's VALIDATION_ERROR.
func DecodeBody(c fiber.Ctx, out any) error {
	if len(c.Body()) == 0 {
		return Validation("request body is required", nil)
	}
	if err := c.Bind().JSON(out); err != nil {
		return Validation("request body must be valid JSON", nil)
	}
	return nil
}
