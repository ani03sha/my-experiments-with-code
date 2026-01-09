// Idempotent backfill script
const { Pool } = require('pg');
const fs = require('fs').promises;
const path = require('path');
require('dotenv').config();

const pool = new Pool({
    host: 'localhost',
    database: 'migration_demo',
    user: process.env.PGUSER || 'postgres',
    password: process.env.PGPASSWORD || 'postgres',
    port: 5432
});

const PROGRESS_FILE = path.join(__dirname, '.backfill_progress');
const CHUNK_SIZE = 50;
const DELAY_MS = 100; // Small delay between chunks for smoother IO

async function getLastProcessedId() {
    try {
        const data = await fs.readFile(PROGRESS_FILE, 'utf8');
        return parseInt(data.trim(), 10) || 0;
    } catch {
        return 0; // File doesn't exist, start from beginning
    }
}

async function saveProgress(id) {
    await fs.writeFile(PROGRESS_FILE, id.toString(), 'utf8');
}

async function backfillChunk(startId) {
    const result = await pool.query(`
            SELECT id, first_name, last_name, full_name
            FROM users
            WHERE id > $1
                AND first_name IS NOT NULL
                AND last_name IS NOT NULL
                AND (full_name IS NULL OR full_name != TRIM(first_name || ' ' || last_name))
            ORDER BY id
            LIMIT $2
        `, [startId, CHUNK_SIZE]);

    if (result.rows.length === 0) {
        return null;
    }

    for (const row of result.rows) {
        // Compute full_name from first_name + last_name
        const computedFullName = row.first_name && row.last_name
            ? `${row.first_name.trim()} ${row.last_name.trim()}`.trim()
            : null;

        // Update if combined value differs from existing or null
        if (computedFullName !== row.full_name) {
            await pool.query(
                `UPDATE users SET full_name = $1 WHERE id = $2`,
                [computedFullName, row.id]
            );
        }
    }

    const lastId = result.rows[result.rows.length - 1].id;
    await saveProgress(lastId);
    return lastId;
}

async function runBackfill() {
    console.log('Starting idempotent backfill...');
    console.log(`Chunk size: ${CHUNK_SIZE}, Delay: ${DELAY_MS}ms`);

    let processed = 0;
    let lastProcessedId = await getLastProcessedId();

    console.log(`Resuming from ID > ${lastProcessedId}`);

    while (true) {
        const newLastId = await backfillChunk(lastProcessedId);

        if (newLastId === null) {
            console.log('Backfill complete');
            break;
        }

        processed += CHUNK_SIZE;
        lastProcessedId = newLastId;

        // Show progress
        const stats = await pool.query(`SELECT COUNT(*) AS total, COUNT(full_name) AS filled FROM users`);
        const { total, filled } = stats.rows[0];

        console.log(`Progress: ${filled}/${total} (${Math.round(filled / total * 100)}%)`);

        // Small delay to prevent DB hammering
        await new Promise(resolve => setTimeout(resolve, DELAY_MS));
    }

    // Final validation
    const final = await pool.query(`
        SELECT 
            COUNT(*) as total_users,
            COUNT(full_name) as users_with_full_name,
            COUNT(CASE WHEN full_name != TRIM(first_name || ' ' || last_name) THEN 1 END) as mismatches
        FROM users
        WHERE first_name IS NOT NULL AND last_name IS NOT NULL
    `);

    if (final.rows[0].mismatches > 0) {
        console.log('\nWARNING: Found mismatches between full_name and computed values');
    }

    await pool.end();
}

runBackfill().catch(err => {
    console.error('Backfill failed:', err);
    process.exit(1);
});