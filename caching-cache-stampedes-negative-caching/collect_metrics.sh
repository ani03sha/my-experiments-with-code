#!/bin/bash
echo "=== Metrics Collection ==="

echo "1. Starting fresh instances..."
node db_simulator.js &
DB_PID=$!
sleep 1

CACHE=naive CACHE_TTL=1000 node api_server.js &
API_PID=$!
sleep 2

echo "2. Baseline metrics before load:"
curl -s http://localhost:3000/metrics
echo "---"
curl -s http://localhost:3001/metrics

echo -e "\n3. Metrics during stampede (5 seconds):"
wrk -t8 -c400 -d5s http://localhost:3000/item/42 > /dev/null &
sleep 1
echo "=== During peak ==="
curl -s http://localhost:3000/metrics | grep -E "(cache_misses|downstream_calls|api_queue|p99)"
curl -s http://localhost:3001/metrics | grep -E "(db_active|db_queue)"

sleep 5
echo -e "\n4. Metrics after stampede:"
curl -s http://localhost:3000/metrics | grep -E "(cache_misses|downstream_calls|p99)"
curl -s http://localhost:3001/metrics | grep "db_requests"

kill $API_PID $DB_PID
wait