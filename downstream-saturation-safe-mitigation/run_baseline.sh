#!/bin/bash
# Baseline: API Bottleneck
set -e

echo "=== Baseline: API bottleneck (POOL_SIZE=2, DB fast mode) ==="

# Kill any existing processes
pkill -f "node db_simulator.js" || true
pkill -f "node api_server.js" || true
sleep 1

# Start DB with MODERATE work (not too fast, not too slow)
export DB_MODE=constrained
export DB_CONC=10
export DB_MEAN_MS=50    # 50ms work - enough to see queueing
export DB_JITTER_MS=20
node db_simulator.js > logs/baseline_db.log 2>&1 &
DB_PID=$!
echo "DB started (PID: $DB_PID) with 50ms work"

# Start API with small pool
export POOL_SIZE=2
export CB_ENABLED=0
node api_server.js > logs/baseline_api.log 2>&1 &
API_PID=$!
echo "API Started (PID: $API_PID)"

# Wait for services
echo "Services warming up..."
sleep 3


echo "Testing connectivity..."
for i in {1..3}; do
    curl -s http://localhost:3000/health && echo " ✓ API healthy" || echo " ✗ API not ready"
    curl -s http://localhost:5001/health && echo " ✓ DB healthy" || echo " ✗ DB not ready"
    sleep 1
done

echo ""
echo "Quick test - should see queueing:"
echo "--------------------------------"
time curl -s "http://localhost:3000/work?test=1" | jq -r '.ok,.queueLength,.active' 2>/dev/null || \
    curl -s "http://localhost:3000/work?test=1"

echo ""
echo "Running wrk load test..."
echo "Expected: High p99 (queueing), api_queue > 0, api_active = 2"
echo ""

mkdir -p results
# Use FEWER connections initially to see queueing clearly
# Run wrk with parameters that FORCE queueing
# -t2: 2 threads (match your CPU cores)
# -c50: 50 connections (more than pool size of 2)
# -d10s: 10 seconds
# --timeout 10s: Give wrk longer timeout
wrk -t2 -c50 -d10s --timeout 10s --latency http://localhost:3000/work > results/baseline.txt 2>&1

echo "Load test complete. Collecting metrics..."
curl -s http://localhost:3000/metrics > results/baseline_api_metrics.txt
curl -s http://localhost:5001/metrics > results/baseline_db_metrics.txt

echo ""
echo "=== RESULTS SUMMARY ==="
echo ""

echo "1. Latency Distribution (from wrk):"
echo "-----------------------------------"
grep -A5 "Latency Distribution" results/baseline.txt || echo "No latency data found"

echo ""
echo "2. Throughput:"
echo "--------------"
grep -E "(Requests/sec|Transfer/sec|Socket errors|Non-2xx)" results/baseline.txt || echo "No throughput data"

echo ""
echo "3. API Metrics (key indicators):"
echo "--------------------------------"
echo "Pool stats:"
grep -E "(api_active|api_queue|api_available|api_pool_size)" results/baseline_api_metrics.txt
echo ""
echo "Request stats:"
grep -E "(api_total|api_successful|api_error|api_timeout)" results/baseline_api_metrics.txt

echo ""
echo "4. DB Metrics:"
echo "--------------"
grep -E "(db_active|db_queue|db_total|db_concurrency)" results/baseline_db_metrics.txt

echo ""
echo "5. Health Check (current state):"
echo "--------------------------------"
curl -s http://localhost:3000/health | jq '.' 2>/dev/null || curl -s http://localhost:3000/health

# Check for errors in logs
echo ""
echo "6. Error Analysis:"
echo "------------------"
if tail -20 logs/baseline_api.log | grep -i "error\|timeout\|fail"; then
    echo "Found errors in API log"
else
    echo "No significant errors in API log"
fi

# Cleanup
echo ""
echo "Cleaning up..."
kill $API_PID $DB_PID 2>/dev/null || true
sleep 1

echo ""
echo "=== Experiment Complete ==="
echo "Check results/baseline.txt for full wrk output"
echo "Check results/baseline_api_metrics.txt for API metrics"