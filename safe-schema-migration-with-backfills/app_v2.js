// App version with dual write
const express = require('express');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
app.use(express.json());

const pool = new Pool({
    host: 'localhost',
    database: 'migration_demo',
    user: process.env.PGUSER || 'postgres',
    password: process.env.PGPASSWORD || 'postgres',
    port: 5432
});

// Configuration dual write mode
const DUAL_WRITE = process.env.DUAL_WRITE === '1';

// Helper to compute full_name
const computeFullName = (first, last) => first && last ? `${first.trim()} ${last.trim()}`.trim() : null;

// V2 endpoints
app.get('/v2/user/:id', async (req, res) => {
    try {
        const result = await pool.query(
            'SELECT id, email, full_name, created_at FROM users WHERE id = $1', [req.params.id]
        );
        res.json(result.rows[0] || { error: 'User not found' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/v2/user', async (req, res) => {
    try {
        const { email, full_name } = req.body;

        // Parse first/last from full_name for dual-write
        let first_name, last_name;
        if (full_name) {
            const parts = full_name.split(' ');
            first_name = parts[0] || null;
            last_name = parts[1] || null;
        }

        // Dual write - write to both old and new columns
        if (DUAL_WRITE) {
            const result = await pool.query(
                `INSERT INTO users (email, full_name, first_name, last_name)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (email)
                DO UPDATE SET
                    full_name = EXCLUDED.full_name,
                    first_name = EXCLUDED.first_name,
                    last_name = EXCLUDED.last_name
                RETURNING id`,
                [email, full_name, first_name, last_name]
            );
            res.json({ id: result.rows[0].id, mode: 'dual-write' });
        } else {
            // Write only to new column (after contraction)
            const result = await pool.query(
                `INSERT INTO users (email, full_name)
                VALUES ($1, $2)
                ON CONFLICT (email)
                DO UPDATE SET
                    full_name = EXCLUDED.full_name
                RETURNING id`,
                [email, full_name]
            );
            res.json({ id: result.rows[0].id, mode: 'v2-only' });
        }
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/v2/stats', async (req, res) => {
    const stats = await pool.query(`
            SELECT 
                COUNT(*) AS total_users,
                COUNT(full_name) AS users_with_full_name,
                COUNT(first_name) AS users_with_first_name,
                COUNT(last_name) AS users_with_last_name,
                SUM(CASE WHEN full_name IS NOT NULL AND first_name is NULL THEN 1 ELSE 0 END) AS v2_only_users
            FROM users
        `);
    res.json(stats.rows[0]);
});

const PORT = process.env.V2_PORT || 3001;
app.listen(PORT, () => {
    console.log(`V2 app running on http://localhost:${PORT}/v2`);
    console.log(`Dual-write mode: ${DUAL_WRITE ? 'ENABLED' : 'DISABLED'}`);
});