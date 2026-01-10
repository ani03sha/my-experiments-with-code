const express = require('express');
const fetch = require('node-fetch');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 8081;

const INSTANCE_ID = process.env.INSTANCE_ID || `instance-${PORT}`;
const DB_URL = process.env.DB_URL || 'http://localhost:8083';
const POOL_SIZE = parseInt(process.env.POOL_SIZE || '50');
const DEGRADE_MODE = process.env.DEGRADE_MODE === '1';
const CHAOS_MODE = process.env.CHAOS_MODE || 'none'; // 'none', 'latency', 'error'

// Metrics
let activeRequests = 0;
let queueLength = 0;
let errors = 0;
let shedCount = 0;

// Chaos parameters
let chaosLatencyMs = 0;
let chaosErrorRate = 0;

// Blocking sleep function (only for chaos latency injection)
function blockSleep(ms) {
    const start = Date.now();
    while (Date.now() - start < ms) {
        // busy loop - intentionally blocks for chaos simulation
    }
}

// Non-blocking sleep for normal processing
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}


// Simulate work
async function handleWork(req, res) {
    // Check pool limit BEFORE incrementing
    if (activeRequests >= POOL_SIZE) {
        queueLength++;
        // Shed request if degrade mode enabled OR over capacity
        if (DEGRADE_MODE || activeRequests >= POOL_SIZE * 2) {
            shedCount++;
            return res.status(503).send('Service degraded - over capacity');
        }
    }

    activeRequests++;

    // Apply chaos latency if enabled (dynamically set via /chaos endpoint)
    // Use async sleep to avoid blocking the event loop and causing connection failures
    if (chaosLatencyMs > 0) {
        await sleep(chaosLatencyMs);
    }

    // Apply chaos error if enabled (dynamically set via /chaos endpoint)
    if (chaosErrorRate > 0 && Math.random() < chaosErrorRate) {
        errors++;
        activeRequests--;
        return res.status(500).send('Chaos error injected');
    }

    // Call DB simulator if not degraded
    let dbResponse;
    try {
        dbResponse = await fetch(DB_URL + '/query');
        if (!dbResponse.ok) {
            throw new Error('DB error');
        }
    } catch (err) {
        errors++;
        activeRequests--;
        return res.status(502).send('DB unavailable');
    }

    // Simulate minimal CPU processing (non-blocking)
    await sleep(2);

    activeRequests--;
    res.send({ instance: INSTANCE_ID, db: 'ok', timestamp: new Date().toISOString() });
}

app.get('/work', (req, res) => {
    handleWork(req, res);
});

// Chaos control endpoint
app.post('/chaos', (req, res) => {
    const { type, latency, duration, rate } = req.body;
    if (type === 'latency') {
        chaosLatencyMs = latency || 200;
        console.log(`[${new Date().toISOString()}] ${INSTANCE_ID} latency chaos enabled: ${chaosLatencyMs}ms for ${duration || 'indefinite'}ms`);
        // Reset after duration
        if (duration) {
            setTimeout(() => {
                chaosLatencyMs = 0;
                console.log(`[${new Date().toISOString()}] ${INSTANCE_ID} latency chaos disabled`);
            }, duration);
        }
    } else if (type === 'error') {
        chaosErrorRate = rate || 0.5;
        console.log(`[${new Date().toISOString()}] ${INSTANCE_ID} error chaos enabled: rate ${chaosErrorRate} for ${duration || 'indefinite'}ms`);
        if (duration) {
            setTimeout(() => {
                chaosErrorRate = 0;
                console.log(`[${new Date().toISOString()}] ${INSTANCE_ID} error chaos disabled`);
            }, duration);
        }
    } else if (type === 'none') {
        chaosLatencyMs = 0;
        chaosErrorRate = 0;
        console.log(`[${new Date().toISOString()}] ${INSTANCE_ID} chaos disabled`);
    }
    res.send('OK');
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    res.set('Content-Type', 'text/plain');
    res.send(`
# HELP api_active Number of active requests.
# TYPE api_active gauge
api_active{instance="${INSTANCE_ID}"} ${activeRequests}
# HELP api_queue Queue length.
# TYPE api_queue gauge
api_queue{instance="${INSTANCE_ID}"} ${queueLength}
# HELP api_errors Total errors.
# TYPE api_errors counter
api_errors{instance="${INSTANCE_ID}"} ${errors}
# HELP api_shed_count Shedded requests count.
# TYPE api_shed_count counter
api_shed_count{instance="${INSTANCE_ID}"} ${shedCount}
`);
});

app.listen(PORT, () => {
    console.log(`[${new Date().toISOString()}] API instance ${INSTANCE_ID} listening on port ${PORT}`);
});