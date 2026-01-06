#!/bin/bash
# Circuit breaker protection
set -e

echo "=== Circuit breaker protection (POOL_SIZE=10, DB_CONNECTIONS=2, CB enabled) ==="

# Kill any existing processes
pkill -f "node db_simulator.js" || true
pkill -f "node api_server.js" || true
sleep 1

# Start DB with very limited concurrency
export DB_MODE=constrained
export DB_CONNECTIONS=2
export DB_MEAN_MS=150 # Slower DB
node db_simulator.js > logs/db_cb.log 2>&1 &
Db_PID=$!
echo "DB Started (PID: $DB_PID)"

# Start API with matching pool
export POOL_SIZE=10
export CB_ENABLED=1
node api_server.js > logs/api_cb.log 2>&1 &
API_PID=$!
echo "API Started (PID: $API_PID)"

# Wait for services
sleep 2
echo "Services warming up..."

# Quick health check
curl -s http://localhost:3000/health | grep -q "healthy" && echo "API Healthy" || echo "API not ready"
curl -s http://localhost:5001/health | grep -q "healthy" && echo "DB Healthy" || echo "DB not ready"

echo "Running load test with circuit breaker..."
wrk -t4 -c200 -d20s --latency http://localhost:3000/work > results/with_cb.txt 2>&1

echo "Load test complete. Collecting metrics..."
curl -s http://locahost:3000/metrics > results/with_cb_api_metrics.txt
curl -s http://localhost:5001/metrics > results/with_cb_db_metrics.txt

echo "Circuit breaker results:"
echo "--------------"
tail -n 10 results/with_cb.txt

# Check if circuit breaker opened
if grep -q "api_cb_open 1" results/with_cb_api_metrics.txt; then
    echo "Circuit breaker opened during test"
else
    echo "Circuit breaker did not open (may need lower threshold)"
fi

# Cleanup
echo "Cleaning up..."
kill $API_PID $DB_PID 2>/dev/null || true
kill $API_PID $DB_PID 2>/dev/null || true

echo "=== Circuit breaker experiment complete ==="