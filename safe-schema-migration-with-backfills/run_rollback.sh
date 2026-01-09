#!/bin/bash
set -e

echo "=== Cleanup: Kill any existing node processes ==="
pkill -f "node app_v1.js" 2>/dev/null || true
pkill -f "node app_v2.js" 2>/dev/null || true
pkill -f "node traffic_generator.js" 2>/dev/null || true
pkill -f "node backfill.js" 2>/dev/null || true
sleep 1

echo "=== Simulating backfill failure ==="
echo "=== Step 1: Reset to post-expansion state ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -c "UPDATE users SET full_name = NULL;"
docker exec migration_demo_db psql -U postgres -d migration_demo -c "DELETE FROM users WHERE id > 3;"

echo "=== Step 2: Start apps ==="
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

echo "=== Step 3: Simulate failed backfill (kill mid-way) ==="
# Clean up any stale progress file from previous runs
rm -f .backfill_progress

node traffic_generator.js 300 0.3 &
TRAFFIC_PID=$!

# Start backfill but interrupt it
node backfill.js &
BACKFILL_PID=$!
sleep 5
kill $BACKFILL_PID 2>/dev/null
echo "Backfill interrupted!"

echo "=== Step 4: Show progress file ==="
cat .backfill_progress 2>/dev/null || echo "No progress file"

echo "=== Step 5: Resume backfill ==="
node backfill.js

echo "=== Step 6: Clean up ==="
kill $TRAFFIC_PID $V1_PID $V2_PID 2>/dev/null
wait $TRAFFIC_PID $V1_PID $V2_PID 2>/dev/null
rm -f .backfill_progress