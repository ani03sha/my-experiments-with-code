#!/bin/bash
set -e

echo "=== Cleanup: Kill any existing node processes ==="
pkill -f "node app_v1.js" 2>/dev/null || true
pkill -f "node app_v2.js" 2>/dev/null || true
pkill -f "node traffic_generator.js" 2>/dev/null || true
sleep 1

echo "=== Step 1: Start V1 app ==="
node app_v1.js &
V1_PID=$!

echo "=== Waiting for V1 app to be ready ==="
sleep 3
until curl -s http://localhost:3000/v1/before_stats > /dev/null 2>&1; do
    echo "Waiting for V1 app..."
    sleep 1
done
echo "V1 app is ready!"

echo "=== Step 2: Run expansion migration ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -f /docker-entrypoint-initdb.d/migrate_expand.sql

echo "=== Step 3: Verify expansion succeeded ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -c "\d users" | grep full_name

echo "=== Step 4: Run traffic with expanded schema (30s) ==="
sleep 2
node traffic_generator.js 30 0.0

echo "=== Step 5: Show post-expansion stats ==="
curl -s http://localhost:3000/v1/after_stats | jq .

kill $V1_PID 2>/dev/null
wait $V1_PID 2>/dev/null