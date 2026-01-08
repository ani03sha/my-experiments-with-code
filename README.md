# My Experiments With Code

Experiments to understand various concepts in detail.

## Downstream Saturation Safe Mitigation
This is a hands-on demonstration of how queueing creates tail latency in distributed systems. Through a minimal API→DB setup, you'll learn:

- Why p99 latency explodes under load (queueing, not slow code)
- How increasing connection pools helps until downstream saturates
- Where bottlenecks actually form in layered architectures
- How to diagnose queue depth using latency distributions
- The "knee" point of diminishing returns for capacity

### Architecture Diagram

![Downstream Saturation Safe Mitigation Architecture](diagrams/downstream_saturation_architecture.png)

### Quick Start

1. Clone and setup

```shell
git clone https://github.com/ani03sha/my-experiments-with-code.git
cd downstream_saturation_safe_mitigation
npm install  # If using package.json
```

2. Start the DB simulator

```shell
node db_simulator.js
# Default: 10 concurrent, 50ms work
# Customize: DB_CONC=5 WORK_MS=100 node db_simulator.js
```

3. Start the API server

```shell
# Small pool (creates API bottleneck)
POOL_SIZE=2 node api_server.js

# Larger pool (moves bottleneck downstream)
POOL_SIZE=20 node api_server.js

# With circuit breaker protection
POOL_SIZE=20 CB_ENABLED=1 node api_server.js
```

4. Run load tests

```shell
# Quick test
wrk -t2 -c100 -d5s --latency http://localhost:3000/work

# Full test with timeout buffer
wrk -t2 -c100 -d10s --timeout 30s --latency http://localhost:3000/work
```

5. View metrics

```shell
# API metrics
curl http://localhost:3000/metrics

# DB metrics
curl http://localhost:5001/metrics

# Health checks
curl http://localhost:3000/health
curl http://localhost:5001/health
```

### Understanding the results

**Expected Patterns**

- POOL_SIZE=2 (API Bottleneck):

```plaintext
RPS: ~37, p99: ~2.0s
API queue: ~98, DB queue: 0
Only 2 concurrent requests → 98 wait in line
```

- POOL_SIZE=10 (Matched Capacity):

```plaintext
RPS: ~190, p99: ~520ms  
API queue: ~90, DB queue: 0
Max throughput reached, but queues still form
```

- POOL_SIZE=50 (Over-provisioned):

```plaintext
RPS: ~190, p99: ~520ms
API queue: ~40, DB queue: ~40
Queue distributes across layers - no throughput gain
```

## Retry Storm Load Amplification

> **"Retries aren't free. Each retry adds load. Too many retries = retry storm = system collapse."**

A hands-on demonstration of how naive retry logic causes cascading failures in distributed systems, and how simple fixes prevent disasters.

### The Problem

Retry storms happen because of a **positive feedback loop**:

1. Downstream service gets slow (5% of requests take 1000ms)
2. Client timeouts fire (100ms timeout)
3. Clients retry immediately
4. **More retries = more load on downstream**
5. **More load = more slow requests**
6. **More slow requests = more timeouts = more retries**
7. **System collapses**

### Quick Start

```bash
# Install dependencies
npm install

# Run the experiment (requires wrk load testing tool)
./run_all_scenarios.sh
```

### Expected Results

```
Scenario             |    Retries |      Queue
---------------------|------------|-----------
Baseline             |          0 |          7
Naive Retries        |        415 |          9
Retry Storm          |       1645 |        115  ⚠️ DISASTER
Backoff+Jitter       |        238 |          7  ✅ 43% better
Lower Max Retries    |        520 |         10
```

#### What This Shows

- **Baseline (no retries)**: Natural queue buildup from slow requests
- **Naive Retries**: 3 retries with immediate retry → 415 total retries
- **Retry Storm**: 5 retries + 50ms timeout → **1645 retries, 115 queue depth** 🔥
- **Backoff+Jitter**: Same 3 retries but with exponential backoff + jitter → 43% fewer retries
- **Lower Max Retries**: Just 2 retries instead of 3 → Still problematic without backoff

