#!/bin/bash
# Increase pool size to match DB capacity
set -e

echo "=== Increasing pool size (POOL_SIZE=5, DB_CONNECTIONS=5) ==="

# Kill any existing processes
pkill -f "node db_simulator.js" || true
pkill -f "node api_server.js" || true
sleep 1

# Start DB with moderate concurrency
export DB_MODE=constrained
export DB_CONNECTIONS=5
node db_simulator.js > logs/db_increase_pool.log 2>&1 &
Db_PID=$!
echo "DB Started (PID: $DB_PID)"

# Start API with matching pool
export POOL_SIZE=5
export CB_ENABLED=0
node api_server.js > logs/api_increase_pool.log 2>&1 &
API_PID=$!
echo "API Started (PID: $API_PID)"

# Wait for services
sleep 2
echo "Services warming up..."

# Quick health check
curl -s http://localhost:3000/health | grep -q "healthy" && echo "API Healthy" || echo "API not ready"
curl -s http://localhost:5001/health | grep -q "healthy" && echo "DB Healthy" || echo "DB not ready"

echo "Running load test..."
wrk -t4 -c200 -d15s --latency http://localhost:3000/work > results/increase_pool.txt 2>&1

echo "Load test complete. Collecting metrics..."
curl -s http://locahost:3000/metrics > results/increase_pool_api_metrics.txt
curl -s http://localhost:5001/metrics > results/increase_pool_db_metrics.txt

echo "Increase pool results:"
echo "--------------"
tail -n 10 results/increase_pool.txt

# Cleanup
echo "Cleaning up..."
kill $API_PID $DB_PID 2>/dev/null || true
kill $API_PID $DB_PID 2>/dev/null || true

echo "=== Increase pool experiment complete ==="