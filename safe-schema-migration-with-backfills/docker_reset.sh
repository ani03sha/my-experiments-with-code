#!/bin/bash
echo "Stopping and removing containers..."
docker-compose down -v

echo "Removing migration progress file..."
rm -f .backfill_progress

echo "Starting fresh..."
docker-compose up -d

echo "Waiting for PostgreSQL to be ready..."
sleep 5

echo "Checking status..."
docker exec migration_demo_db psql -U postgres -d migration_demo -c "SELECT COUNT(*) FROM users;"