const express = require('express');
const { Worker, isMainThread, parentPort } = require('worker_threads');
const { Tracer } = require('./instrumentation');
const { resolve } = require('path');

const app = express();
app.use(express.json());

const tracer = new Tracer('service_a', 'http://localhost:9411');
const port = 3000;

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

function createWorkerTask(data, parentContext) {
    return new Promise((resolve, reject) => {
        const worker = new Worker(__filename, {
            workerData: { data, context: parentContext }
        });

        worker.on('message', resolve);
        worker.on('error', reject);
        worker.on('exit', (code) => {
            if (code !== 0) reject(new Error(`Worker stopped with exit code ${code}`));
        });
    });
}

app.get('/work', async (req, res) => {
    const start = Date.now();
    activeRequests++;

    const span = tracer.startSpan('handle_api_request');

    // Simulate API processing
    await new Promise(resolve => setTimeout(resolve, 5));

    // Call service B
    try {
        await tracer.instrumentHTTPCall(
            'http://localhost:3001/work',
            { method: 'POST', body: JSON.stringify({}) },
            'call_service_b',
            span
        );
    } catch (error) {
        await span.finish({ error: error.message });
        requestCount++;
        activeRequests--;
        recordLatency(start);
        return res.status(500).json({ error: 'Service B failure' });
    }

    // Simulate external API call
    const externalCall = tracer.instrumentAsync(
        async () => {
            await new Promise(resolve => setTimeout(resolve, 20));
            return { external: 'ok' };
        },
        'call_external_api',
        span.context
    );

    await externalCall();

    // Optional: start worker thread with trace context
    if (Math.random() < 0.3) {
        await createWorkerTask({ task: 'background' }, span.context);
    }

    await span.finish();

    requestCount++;
    activeRequests--;
    recordLatency(start);

    res.json({ status: 'complete', trace_id: span.context.traceId });
});

app.get('/trace/:traceId', async (req, res) => {
    const traceId = req.params.traceId;
    try {
        const response = await fetch(`http://localhost:9411/trace/${traceId}`);
        const spans = await response.json();
        res.json(spans);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
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

// Worker thread logic
if (!isMainThread) {
    const { Tracer } = require('./instrumentation');
    const tracer = new Tracer('service_a_worker', 'http://localhost:9411');

    // Extract context from parent
    const parentContext = require('worker_threads').workerData.context;
    const span = tracer.startSpan('worker_background_task', parentContext);

    // Simulate background work
    setTimeout(async () => {
        await span.finish({ worker_result: 'processed' });
        parentPort.postMessage({ status: 'done' });
    }, 50);
} else if (require.main === module) {
    app.listen(port, () => {
        console.log(`Service A listening on http://localhost:${port}`);
    });
}

module.exports = { app, tracer };