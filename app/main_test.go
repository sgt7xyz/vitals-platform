package main

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func testServer(failRate float64) *Server {
	s := NewServer(failRate, slog.New(slog.NewTextHandler(io.Discard, nil)))
	s.ready.Store(true)
	return s
}

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestHealthz(t *testing.T) {
	if got := get(t, testServer(0).Routes(), "/healthz").Code; got != http.StatusOK {
		t.Fatalf("healthz = %d, want 200", got)
	}
}

func TestReadyzFailsBeforeReady(t *testing.T) {
	s := testServer(0)
	s.ready.Store(false)
	if got := get(t, s.Routes(), "/readyz").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("readyz = %d, want 503", got)
	}
}

func TestVitalsReturnsReading(t *testing.T) {
	rec := get(t, testServer(0).Routes(), "/api/v1/vitals")
	if rec.Code != http.StatusOK {
		t.Fatalf("vitals = %d, want 200", rec.Code)
	}
	var r Reading
	if err := json.Unmarshal(rec.Body.Bytes(), &r); err != nil {
		t.Fatalf("bad JSON: %v", err)
	}
	if r.HeartRate < 60 || r.HeartRate > 100 {
		t.Errorf("heart rate %d out of range", r.HeartRate)
	}
	if !strings.HasPrefix(r.PatientID, "SYN-") {
		t.Errorf("patient id %q should be synthetic", r.PatientID)
	}
}

func TestFailRateInjects503AndCounts5xx(t *testing.T) {
	s := testServer(1.0)
	h := s.Routes()
	if got := get(t, h, "/api/v1/vitals").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("vitals = %d, want 503", got)
	}
	body := get(t, h, "/metrics").Body.String()
	want := `vitals_http_requests_total{route="/api/v1/vitals",code_class="5xx"} 1`
	if !strings.Contains(body, want) {
		t.Fatalf("metrics missing %q\n%s", want, body)
	}
}

func TestHealthEndpointsAreNotCounted(t *testing.T) {
	s := testServer(0)
	h := s.Routes()
	get(t, h, "/healthz")
	get(t, h, "/readyz")
	if body := get(t, h, "/metrics").Body.String(); strings.Contains(body, "/healthz") {
		t.Fatalf("health checks leaked into SLO metrics:\n%s", body)
	}
}

func TestCodeClass(t *testing.T) {
	cases := map[int]string{200: "2xx", 404: "4xx", 503: "5xx", 42: "unknown"}
	for code, want := range cases {
		if got := codeClass(code); got != want {
			t.Errorf("codeClass(%d) = %q, want %q", code, got, want)
		}
	}
}

func TestParseFailRate(t *testing.T) {
	cases := map[string]float64{"": 0, "abc": 0, "-1": 0, "0.25": 0.25, "5": 1}
	for in, want := range cases {
		if got := parseFailRate(in); got != want {
			t.Errorf("parseFailRate(%q) = %v, want %v", in, got, want)
		}
	}
}
