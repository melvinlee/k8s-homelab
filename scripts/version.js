// k6 load-test script — exercises a simple HTTP endpoint and streams metrics
// to Prometheus via remote-write.
//
// Prerequisites:
//   1. Install k6: https://k6.io/docs/get-started/installation/
//   2. Import Grafana dashboard ID 18030 ("k6 Prometheus") at
//      http://grafana.home — use the Grafana UI: Dashboards → Import → 18030.
//
// Run locally (metrics to stdout only):
//   k6 run scripts/version.js
//
// Run with Prometheus remote-write (native histograms required for latency panels):
//   K6_PROMETHEUS_RW_SERVER_URL=http://prometheus.home/api/v1/write \
//   K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true \
//   k6 run --out experimental-prometheus-rw scripts/version.js
//
// K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true sends Trend metrics
// (http_req_duration, http_req_waiting, etc.) as native Prometheus histograms
// instead of flat _p99 gauges — required for dashboard 18030 latency panels.
// Prometheus 2.40+ / 3.x supports native histograms without extra flags.
//
// Environment variables:
//   BASE_URL  — full URL to test (default: http://localhost/)

import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://localhost/";

export const options = {
  vus: 10,
  duration: "30s",
};

export default function () {
  const res = http.get(BASE_URL);

  check(res, {
    "status is 200": (r) => r.status === 200,
    "response time < 500ms": (r) => r.timings.duration < 500,
  });

  sleep(1);
}
