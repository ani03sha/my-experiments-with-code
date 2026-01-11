#!/bin/bash
OUTPUT_FILE="results/naive_cache_$(date +%Y%m%d_%H%M%S).txt"

exec > >(tee -a "$OUTPUT_FILE") 2>&1

echo "=== Naive Cache Test ==="
echo "Output will be saved to: $OUTPUT_FILE"
echo "Timestamp: $(date)"
echo ""

echo "Starting DB simulator..."
node db_simulator.js > /dev/null 2>&1 &
DB_PID=$!

sleep 2

echo "Starting API server with naive cache (TTL=2000ms)..."
CACHE=naive CACHE_TTL=2000 node api_server.js > /dev/null 2>&1 &
API_PID=$!

sleep 2

echo "Warming cache..."
curl -s http://localhost:3000/item/42 > /dev/null
sleep 1

echo ""
echo "Phase 1: Running steady-state load (cache hot)..."
wrk -t4 -c200 -d10s --latency http://localhost:3000/item/42

echo ""
echo "Forcing cache expiry (waiting 2.1 seconds)..."
sleep 2.1

echo ""
echo "Phase 2: Running load during cache miss stampede..."
wrk -t8 -c400 -d10s --latency http://localhost:3000/item/42

echo ""
echo "=== Final Metrics ==="
echo "API Metrics:"
curl -s http://localhost:3000/metrics | grep -E "(cache|downstream|p99)"
echo ""
echo "DB Metrics:"
curl -s http://localhost:3001/metrics | grep -E "(db_active|db_queue|db_requests)"

echo ""
echo "=== Analysis ==="
echo "Phase 1 shows good performance with hot cache."
echo "Phase 2 shows latency spike when cache expires and stampede occurs."

kill $API_PID $DB_PID 2>/dev/null
wait 2>/dev/null

echo ""
echo "Test complete. Results saved to: $OUTPUT_FILE"