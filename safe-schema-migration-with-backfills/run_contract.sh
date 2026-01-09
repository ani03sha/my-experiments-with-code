#!/bin/bash
set -e

echo "=== Cleanup: Kill any existing node processes ==="
pkill -f "node app_v1.js" 2>/dev/null || true
pkill -f "node app_v2.js" 2>/dev/null || true
pkill -f "node traffic_generator.js" 2>/dev/null || true
sleep 1

echo "=== Step 1: Validate backfill completion ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -c "
    SELECT 
        COUNT(*) as total,
        COUNT(full_name) as with_full_name,
        COUNT(CASE WHEN full_name IS NULL THEN 1 END) as null_full_names
    FROM users
"

echo "=== Step 2: Start V2-only app (no dual-write) ==="
DUAL_WRITE=0 node app_v2.js &
V2_PID=$!

echo "=== Waiting for V2 app to be ready ==="
sleep 3
until curl -s http://localhost:3001/v2/stats > /dev/null 2>&1; do
    echo "Waiting for V2 app..."
    sleep 1
done
echo "V2 app is ready!"

echo "=== Step 3: Run contraction migration ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -f /docker-entrypoint-initdb.d/migrate_contract.sql

echo "=== Step 4: Verify contraction ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -c "\d users"

echo "=== Step 5: Run traffic on V2 only (30s) ==="
node traffic_generator.js 30 1.0  # 100% V2 traffic

echo "=== Step 6: Final stats ==="
curl -s http://localhost:3001/v2/stats | jq .

kill $V2_PID 2>/dev/null
wait $V2_PID 2>/dev/null