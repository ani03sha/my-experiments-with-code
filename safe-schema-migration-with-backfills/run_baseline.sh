#!/bin/bash
set -e

echo "=== Cleanup: Kill any existing node processes ==="
pkill -f "node app_v1.js" 2>/dev/null || true
pkill -f "node app_v2.js" 2>/dev/null || true
pkill -f "node traffic_generator.js" 2>/dev/null || true
sleep 1

echo "=== Starting Docker containers ==="
docker-compose up -d

echo "=== Waiting for PostgreSQL to be ready ==="
until docker exec migration_demo_db pg_isready -U postgres > /dev/null 2>&1; do
    echo "Waiting for PostgreSQL..."
    sleep 1
done
echo "PostgreSQL is ready!"

echo "=== Step 1: Initialize database (if not already) ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -f /docker-entrypoint-initdb.d/db_init.sql

echo "=== Step 2: Start V1 app ==="
node app_v1.js &
V1_PID=$!

echo "=== Waiting for V1 app to be ready ==="
sleep 3
until curl -s http://localhost:3000/v1/before_stats > /dev/null 2>&1; do
    echo "Waiting for V1 app..."
    sleep 1
done
echo "V1 app is ready!"

echo "=== Step 3: Run baseline traffic (60s) ==="
node traffic_generator.js 60 0.0

echo "=== Step 4: Show baseline stats (Before schema change) ==="
curl -s http://localhost:3000/v1/before_stats | jq .

echo "=== Step 5: Database schema ==="
docker exec migration_demo_db psql -U postgres -d migration_demo -c "\d users"

kill $V1_PID 2>/dev/null
wait $V1_PID 2>/dev/null