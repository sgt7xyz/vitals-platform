// Command vitals serves synthetic patient vital signs. It exists to give the
// platform something real to deploy, observe, break, and recover.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"math/rand/v2"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"
)

var version = "dev" // overwritten at build time with -ldflags "-X main.version=<sha>"

type Server struct {
	metrics  *Metrics
	failRate float64 // 0.0-1.0; fraction of API calls that return 503 (game-day knob)
	ready    atomic.Bool
	log      *slog.Logger
}

type Reading struct {
	PatientID  string    `json:"patient_id"`
	HeartRate  int       `json:"heart_rate_bpm"`
	SpO2       int       `json:"spo2_pct"`
	RecordedAt time.Time `json:"recorded_at"`
	Version    string    `json:"version"`
}

func newLogger() *slog.Logger {
	// Cloud Logging reads "severity" and "message" from JSON logs, so rename slog's keys.
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			switch a.Key {
			case slog.LevelKey:
				a.Key = "severity"
			case slog.MessageKey:
				a.Key = "message"
			}
			return a
		},
	}))
}

func parseFailRate(s string) float64 {
	f, err := strconv.ParseFloat(s, 64)
	if err != nil || f < 0 {
		return 0
	}
	if f > 1 {
		return 1
	}
	return f
}

func NewServer(failRate float64, logger *slog.Logger) *Server {
	return &Server{metrics: NewMetrics(), failRate: failRate, log: logger}
}

// statusRecorder captures the status code a handler wrote so we can count it.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// instrument wraps API handlers only. Health and metrics endpoints stay out of
// the SLO so load-balancer probes do not inflate the "good" count.
func (s *Server) instrument(route string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		h(rec, r)
		s.metrics.Observe(route, rec.status, time.Since(start))
	}
}

func (s *Server) handleVitals(w http.ResponseWriter, r *http.Request) {
	if s.failRate > 0 && rand.Float64() < s.failRate {
		s.log.Error("injected failure", "route", "/api/v1/vitals", "fail_rate", s.failRate)
		http.Error(w, `{"error":"upstream unavailable"}`, http.StatusServiceUnavailable)
		return
	}
	reading := Reading{
		PatientID:  "SYN-" + strconv.Itoa(1000+rand.IntN(9000)),
		HeartRate:  60 + rand.IntN(41),
		SpO2:       95 + rand.IntN(6),
		RecordedAt: time.Now().UTC(),
		Version:    version,
	}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(reading)
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !s.ready.Load() {
			http.Error(w, "not ready", http.StatusServiceUnavailable)
			return
		}
		_, _ = w.Write([]byte("ready\n"))
	})
	mux.HandleFunc("GET /metrics", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/plain; version=0.0.4")
		s.metrics.Render(w)
	})
	mux.HandleFunc("GET /api/v1/vitals", s.instrument("/api/v1/vitals", s.handleVitals))
	return mux
}

func main() {
	logger := newLogger()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	s := NewServer(parseFailRate(os.Getenv("FAIL_RATE")), logger)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           s.Routes(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		logger.Info("starting", "port", port, "version", version, "fail_rate", s.failRate)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("server failed", "err", err)
			os.Exit(1)
		}
	}()
	s.ready.Store(true)

	<-ctx.Done()
	// Kubernetes sends SIGTERM, then waits terminationGracePeriodSeconds.
	// Fail readiness first so the Service stops routing to us, then drain.
	s.ready.Store(false)
	logger.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown error", "err", err)
	}
}
