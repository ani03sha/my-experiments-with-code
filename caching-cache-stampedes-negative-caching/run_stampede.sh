#!/bin/bash
OUTPUT_FILE="results/stampede_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "=== Cache Stampede Test ==="
echo "Output will be saved to: $OUTPUT_FILE"
echo "Timestamp: $(date)"
echo ""

echo "Starting DB simulator..."
node db_simulator.js > /dev/null 2>&1 &
DB_PID=$!

sleep 2

echo "Starting API server with naive cache (TTL=1000ms)..."
CACHE=naive CACHE_TTL=1000 node api_server.js > /dev/null 2>&1 &
API_PID=$!

sleep 2

echo "Warming cache with initial request..."
curl -s "http://localhost:3000/item/42" > /dev/null

echo "Waiting for synchronized TTL expiry (1.1 seconds)..."
sleep 1.1  # Cache expires, all concurrent requests will miss

echo ""
echo "Running stampede load test (400 concurrent connections hitting expired cache)..."
wrk -t8 -c400 -d15s --latency http://localhost:3000/item/42

echo ""
echo "=== Stampede Metrics ==="
echo "API Metrics:"
curl -s http://localhost:3000/metrics | grep -E "(cache_hits|cache_misses|downstream_calls|p99_latency)"
echo ""
echo "DB Metrics:"
curl -s http://localhost:3001/metrics | grep -E "(db_active|db_queue|db_requests)"

echo ""
echo "=== Analysis ==="
echo "Notice the high downstream_calls and p99_latency spike during stampede."
echo "All concurrent requests hit an expired cache simultaneously, causing a thundering herd."

kill $API_PID $DB_PID 2>/dev/null
wait 2>/dev/null

echo ""
echo "Test complete. Results saved to: $OUTPUT_FILE"