-- Add nullable column under new schema (safe under live traffic)
ALTER TABLE users
ADD COLUMN full_name VARCHAR(255);

COMMENT ON COLUMN users.full_name IS 'v2: derived from first_name + last_name, populated by backfill';