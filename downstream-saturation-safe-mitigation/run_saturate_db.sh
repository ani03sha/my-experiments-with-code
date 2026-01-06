#!/bin/bash
# Overwhelm downstream DB
set -e

echo "=== Saturate downstream DB (POOL_SIZE=20, DB_CONNECTIONS=3) ==="

# Kill any existing processes
pkill -f "node db_simulator.js" || true
pkill -f "node api_server.js" || true
sleep 1

# Start DB with moderate concurrency
export DB_MODE=constrained
export DB_CONNECTIONS=3
export DB_MEAN_MS=200 # Slower DB
node db_simulator.js > logs/db_saturate.log 2>&1 &
Db_PID=$!
echo "DB Started (PID: $DB_PID)"

# Start API with matching pool
export POOL_SIZE=20
export CB_ENABLED=0
node api_server.js > logs/api_saturate.log 2>&1 &
API_PID=$!
echo "API Started (PID: $API_PID)"

# Wait for services
sleep 2
echo "Services warming up..."

# Quick health check
curl -s http://localhost:3000/health | grep -q "healthy" && echo "API Healthy" || echo "API not ready"
curl -s http://localhost:5001/health | grep -q "healthy" && echo "DB Healthy" || echo "DB not ready"

echo "Running aggressive load test..."
wrk -t4 -c200 -d30s --latency http://localhost:3000/work > results/saturate_db.txt 2>&1

echo "Load test complete. Collecting metrics..."
curl -s http://locahost:3000/metrics > results/saturate_api_metrics.txt
curl -s http://localhost:5001/metrics > results/saturate_db_metrics.txt

echo "Saturation results:"
echo "--------------"
tail -n 10 results/saturate_db.txt

# Cleanup
echo "Cleaning up..."
kill $API_PID $DB_PID 2>/dev/null || true
kill $API_PID $DB_PID 2>/dev/null || true

echo "=== Saturation experiment complete ==="