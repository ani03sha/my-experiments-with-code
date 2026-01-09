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

// V1 endpoints, use first_name and last_name
app.get('/v1/user/:id', async (req, res) => {
    try {
        const result = await pool.query(
            'SELECT id, email, first_name, last_name, created_at FROM users WHERE id = $1', [req.params.id]
        );
        res.json(result.rows[0] || { error: 'User not found' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/v1/user', async (req, res) => {
    try {
        const { email, first_name, last_name } = req.body;
        const result = await pool.query(
            `INSERT INTO users (email, first_name, last_name) 
             VALUES ($1, $2, $3) 
             ON CONFLICT (email) 
             DO UPDATE SET first_name = EXCLUDED.first_name, last_name = EXCLUDED.last_name
             RETURNING id`,
            [email, first_name, last_name]
        );
        res.json({ id: result.rows[0].id });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/v1/before_stats', async (req, res) => {
    const stats = await pool.query(`
            SELECT
                COUNT(*) as total_users
            FROM users
        `);
    res.json(stats.rows[0]);
});

app.get('/v1/after_stats', async (req, res) => {
    const stats = await pool.query(`
            SELECT
                COUNT(*) as total_users,
                COUNT(full_name) as users_with_full_name,
                COUNT(*) - COUNT(full_name) as users_missing_full_name
            FROM users
        `);
    res.json(stats.rows[0]);
});

const PORT = process.env.V1_PORT || 3000;
app.listen(PORT, () => {
    console.log(`V1 app running on http://localhost:${PORT}/v1`);
});