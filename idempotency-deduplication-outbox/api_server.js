const express = require('express');
const { initDB } = require('./db.js');
const crypto = require('crypto');

const app = express();
app.use(express.json());

let db, metrics = {
    requests_received: 0,
    requests_enqueued: 0,
    duplicate_detected: 0,
    outbox_entries: 0
};

async function startServer() {
    db = await initDB();
    const MODE = process.env.MODE || 'naive';

    app.post('/charge', async (req, res) => {
        metrics.requests_received++;
        const idempotencyKey = req.headers['idempotency-key'];
        const amount = req.body.amount;

        if (MODE === 'idempotent_key' || MODE === 'outbox') {
            if (!idempotencyKey) {
                return res.status(400).json({ error: 'Idempotency-Key header required' });
            }
            const requestHash = crypto.createHash('sha256').update(JSON.stringify(req.body)).digest('hex');
            const existing = await db.get('SELECT * FROM idempotency_keys WHERE key = ?', [idempotencyKey]);
            if (existing) {
                if (existing.request_hash !== requestHash) {
                    return res.status(409).json({ error: 'Key reused with different payload' });
                }
                metrics.duplicate_detected++;
                const charge = await db.get('SELECT * FROM charges WHERE id = ?', [existing.charge_id]);
                return res.json({ idempotency_replay: true, charge });
            }
        }

        let chargeId;
        try {
            if (MODE === 'outbox') {
                await db.run('BEGIN TRANSACTION');
                const result = await db.run('INSERT INTO charges (amount) VALUES (?)', [amount]);
                chargeId = result.lastID;
                await db.run('INSERT INTO outbox (charge_id) VALUES (?)', [chargeId]);
                await db.run('INSERT INTO idempotency_keys (key, charge_id, request_hash) VALUES (?, ?, ?)',
                    [idempotencyKey, chargeId, crypto.createHash('sha256').update(JSON.stringify(req.body)).digest('hex')]
                );
                await db.run('COMMIT');
                metrics.outbox_entries++;
                metrics.requests_enqueued++;
                res.json({ message: 'Charge enqueued via outbox', chargeId });
            } else {
                // Naive or idempotent_key without dedup
                const result = await db.run('INSERT INTO charges (amount) VALUES (?)', [amount]);
                chargeId = result.lastID;
                if (MODE === 'idempotent_key') {
                    await db.run('INSERT INTO idempotency_keys (key, charge_id, request_hash) VALUES (?, ?, ?)',
                        [idempotencyKey, chargeId, crypto.createHash('sha256').update(JSON.stringify(req.body)).digest('hex')]
                    );
                }
                // Simulate direct enqueue
                require('fs').appendFileSync('queue.txt', `${chargeId},${amount}\n`);
                metrics.requests_enqueued++;
                res.json({ message: 'Charge processed directly', chargeId });
            }
        } catch (error) {
            if (MODE === 'outbox') {
                await db.run('ROLLBACK');
            }
            res.status(500).json({ error: error.message });
        }
    });

    app.get('/metrics', (req, res) => res.json(metrics));

    app.listen(3000, () => console.log(`API running in ${MODE} mode on port 3000`));
}

startServer();