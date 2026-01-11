#!/bin/bash
OUTPUT_FILE="results/no_cache_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "=== No Cache Test ==="
echo "Output will be saved to: $OUTPUT_FILE"
echo "Timestamp: $(date)"
echo ""

echo "Starting DB simulator..."
node db_simulator.js > /dev/null 2>&1 &
DB_PID=$!

sleep 2

echo "Starting API server with no cache..."
CACHE=off node api_server.js > /dev/null 2>&1 &
API_PID=$!

sleep 2

echo "Running load test (100 concurrent connections, no caching)..."
wrk -t4 -c100 -d15s --latency http://localhost:3000/item/42

echo ""
echo "=== Metrics ==="
echo "API Metrics:"
curl -s http://localhost:3000/metrics | grep -E "(cache|downstream|p99)"
echo ""
echo "DB Metrics:"
curl -s http://localhost:3001/metrics | grep -E "(db_active|db_queue|db_requests)"

echo ""
echo "=== Analysis ==="
echo "Baseline performance with no caching. All requests go directly to DB."
echo "downstream_calls should equal total requests."

kill $API_PID $DB_PID 2>/dev/null
wait 2>/dev/null

echo ""
echo "Test complete. Results saved to: $OUTPUT_FILE"