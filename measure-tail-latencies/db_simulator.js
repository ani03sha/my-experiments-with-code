const express = require('express');
const { Worker, isMainThread, parentPort } = require('worker_threads');

const app = express();
const MAX_CONNECTIONS = parseInt(process.env.DB_CONNECTIONS || '5');
const WORK_MS = 2000; // Fixed 100ms CPU work

let active = 0;

// CPU bound work function (blocks event loop)
function cpuWork(ms) {
    const start = Date.now();
    while (Date.now - start < ms) {
        // Busy waiting
    }
}

app.get('/db', async (req, res) => {
    if (active >= MAX_CONNECTIONS) {
        return res.status(503).json({ error: 'DB saturated' });
    }

    active++;

    cpuWork(WORK_MS);

    active--;

    res.json({
        ok: true,
        work: WORK_MS
    });
});

app.get('/metrics', (req, res) => {
    res.send(`db_active ${active}\n`);
});

app.listen(5001);