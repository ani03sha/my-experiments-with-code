#!/bin/bash
set -e

echo "=== Validation Queries ==="

echo "1. Count NULL full_names:"
docker exec migration_demo_db psql -U postgres -d migration_demo -c "
    SELECT COUNT(*) as null_full_names FROM users WHERE full_name IS NULL;
"

echo "2. Sample rows with potential mismatches:"
docker exec migration_demo_db psql -U postgres -d migration_demo -c "
    SELECT 
        id, 
        first_name, 
        last_name, 
        full_name,
        (first_name || ' ' || last_name) as computed
    FROM users 
    WHERE first_name IS NOT NULL 
      AND last_name IS NOT NULL
      AND full_name IS NOT NULL
      AND full_name != TRIM(first_name || ' ' || last_name)
    LIMIT 5;
"

echo "3. Migration completeness:"
docker exec migration_demo_db psql -U postgres -d migration_demo -c "
    SELECT 
        COUNT(*) as total,
        COUNT(full_name) as with_full_name,
        ROUND(COUNT(full_name) * 100.0 / COUNT(*), 2) as percent_complete
    FROM users;
"

echo "4. Column existence check:"
docker exec migration_demo_db psql -U postgres -d migration_demo -c "
    SELECT column_name, data_type, is_nullable
    FROM information_schema.columns 
    WHERE table_name = 'users' 
    ORDER BY ordinal_position;
"