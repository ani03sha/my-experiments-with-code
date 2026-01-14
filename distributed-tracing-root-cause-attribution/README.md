# Distributed Tracing & Root-Cause Attribution Demo

A compact, deterministic demo that teaches **distributed tracing, context propagation, sampling, and latency attribution** across a small multi-service stack.

## Architecture

```
wrk -> service_A (API:3000) -> service_B (worker:3001) -> service_C (db_sim:3002)
                           \-> external_call (simulated)
       trace-collector (9411) <- spans (HTTP POST)
```

### Services

| Service | Port | Role |
|---------|------|------|
| service_a.js | 3000 | API entrypoint, orchestrates calls to B and external APIs |
| service_b.js | 3001 | Mid-tier business logic with CPU-bound work |
| service_c.js | 3002 | Database simulation with variable latency |
| trace_collector.js | 9411 | Collects and stores spans in NDJSON format |

## Prerequisites

- Node.js 18+
- wrk (load testing tool)
- jq (for JSON formatting, optional)

## Installation

```bash
npm install
```

## Quick Start

### 1. Run Baseline Test

```bash
chmod +x *.sh
./run_baseline.sh
```

This will:
- Start the trace collector and all services
- Run `wrk -t4 -c200 -d20s` baseline load test
- Collect metrics and traces
- Output results to `baseline.txt` and `traces_baseline.ndjson`

### 2. Run High Load Test

```bash
./run_high_load.sh
```

This will:
- Run `wrk -t8 -c400 -d60s` to create tail latency
- Generate trace summaries for slowest traces
- Output to `high_load.txt`, `trace_summary.txt`, `traces_high_load.ndjson`

### 3. Demonstrate Sampling Strategies

```bash
./run_sampling.sh
```

Shows three sampling modes:
- **No sampling (100%)**: All spans collected
- **Probabilistic (10%)**: ~10% of traces sampled
- **Head-tail**: 10% base + all slow traces (>100ms threshold)

### 4. View Trace Summaries

```bash
./trace_summary.sh traces.ndjson 5
```

Outputs waterfall views of the top 5 slowest traces.

### 5. Collect Metrics

```bash
./collect_metrics.sh
```

Fetches latency percentiles (p50/p95/p99) from all services.

## Trace Headers

Context propagation uses these HTTP headers:

| Header | Purpose |
|--------|---------|
| `X-Trace-Id` | UUIDv4 trace identifier |
| `X-Span-Id` | 16-char hex span identifier |
| `X-Sampled` | `1` = sample, `0` = drop |

## Span Model

Each span contains:

```json
{
  "trace_id": "uuid-v4",
  "span_id": "hex16",
  "parent_span_id": "hex16 or null",
  "service": "service_a",
  "operation": "handle_api_request",
  "start_ts_iso": "2024-01-15T10:00:00.000Z",
  "end_ts_iso": "2024-01-15T10:00:00.150Z",
  "duration_ms": 150,
  "tags": { "key": "value" },
  "sampled": true
}
```

## wrk Commands

**Baseline:**
```bash
wrk -t4 -c200 -d20s --latency http://localhost:3000/work
```

**High load (creates tail latency):**
```bash
wrk -t8 -c400 -d60s --latency http://localhost:3000/work
```

> **Why -c400 creates tails:** With 400 concurrent connections but limited downstream capacity, requests queue up. Connection queueing + variable DB latency compounds into significant p99 spikes.

## Validation

### 1. Trace Propagation
For any trace, `trace_summary.sh` should show spans across all three services with correct parent-child relationships:

```
service_a.handle_api_request - 150ms
  service_a.call_service_b - 80ms
    service_b.process_business_logic - 75ms
      service_b.call_service_c - 40ms
        service_c.db_query - 35ms
  service_a.call_external_api - 25ms
```

### 2. Root Cause Attribution
The **dominant span** in slow traces identifies the bottleneck (usually `service_c.db_query` during high load due to simulated DB tail latency).

### 3. Sampling Behavior
- **100% sampling**: All traces captured (high volume)
- **Probabilistic 10%**: ~10% of traces (may miss slow requests)
- **Head-tail**: ~10% base + guaranteed slow traces (best for debugging)

## API Endpoints

### Service A (port 3000)
- `GET /work` - Main endpoint that orchestrates the distributed call chain
- `GET /trace/:traceId` - Fetch spans for a specific trace
- `GET /metrics` - Latency percentiles and request counts
- `GET /health` - Health check

### Service B (port 3001)
- `POST /work` - Process business logic
- `GET /metrics` - Latency percentiles
- `GET /health` - Health check

### Service C (port 3002)
- `POST /work` - Simulate DB query
- `GET /metrics` - Latency percentiles
- `GET /health` - Health check

### Trace Collector (port 9411)
- `POST /ingest` - Receive spans (NDJSON appended to `traces.ndjson`)
- `GET /trace/:traceId` - Retrieve all spans for a trace

## Key Concepts

### Context Propagation
Trace context must be explicitly propagated via HTTP headers. Without instrumentation, async callbacks and worker threads lose context. The `instrumentation.js` helper provides:
- `startSpan()` - Create a new span with optional parent context
- `propagateHeaders()` - Convert context to HTTP headers
- `extractHeaders()` - Parse incoming headers to context
- `instrumentHTTPCall()` - Wrap fetch calls with automatic span creation
- `instrumentAsync()` - Wrap async functions with spans

### Sampling Tradeoffs
- **No sampling**: Full fidelity but high storage/overhead
- **Probabilistic**: Reduces volume but may miss rare slow requests
- **Head-tail**: Best balance - captures slow traces that matter most for debugging while reducing volume

### Traces vs Metrics
- **Metrics**: Tell you there IS a problem (p99 spiked)
- **Traces**: Tell you WHERE the problem is (which service/operation)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| No spans in collector | Verify services POST to `http://localhost:9411/ingest` and set `X-Trace-Id` header |
| Flat spans (no hierarchy) | Ensure outbound calls include `X-Span-Id` and child spans use `parent_span_id` from header |
| Sampling drops slow traces | Enable head-tail sampling or set probability to 100% temporarily |
| Services won't start | Check ports 3000, 3001, 3002, 9411 are available |

## Files

| File | Description |
|------|-------------|
| `service_a.js` | API entrypoint with worker thread support |
| `service_b.js` | Mid-tier service with CPU-bound simulation |
| `service_c.js` | DB simulator with configurable latency |
| `trace_collector.js` | NDJSON-based span collector |
| `trace_summary.js` | CLI/server for trace analysis |
| `instrumentation.js` | Span creation and propagation helpers |
| `run_baseline.sh` | Baseline load test script |
| `run_high_load.sh` | High load test with trace analysis |
| `run_sampling.sh` | Sampling strategy demonstration |
| `trace_summary.sh` | Wrapper for trace_summary.js |
| `collect_metrics.sh` | Fetch metrics from all services |

## Twitter Thread Template

1. **Hook**: "Your p99 jumped — here's how tracing shows which service is responsible."
2. **Setup**: Architecture diagram + collector description
3. **Baseline**: Paste `baseline.txt` p50/p95/p99 lines
4. **Slow trace**: Paste waterfall from `trace_summary.txt` showing dominant span
5. **Sampling**: Show span counts for 100% vs probabilistic vs head-tail
6. **Takeaway**: Instrument all service boundaries; use head-tail sampling in prod
7. **Caveats**: Tracing adds ~1-5ms overhead; mask PII in span tags
8. **CTA**: "Run `./trace_summary.sh` and paste your slowest trace — I'll interpret it"
