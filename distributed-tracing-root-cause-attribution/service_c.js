const express = require('express');
const { Tracer } = require('./instrumentation');

const app = express();
app.use(express.json());

const tracer = new Tracer('service_c', 'http://localhost:9411');
const port = 3002;

let requestCount = 0;
let activeRequests = 0;
const latencies = [];

function recordLatency(start) {
    const latency = Date.now() - start;
    latencies.push(latency);
    if (latencies.length > 1000) {
        latencies.shift();
    }
}

function calculatePercentiles() {
    const sorted = [...latencies].sort((a, b) => a - b);
    return {
        p50: sorted[Math.floor(sorted.length * 0.5)],
        p95: sorted[Math.floor(sorted.length * 0.95)],
        p99: sorted[Math.floor(sorted.length * 0.99)]
    }
}

app.post('/work', async (req, res) => {
    const start = Date.now();
    activeRequests++;

    const parentContext = tracer.extractHeaders(req.headers);
    const span = tracer.startSpan('db_query', parentContext, {
        db_operation: 'SELECT',
        db_table: 'users'
    });

    // Simulate DB work with variable latency
    let dbTime = 5 + Math.random() * 50; // 5-55ms
    if (Math.random() < 0.01) {
        dbTime += 200; // 1% tail latency
    }

    await new Promise(resolve => setTimeout(resolve, dbTime));

    await span.finish({ db_time_ms: dbTime, rows_returned: 42 });

    requestCount++;
    activeRequests--;
    recordLatency(start);

    res.json({ status: 'ok', db_time: dbTime });
});

app.get('/metrics', (req, res) => {
    const percentiles = calculatePercentiles();
    res.json({
        request_count: requestCount,
        active_request: activeRequests,
        latencies: percentiles
    });
});

app.get('/health', (req, res) => {
    res.send('OK');
});

app.use((req, res) => {
    res.status(404).send('Not found');
});

if (require.main === module) {
    app.listen(port, () => {
        console.log(`Service C (DB) listening on http://localhost:${port}`);
    });
}

module.exports = { app, tracer };