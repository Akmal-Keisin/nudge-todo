package middleware

import (
	"crypto/subtle"

	"github.com/gofiber/fiber/v3"

	"github.com/akmalkeisin/nudge/server/internal/api"
)

// Auth requires a bearer token that matches expected, compared in constant
// time so the token cannot be probed by timing.
func Auth(expected string) fiber.Handler {
	want := []byte("Bearer " + expected)

	return func(c fiber.Ctx) error {
		got := []byte(c.Get(fiber.HeaderAuthorization))
		if subtle.ConstantTimeCompare(got, want) != 1 {
			return api.Unauthorized("missing or invalid bearer token")
		}
		return c.Next()
	}
}
