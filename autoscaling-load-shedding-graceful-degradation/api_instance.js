const express = require('express');
const { request } = require('http');
const { Worker, isMainThread } = require('worker_threads');

// Configurations from environment
const PORT = process.env.PORT || 3000;
const POOL_SIZE = parseInt(process.env.POOL_SIZE || '4');
const SHED_THRESHOLD = parseInt(process.env.SHED_THRESHOLD || '10');
const DEGRADE_MODE = process.env.DEGRADE_MODE === '1';
const INSTANCE_ID = process.env.INSTANCE_ID || 'default';


// Metrics
let metrics = {
    instance_id: INSTANCE_ID,
    api_active: 0,
    api_queue: 0,
    api_shed_count: 0,
    api_degraded_count: 0,
    request_durations: [],
    total_requests: 0,
    successful_requests: 0
};

// Worker pool simulation
class WorkerPool {
    constructor(size) {
        this.size = size;
        this.activeWorkers = 0;
        this.queue = [];
    }

    async executeWork() {
        // Simulate CPU-intensive work (more realistic than simple loop)
        const start = Date.now();
        let result = 0;

        // Do actual CPU work (calculate Fibonacci of a moderate number)
        function fibonacci(n) {
            if (n <= 1) return n;
            return fibonacci(n - 1) + fibonacci(n - 2);
        }

        // Vary workload slightly
        const fibN = 25 + Math.floor(Math.random() * 5);
        result = fibonacci(fibN);

        // Simulate DB call (80% fast, 20% slow)
        const dbTime = Math.random() < 0.8 ? 5 : 100;
        await new Promise(resolve => setTimeout(resolve, dbTime));

        const totalTime = Date.now() - start;

        return {
            result: result % 1000, // Keep result small
            dbTime,
            computeTime: totalTime - dbTime
        };
    }

    async process(requestId) {
        // Check if need to queue
        if (this.activeWorkers >= this.size) {
            return new Promise((resolve) => {
                this.queue.push({ requestId, resolve });
                metrics.api_queue = this.queue.length;
            });
        }

        this.activeWorkers++;
        metrics.api_active = this.activeWorkers;

        try {
            const result = await this.executeWork();
            return result;
        } finally {
            this.activeWorkers--;
            metrics.api_active = this.activeWorkers;

            // Process next in queue if any
            if (this.queue.length > 0) {
                const next = this.queue.shift();
                metrics.api_queue = this.queue.length;
                // Process asynchronously to avoid deep recursion
                setImmediate(() => this.process(next.requestId).then(next.resolve));
            }
        }
    }
}

const workerPool = new WorkerPool(POOL_SIZE);
const app = express();
app.use(express.json());

// Calculate percentile helper
function calculatePercentile(arr, percentile) {
    if (arr.length === 0) {
        return 0;
    }
    const sorted = [...arr].sort((a, b) => a - b);
    const index = Math.ceil(percentile / 100 * sorted.length) - 1;
    return sorted[Math.max(0, index)];
}

// Metrics
app.get('/metrics', (req, res) => {
    const response = {
        ...metrics,
        p50_estimate: calculatePercentile(metrics.request_durations, 50),
        p95_estimate: calculatePercentile(metrics.request_durations, 95),
        p99_estimate: calculatePercentile(metrics.request_durations, 99),
        pool_size: POOL_SIZE,
        shed_threshold: SHED_THRESHOLD,
        degrade_mode: DEGRADE_MODE,
        timestamp: Date.now()
    };

    res.json(response);
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        instance: INSTANCE_ID,
        port: PORT,
        queue: workerPool.queue.length,
        active: workerPool.activeWorkers
    });
});

// Work endpoint with load shedding
app.get('/work', async (req, res) => {
    const startTime = Date.now();
    const requestId = metrics.total_requests++;

    // Update metrics
    metrics.api_active = workerPool.activeWorkers;
    metrics.api_queue = workerPool.queue.length;

    // Load shedding check
    if (workerPool.queue.length > SHED_THRESHOLD) {
        metrics.api_shed_count++;

        if (DEGRADE_MODE) {
            // Graceful degradation: return cached/partial response
            metrics.api_degraded_count++;
            const duration = Date.now() - startTime;
            metrics.request_durations.push(duration);

            // Keep only last 1000 durations
            if (metrics.request_durations.length > 1000) {
                metrics.request_durations = metrics.request_durations.slice(-1000);
            }

            return res.json({
                status: 'degraded',
                cached_data: true,
                message: 'Returning cached response due to high load',
                instance: INSTANCE_ID,
                queue_depth: workerPool.queue.length,
                duration
            });
        } else {
            // Straight rejection
            const duration = Date.now() - startTime;
            return res.status(503).json({
                error: 'Service overloaded',
                shed: true,
                instance: INSTANCE_ID,
                queue_depth: workerPool.queue.length,
                duration
            });
        }
    }

    try {
        const result = await workerPool.process(requestId);
        metrics.successful_requests++;
        const duration = Date.now() - startTime;
        metrics.request_durations.push(duration);

        // Keep only last 1000 durations
        if (metrics.request_durations.length > 1000) {
            metrics.request_durations = metrics.request_durations.slice(-1000);
        }

        res.json({
            status: 'success',
            result: result.result,
            db_time: result.dbTime,
            compute_time: result.computeTime,
            instance: INSTANCE_ID,
            active_workers: workerPool.activeWorkers,
            queue_length: workerPool.queue.length,
            duration
        });
    } catch (error) {
        const duration = Date.now() - startTime;
        res.status(500).json({
            error: 'Processing failed',
            instance: INSTANCE_ID,
            message: error.message,
            duration
        });
    }
});

// Degraded endpoint (simplified response)
app.get('/degraded', (req, res) => {
    res.json({
        status: 'degraded',
        data: { cached: true, timestamp: Date.now() },
        message: 'This is a degraded response',
        instance: INSTANCE_ID
    });
});

// Start server
const server = app.listen(PORT, () => {
    console.log(`API instance ${INSTANCE_ID} listening on port ${PORT}`);
    console.log(`  Pool size: ${POOL_SIZE}, Shed threshold: ${SHED_THRESHOLD}`);
    console.log(`  Degrade mode: ${DEGRADE_MODE ? 'ON' : 'OFF'}`);
    console.log(`  Health: http://localhost:${PORT}/health`);
    console.log(`  Metrics: http://localhost:${PORT}/metrics`);
});

// Clean shutdown
function shutdown() {
    console.log(`\nInstance ${INSTANCE_ID} shutting down gracefully...`);
    server.close(() => {
        console.log(`Instance ${INSTANCE_ID} closed`);
        process.exit(0);
    });

    // Force shutdown after 5 seconds
    setTimeout(() => {
        console.log(`Instance ${INSTANCE_ID} forced shutdown`);
        process.exit(1);
    }, 5000);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

// Export for testing
module.exports = app;