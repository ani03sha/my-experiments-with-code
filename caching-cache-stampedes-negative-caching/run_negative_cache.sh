#!/bin/bash
OUTPUT_FILE="results/negative_cache_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "=== Negative Caching Test ==="
echo "Output will be saved to: $OUTPUT_FILE"
echo "Timestamp: $(date)"
echo ""

echo "Starting DB simulator..."
node db_simulator.js > /dev/null 2>&1 &
DB_PID=$!

sleep 2

echo "Enabling DB error mode (10% error rate)..."
curl -s -X POST "http://localhost:3001/error_mode?enable=true"
echo ""

echo "Starting API server with negative caching..."
CACHE=negative CACHE_TTL=2000 node api_server.js > /dev/null 2>&1 &
API_PID=$!

sleep 2

echo "Testing negative caching behavior..."
echo "First request (will error and be cached):"
curl -s http://localhost:3000/item/fail_key
echo ""

echo ""
echo "Running load test (errors will be cached for 1 second)..."
wrk -t4 -c200 -d15s --latency http://localhost:3000/item/fail_key

echo ""
echo "=== Negative Caching Metrics ==="
echo "API Metrics:"
curl -s http://localhost:3000/metrics | grep -E "(cache_hits|cache_misses|downstream_calls|p99_latency)"
echo ""
echo "DB Metrics:"
curl -s http://localhost:3001/metrics | grep -E "(db_requests|db_queue)"

echo ""
echo "=== Analysis ==="
echo "With negative caching, error responses are cached for 1 second."
echo "This prevents hammering the DB with repeated requests for failing keys."
echo "downstream_calls should be much lower than total requests due to error caching."

echo ""
echo "Disabling error mode..."
curl -s -X POST "http://localhost:3001/error_mode?enable=false" > /dev/null

kill $API_PID $DB_PID 2>/dev/null
wait 2>/dev/null

echo ""
echo "Test complete. Results saved to: $OUTPUT_FILE"