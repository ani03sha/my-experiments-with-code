const express = require('express');
const { Tracer } = require('./instrumentation');

const app = express();
app.use(express.json());

const tracer = new Tracer('service_b', 'http://localhost:9411');
const port = 3001;

let requestCount = 0;
let activeRequests = 0;
const latencies = [];

function recordLatency(start) {
    const latency = Date.now() - start;
    latencies.push(latency);
    if (latencies.length > 1000) latencies.shift();
}

function calculatePercentiles() {
    const sorted = [...latencies].sort((a, b) => a - b);
    return {
        p50: sorted[Math.floor(sorted.length * 0.5)],
        p95: sorted[Math.floor(sorted.length * 0.95)],
        p99: sorted[Math.floor(sorted.length * 0.99)]
    };
}

app.post('/work', async (req, res) => {
    const start = Date.now();
    activeRequests++;

    const parentContext = tracer.extractHeaders(req.headers);
    const span = tracer.startSpan('process_business_logic', parentContext);

    // Simulate CPU work (non-blocking to allow concurrency)
    const workTime = 10 + Math.random() * 30; // 10-40ms
    await new Promise(resolve => setTimeout(resolve, workTime));

    // Call service C
    try {
        await tracer.instrumentHTTPCall(
            'http://localhost:3002/work',
            { method: 'POST' },
            'call_service_c',
            span
        );
    } catch (error) {
        span.finish({ error: error.message });
        requestCount++;
        activeRequests--;
        recordLatency(start);
        return res.status(500).json({ error: 'Downstream failure' });
    }

    span.finish({ processing_time_ms: workTime });

    requestCount++;
    activeRequests--;
    recordLatency(start);

    res.json({ status: 'processed' });
});

app.get('/metrics', (req, res) => {
    const percentiles = calculatePercentiles();
    res.json({
        request_count: requestCount,
        active_requests: activeRequests,
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
        console.log(`Service B listening on http://localhost:${port}`);
    });
}

module.exports = { app, tracer };