#!/bin/bash
# Simple test to verify chaos injection is working

echo "Starting API instance..."
PORT=8081 INSTANCE_ID=instance-1 node api_instance.js &
INSTANCE_PID=$!
sleep 2

echo ""
echo "Testing normal request (should be fast)..."
time curl -s http://localhost:8081/work > /dev/null

echo ""
echo "Injecting 200ms latency chaos..."
curl -X POST http://localhost:8081/chaos \
  -H "Content-Type: application/json" \
  -d '{"type":"latency","latency":200,"duration":5000}'

echo ""
echo "Testing with chaos (should be slow ~200ms)..."
time curl -s http://localhost:8081/work > /dev/null

echo ""
echo "Waiting for chaos to auto-disable (5 seconds)..."
sleep 6

echo ""
echo "Testing after chaos disabled (should be fast again)..."
time curl -s http://localhost:8081/work > /dev/null

echo ""
echo "Cleaning up..."
kill $INSTANCE_PID
wait 2>/dev/null || true

echo "Test complete!"
