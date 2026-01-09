-- Only run after backfill is 100% complete and validated
-- Step 1: Ensure no NULLs in the new column
UPDATE users
SET
    full_name = ''
WHERE
    full_name IS NULL;

-- Step 2: Make column non-nullable
ALTER TABLE users
ALTER COLUMN full_name
SET
    NOT NULL;

-- Step 3: Drop old columns (irreversible)
ALTER TABLE users
DROP COLUMN first_name;

ALTER TABLE users
DROP COLUMN last_name;

-- Optional: Add index if needed
CREATE INDEX idx_users_full_name ON users (full_name);