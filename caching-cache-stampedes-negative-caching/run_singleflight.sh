#!/bin/bash
OUTPUT_FILE="results/singleflight_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "=== Singleflight Protection Test ==="
echo "Output will be saved to: $OUTPUT_FILE"
echo "Timestamp: $(date)"
echo ""

echo "Starting DB simulator..."
node db_simulator.js > /dev/null 2>&1 &
DB_PID=$!

sleep 2

echo "Starting API server with singleflight cache (TTL=1000ms)..."
CACHE=singleflight CACHE_TTL=1000 node api_server.js > /dev/null 2>&1 &
API_PID=$!

sleep 2

echo "Warming cache..."
curl -s http://localhost:3000/item/42 > /dev/null

echo "Waiting for TTL expiry (1.1 seconds)..."
sleep 1.1

echo ""
echo "Running stampede load with singleflight protection (400 concurrent)..."
wrk -t8 -c400 -d15s --latency http://localhost:3000/item/42

echo ""
echo "=== Singleflight Metrics ==="
echo "API Metrics:"
curl -s http://localhost:3000/metrics | grep -E "(cache_hits|cache_misses|downstream_calls|in_flight_loads|p99_latency)"
echo ""
echo "DB Metrics:"
curl -s http://localhost:3001/metrics | grep -E "(db_active|db_queue|db_requests)"

echo ""
echo "=== Analysis ==="
echo "Singleflight ensures only ~1 DB call per cache miss despite 400 concurrent requests."
echo "Compare downstream_calls here vs the stampede test - should be dramatically lower."
echo "in_flight_loads shows request coalescing is working (should be ~1 during misses)."

kill $API_PID $DB_PID 2>/dev/null
wait 2>/dev/null

echo ""
echo "Test complete. Results saved to: $OUTPUT_FILE"