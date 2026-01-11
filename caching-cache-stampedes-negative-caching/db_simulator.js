const express = require('express');

const app = express();

const PORT = 3001;

// Configuration
const DB_CONCURRENCY_LIMIT = parseInt(process.env.DB_CONCURRENCY_LIMIT || '20', 10); // Limited concurrent DB connections
const DB_LATENCY_MS = parseInt(process.env.DB_LATENCY_MS || '50', 10); // Base DB latency
const DB_ERROR_RATE = parseFloat(process.env.DB_ERROR_RATE || '0.1'); // 10% error rate when error mode is on

// Metrics
let activeRequests = 0;
let requestQueue = [];
let totalRequests = 0;
let errorMode = false;

// Semaphore for DB concurrency
class Semaphore {
    constructor(max) {
        this.max = max;
        this.current = 0;
        this.queue = [];
    }

    async acquire() {
        return new Promise((resolve) => {
            if (this.current < this.max) {
                this.current++;
                resolve();
            } else {
                this.queue.push(resolve);
            }
        });
    }

    release() {
        if (this.queue.length > 0) {
            const next = this.queue.shift();
            next();
        } else {
            this.current--;
        }
    }
}

const dbSemaphore = new Semaphore(DB_CONCURRENCY_LIMIT);

// Simulate DB work with async delay
async function simulateDBWork(key) {
    // Async sleep to simulate DB latency without blocking event loop
    await new Promise(resolve => setTimeout(resolve, DB_LATENCY_MS));

    // Simulate errors in error mode
    if (errorMode && Math.random() < DB_ERROR_RATE) {
        throw new Error('DB query failed');
    }

    return {
        id: key,
        data: `value_for_${key}`,
        timestamp: Date.now()
    }
}

app.get('/item/:id', async (req, res) => {
    totalRequests++;
    const key = req.params.id;

    // Track down queue depth before acquiring semaphore
    const queueDepth = dbSemaphore.queue.length;

    try {
        await dbSemaphore.acquire();
        activeRequests++;

        const result = await simulateDBWork(key);
        res.json(result);
    } catch (error) {
        res.status(500).json({ error: error.message });
    } finally {
        activeRequests--;
        dbSemaphore.release();
    }
});

app.get('/metrics', (req, res) => {
    res.set('Content-Type', 'text/plain');
    res.send(`
# HELP db_active Current active DB requests
# TYPE db_active gauge
db_active ${activeRequests}

# HELP db_queue Current DB queue length
# TYPE db_queue gauge
db_queue ${dbSemaphore.queue.length}

# HELP db_requests Total DB requests
# TYPE db_requests counter
db_requests ${totalRequests}
`);
});

app.post('/error_mode', (req, res) => {
    errorMode = req.query.enable === 'true';
    res.json({ errorMode });
});

if (require.main === module) {
    app.listen(PORT, () => {
        console.log(`DB simulator running on http://localhost:${PORT}`);
    });
}

module.exports = { app, dbSemaphore, activeRequests };