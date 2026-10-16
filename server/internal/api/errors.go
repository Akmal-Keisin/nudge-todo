package api

import (
	"errors"
	"net/http"

	"github.com/gofiber/fiber/v3"
)

// Error codes from the API contract.
const (
	CodeValidationError = "VALIDATION_ERROR"
	CodeUnauthorized    = "UNAUTHORIZED"
	CodeNotFound        = "NOT_FOUND"
	CodeRateLimited     = "RATE_LIMITED"
	CodeInternalError   = "INTERNAL_ERROR"
)

// Error is a failure the API can render directly. Anything else that reaches
// the error handler becomes a 500.
type Error struct {
	Status  int
	Code    string
	Message string
	Details map[string]any
}

func (e *Error) Error() string { return e.Message }

func Validation(message string, details map[string]any) *Error {
	return &Error{
		Status:  http.StatusBadRequest,
		Code:    CodeValidationError,
		Message: message,
		Details: details,
	}
}

func Unauthorized(message string) *Error {
	return &Error{
		Status:  http.StatusUnauthorized,
		Code:    CodeUnauthorized,
		Message: message,
	}
}

func NotFound(message string) *Error {
	return &Error{
		Status:  http.StatusNotFound,
		Code:    CodeNotFound,
		Message: message,
	}
}

func RateLimited(message string) *Error {
	return &Error{
		Status:  http.StatusTooManyRequests,
		Code:    CodeRateLimited,
		Message: message,
	}
}

func Internal(message string) *Error {
	return &Error{
		Status:  http.StatusInternalServerError,
		Code:    CodeInternalError,
		Message: message,
	}
}

// ErrorHandler renders any error as the contract's error envelope. It is
// installed on the Fiber app so no handler has to repeat this.
func ErrorHandler(c fiber.Ctx, err error) error {
	var apiErr *Error
	if errors.As(err, &apiErr) {
		return c.Status(apiErr.Status).JSON(errorResponse{Error: errorBody{
			Code:    apiErr.Code,
			Message: apiErr.Message,
			Details: apiErr.Details,
		}})
	}

	var fiberErr *fiber.Error
	if errors.As(err, &fiberErr) {
		return c.Status(fiberErr.Code).JSON(errorResponse{Error: errorBody{
			Code:    codeForStatus(fiberErr.Code),
			Message: fiberErr.Message,
		}})
	}

	return c.Status(http.StatusInternalServerError).JSON(errorResponse{Error: errorBody{
		Code:    CodeInternalError,
		Message: "internal error",
	}})
}

func codeForStatus(status int) string {
	switch status {
	case http.StatusBadRequest:
		return CodeValidationError
	case http.StatusUnauthorized:
		return CodeUnauthorized
	case http.StatusNotFound:
		return CodeNotFound
	case http.StatusTooManyRequests:
		return CodeRateLimited
	default:
		return CodeInternalError
	}
}
