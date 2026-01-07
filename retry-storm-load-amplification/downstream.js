const express = require('express');
const app = express();

const PORT = process.env.DOWNSTREAM_PORT || 3001;

// Configuration behaviour
const CONCURRENCY_LIMIT = 10;
const FAST_LATENCY = 50 // ms
const SLOW_LATENCY = 1000 // ms
const ERROR_RATE = 0.01 // 1%
const SLOW_RATE = 0.05 // 5%

// Metrics
let activeRequests = 0;
let queuedRequests = 0;
let errorsTotal = 0;
let requestsTotal = 0;

// Simple semaphore for concurrency control
class Semaphore {
    constructor(max) {
        this.max = max;
        this.current = 0;
        this.queue = [];
    }

    async acquire() {
        if (this.current < this.max) {
            this.current++;
            activeRequests = this.current;
            return Promise.resolve();
        }
        queuedRequests++;
        return new Promise((resolve) => this.queue.push(resolve));
    }

    release() {
        if (this.queue.length > 0) {
            const next = this.queue.shift();
            queuedRequests--;
            next();
        } else {
            this.current--;
            activeRequests = this.current;
        }
    }
}

const semaphore = new Semaphore(CONCURRENCY_LIMIT);

app.get('/api', async (req, res) => {
    requestsTotal++;
    const start = Date.now();

    await semaphore.acquire();

    try {
        // Simulate occassional slow responses
        const isSlow = Math.random() < SLOW_RATE;
        const latency = isSlow ? SLOW_LATENCY : FAST_LATENCY;
        await new Promise((resolve) => setTimeout(resolve, latency));
        // Simulate occassional errors
        const isError = Math.random() < ERROR_RATE;
        if (isError) {
            errorsTotal++;
            res.status(500).json({ error: 'Internal server error' });
        } else {
            res.json({ success: true, latency: Date.now() - start});
        }
    } finally {
        semaphore.release();
    }
});

app.get('/metrics', (req, res) => {
    res.json({
        activeRequests,
        queuedRequests,
        errorsTotal,
        requestsTotal
    });
});

app.listen(PORT, () => {
    console.log(`Downstream service listening on port ${PORT}`);
});