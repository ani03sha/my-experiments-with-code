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