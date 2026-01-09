#!/bin/bash
set -e

echo "=== Cleanup: Kill any existing node processes ==="
pkill -f "node app_v1.js" 2>/dev/null || true
pkill -f "node app_v2.js" 2>/dev/null || true
pkill -f "node traffic_generator.js" 2>/dev/null || true
pkill -f "node backfill.js" 2>/dev/null || true
sleep 1

echo "=== Step 1: Start V1 app and V2 app (dual-write) ==="
node app_v1.js &
V1_PID=$!

DUAL_WRITE=1 node app_v2.js &
V2_PID=$!

echo "=== Waiting for apps to be ready ==="
sleep 3
until curl -s http://localhost:3000/v1/after_stats > /dev/null 2>&1; do
    echo "Waiting for V1 app..."
    sleep 1
done
until curl -s http://localhost:3001/v2/stats > /dev/null 2>&1; do
    echo "Waiting for V2 app..."
    sleep 1
done
echo "Both apps are ready!"

echo "=== Step 2: Show pre-backfill state ==="
echo "V1 stats:"
curl -s http://localhost:3000/v1/after_stats | jq .
echo "V2 stats:"
curl -s http://localhost:3001/v2/stats | jq .

echo "=== Step 3: Run backfill with live traffic (2 mins) ==="
# Clean up any stale progress file from previous runs
rm -f .backfill_progress

node traffic_generator.js 120 0.2 &  # 20% traffic to V2
TRAFFIC_PID=$!

node backfill.js

echo "=== Step 4: Show post-backfill state ==="
kill $TRAFFIC_PID 2>/dev/null
wait $TRAFFIC_PID 2>/dev/null

echo "V1 stats:"
curl -s http://localhost:3000/v1/after_stats | jq .
echo "V2 stats:"
curl -s http://localhost:3001/v2/stats | jq .

kill $V1_PID $V2_PID 2>/dev/null
wait $V1_PID $V2_PID 2>/dev/null