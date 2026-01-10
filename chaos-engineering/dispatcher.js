const express = require('express');
const fetch = require('node-fetch');

const app = express();
app.use(express.json());

// List of API instance URLs
let instances = process.env.INSTANCES ? process.env.INSTANCES.split(',') : [
    'http://localhost:8081',
    'http://localhost:8082'
];
let roundRobinIndex = 0;

// Metrics
let activeInstances = instances.length;
let totalLatency = 0;
let requestCount = 0;

// Register new instance
app.post('/register', (req, res) => {
    const { url } = req.body;
    if (!url) {
        return res.status(400).send('Missing URL');
    }
    if (!instances.includes(url)) {
        instances.push(url);
        activeInstances = instances.length;
        console.log(`[${new Date().toISOString()}] Registered instance ${url}`);
    }
    res.send('ok');
});

// Unregister instance
app.post('/unregister', (req, res) => {
    const { url } = req.body;
    instances = instances.filter(i => i !== url);
    activeInstances = instances.length;
    console.log(`[${new Date().toISOString()}] Unregistered instance ${url}`);
    res.send('OK');
});

// Forward request to next instance
app.all('/work', async (req, res) => {
    if (instances.length === 0) {
        return res.status(503).send('No instances available');
    }
    const target = instances[roundRobinIndex];
    roundRobinIndex = (roundRobinIndex + 1) % instances.length;

    const start = Date.now();
    try {
        const response = await fetch(target + '/work', {
            method: req.method,
            headers: req.headers,
            body: req.method !== 'GET' && req.body ? JSON.stringify(req.body) : undefined
        });
        const latency = Date.now() - start;
        totalLatency += latency;
        requestCount++;
        // Forward status and headers
        res.status(response.status);
        response.headers.forEach((value, name) => res.setHeader(name, value));
        const text = await response.text();
        res.send(text);
    } catch (err) {
        const latency = Date.now() - start;
        totalLatency += latency;
        requestCount++;
        console.error(`[${new Date().toISOString()}] Error forwarding to ${target}:`, err.message);
        res.status(502).send('Bad Gateway');
    }
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    const avgLatency = requestCount > 0 ? totalLatency / requestCount : 0;
    res.set('Content-Type', 'text/plain');
    res.send(`
# HELP dispatcher_active_instances Number of active API instances.
# TYPE dispatcher_active_instances gauge
dispatcher_active_instances ${activeInstances}
# HELP dispatcher_avg_latency_estimate Average latency estimate in milliseconds.
# TYPE dispatcher_avg_latency_estimate gauge
dispatcher_avg_latency_estimate ${avgLatency}
`);
});

const PORT = process.env.PORT || 8080;

app.listen(PORT, () => {
    console.log(`[${new Date().toISOString()}] Dispatcher listening on port ${PORT}`);
});