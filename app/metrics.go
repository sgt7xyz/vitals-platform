package main

import (
	"fmt"
	"io"
	"sort"
	"strconv"
	"sync"
	"time"
)

// A tiny, dependency-free Prometheus exporter. In production you would use
// github.com/prometheus/client_golang; writing it by hand shows what the
// text exposition format actually is, which is a good interview talking point.

var latencyBuckets = []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1}

type counterKey struct {
	route     string
	codeClass string
}

type histogram struct {
	counts []uint64 // cumulative per bucket, plus +Inf at the end
	sum    float64
	count  uint64
}

type Metrics struct {
	mu        sync.Mutex
	requests  map[counterKey]uint64
	latencies map[string]*histogram
}

func NewMetrics() *Metrics {
	return &Metrics{
		requests:  map[counterKey]uint64{},
		latencies: map[string]*histogram{},
	}
}

// codeClass turns 503 into "5xx". The SLO filters on this label.
func codeClass(code int) string {
	if code < 100 || code > 599 {
		return "unknown"
	}
	return strconv.Itoa(code/100) + "xx"
}

func (m *Metrics) Observe(route string, code int, d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.requests[counterKey{route, codeClass(code)}]++

	h, ok := m.latencies[route]
	if !ok {
		h = &histogram{counts: make([]uint64, len(latencyBuckets)+1)}
		m.latencies[route] = h
	}
	secs := d.Seconds()
	for i, upper := range latencyBuckets {
		if secs <= upper {
			h.counts[i]++
		}
	}
	h.counts[len(latencyBuckets)]++ // +Inf
	h.sum += secs
	h.count++
}

func (m *Metrics) Render(w io.Writer) {
	m.mu.Lock()
	defer m.mu.Unlock()

	fmt.Fprintln(w, "# HELP vitals_http_requests_total API requests by route and status class.")
	fmt.Fprintln(w, "# TYPE vitals_http_requests_total counter")
	keys := make([]counterKey, 0, len(m.requests))
	for k := range m.requests {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].route != keys[j].route {
			return keys[i].route < keys[j].route
		}
		return keys[i].codeClass < keys[j].codeClass
	})
	for _, k := range keys {
		fmt.Fprintf(w, "vitals_http_requests_total{route=%q,code_class=%q} %d\n", k.route, k.codeClass, m.requests[k])
	}

	fmt.Fprintln(w, "# HELP vitals_http_request_duration_seconds API request latency.")
	fmt.Fprintln(w, "# TYPE vitals_http_request_duration_seconds histogram")
	routes := make([]string, 0, len(m.latencies))
	for r := range m.latencies {
		routes = append(routes, r)
	}
	sort.Strings(routes)
	for _, r := range routes {
		h := m.latencies[r]
		for i, upper := range latencyBuckets {
			fmt.Fprintf(w, "vitals_http_request_duration_seconds_bucket{route=%q,le=%q} %d\n", r, strconv.FormatFloat(upper, 'f', -1, 64), h.counts[i])
		}
		fmt.Fprintf(w, "vitals_http_request_duration_seconds_bucket{route=%q,le=\"+Inf\"} %d\n", r, h.counts[len(latencyBuckets)])
		fmt.Fprintf(w, "vitals_http_request_duration_seconds_sum{route=%q} %g\n", r, h.sum)
		fmt.Fprintf(w, "vitals_http_request_duration_seconds_count{route=%q} %d\n", r, h.count)
	}
}
