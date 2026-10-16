package middleware

import (
	"sync"

	"github.com/gofiber/fiber/v3"
	"golang.org/x/time/rate"

	"github.com/akmalkeisin/nudge/server/internal/api"
)

// maxTrackedKeys bounds the limiter map so a flood of distinct keys cannot grow
// it without limit.
const maxTrackedKeys = 10000

// KeyByToken keys on the bearer token, for use after Auth.
func KeyByToken(c fiber.Ctx) string {
	return c.Get(fiber.HeaderAuthorization)
}

// KeyByIP keys on the client address, for use before Auth.
func KeyByIP(c fiber.Ctx) string {
	return c.IP()
}

// RateLimit caps requests per minute per key. The bucket allows a burst of
// perMinute requests and refills at perMinute/60 per second.
//
// Run it twice: once by IP ahead of Auth to bound token guessing, and once by
// token afterwards to bound a legitimate client.
func RateLimit(perMinute int, keyFunc func(fiber.Ctx) string) fiber.Handler {
	var (
		mu       sync.Mutex
		limiters = make(map[string]*rate.Limiter)
	)

	limiterFor := func(key string) *rate.Limiter {
		mu.Lock()
		defer mu.Unlock()

		if limiter, ok := limiters[key]; ok {
			return limiter
		}
		if len(limiters) >= maxTrackedKeys {
			pruneIdle(limiters)
		}
		limiter := rate.NewLimiter(rate.Limit(float64(perMinute)/60.0), perMinute)
		limiters[key] = limiter
		return limiter
	}

	return func(c fiber.Ctx) error {
		if !limiterFor(keyFunc(c)).Allow() {
			return api.RateLimited("too many requests")
		}
		return c.Next()
	}
}

// pruneIdle drops limiters that have fully refilled, which means they have not
// been used for at least a minute. Callers must hold the lock.
func pruneIdle(limiters map[string]*rate.Limiter) {
	for key, limiter := range limiters {
		if limiter.Tokens() >= float64(limiter.Burst()) {
			delete(limiters, key)
		}
	}
}