### The Key Insight

#### Load Amplification Formula

```
Effective QPS = Incoming QPS × (1 + Average Retries)
```

If you have 100 req/s with 3 retries on 10% of requests:
```
100 req/s × (1 + 0.3) = 130 req/s on downstream
```

But with a retry storm, this becomes exponential:
```
100 req/s × (1 + 16 retries) = 1700 req/s 🔥
```

### Why Tail Latency Explodes First

- **95% of requests** finish fast (50ms)
- **5% are slow** (1000ms) - get queued
- **Retries hit the slow path again**
- **Queue grows** → latency compounds
- **p99 goes vertical while p50 looks fine**

Your users see timeouts while dashboards show "healthy".

### The Fixes

#### 1. Exponential Backoff

Wait longer between retries:
- 1st retry: 50ms
- 2nd retry: 100ms
- 3rd retry: 200ms

```javascript
// api_server.js:138
const baseDelay = 50;
let delay = Math.min(1000, baseDelay * Math.pow(2, attempt - 1));
```

#### 2. Jitter

Add ±50% randomness to prevent "thundering herd":

```javascript
// api_server.js:141
if (JITTER) {
  delay = delay * (0.5 + Math.random());
}
```

#### 3. Bound Retry Counts

Never use unlimited retries. Max 2-3 retries:

```javascript
// api_server.js:10
const RETRIES = 3; // Not 5, not 10, definitely not infinite
```

### Architecture

#### Downstream Service (`downstream.js`)

Simulates a realistic backend:
- **Concurrency limit**: 10 max concurrent requests
- **Fast path**: 50ms latency (95% of requests)
- **Slow path**: 1000ms latency (5% of requests)
- **Error rate**: 1% random errors
- **Queue behavior**: Wait time compounds with queue depth

#### API Server (`api_server.js`)

Configurable retry behavior:
- `RETRIES`: Max retry attempts
- `TIMEOUT_MS`: Request timeout
- `EXP_BACKOFF`: Enable exponential backoff
- `JITTER`: Enable jitter
- `RETRY_BUDGET`: Max retries per second (optional)

#### Load Testing

Uses `wrk` to generate realistic load:
- 2 threads
- 10 concurrent connections
- 10 second test duration per scenario

### How to Run Individual Scenarios

#### Baseline (No Retries)
```bash
./run_baseline.sh
```

#### Naive Retries (3 retries, no backoff)
```bash
RETRIES=3 TIMEOUT_MS=100 node api_server.js &
node downstream.js &
wrk -t2 -c10 -d10s http://localhost:3000/api
```

#### Retry Storm (5 retries, 50ms timeout)
```bash
RETRIES=5 TIMEOUT_MS=50 node api_server.js &
node downstream.js &
wrk -t2 -c10 -d10s http://localhost:3000/api
```

#### Backoff + Jitter (Safe Retries)
```bash
RETRIES=3 TIMEOUT_MS=100 EXP_BACKOFF=true JITTER=true node api_server.js &
node downstream.js &
wrk -t2 -c10 -d10s http://localhost:3000/api
```

### Production Rules

1. **Always bound retry counts** - Max 2-3 retries
2. **Always use exponential backoff** - 50ms, 100ms, 200ms, 400ms...
3. **Always add jitter** - Prevents synchronized retries
4. **Align timeouts with SLOs** - timeout = p99 latency + buffer
5. **Monitor retry rates** - Alert when retry rate > 10%

### The "Aha!" Moment

When you see the retry storm scenario:

- **1645 retries** from just a 5% slow rate
- **115 queue depth** from compounding delays
- **System thrashing** instead of serving requests

Compare to backoff+jitter:
- **238 retries** (85% reduction!)
- **7 queue depth** (93% reduction!)
- **System stable** and recovering

**That's the power of simple fixes.**

**Bottom line**: Never "just add retries." Always bound, backoff, and budget. Retries are necessary but dangerous. Handle with care.
