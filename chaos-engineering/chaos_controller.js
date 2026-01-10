const express = require('express');
const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(express.json());

const SCHEDULE_FILE = process.env.SCHEDULE_FILE || './chaos_schedule.json';
const BLAST_RADIUS = parseFloat(process.env.BLAST_RADIUS || '1.0');

let chaosActive = false;
let schedule = [];

function loadSchedule() {
    try {
        const filePath = path.resolve(SCHEDULE_FILE);
        const fileContent = fs.readFileSync(filePath, 'utf8');
        schedule = JSON.parse(fileContent);
        console.log(`[${new Date().toISOString()}] Loaded schedule from ${filePath}: ${schedule.length} items`);
    } catch (err) {
        console.log(`[${new Date().toISOString()}] No schedule file found or error loading: ${err.message}`);
        schedule = [];
    }
}

async function injectChaos(type, target, latency, duration, rate) {
    const instances = target === 'all'
        ? ['http://localhost:8081', 'http://localhost:8082']
        : [target];
    for (const instance of instances) {
        try {
            await fetch(`${instance}/chaos`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ type, latency, duration, rate })
            });
            console.log(`[${new Date().toISOString()}] Injected ${type} into ${instance} (latency=${latency}ms, duration=${duration}ms, rate=${rate})`);
        } catch (err) {
            console.error(`[${new Date().toISOString()}] Failed to inject ${type} into ${instance}:`, err.message);
        }
    }
}

function startSchedule() {
    chaosActive = true;
    console.log(`[${new Date().toISOString()}] Starting chaos schedule with ${schedule.length} items`);
    schedule.forEach((item, idx) => {
        console.log(`[${new Date().toISOString()}] Scheduled ${item.type} chaos for T+${item.time}s on ${item.target}`);
        setTimeout(() => {
            if (!chaosActive) {
                console.log(`[${new Date().toISOString()}] Chaos is inactive, skipping scheduled item`);
                return;
            }
            console.log(`[${new Date().toISOString()}] Executing scheduled chaos: ${item.type}`);
            injectChaos(item.type, item.target, item.latency, item.duration, item.rate);
        }, item.time * 1000);
    });
}

// Endpoints
app.post('/inject/:type', express.json(), async (req, res) => {
    const { type } = req.params;
    const { target, latency, duration, rate } = req.body;
    await injectChaos(type, target, latency, duration, rate);
    res.send('OK');
});

app.post('/panic', (req, res) => {
    chaosActive = false;
    // Disable chaos on all instances
    injectChaos('none', 'all', 0, 0, 0);
    console.log(`[${new Date().toISOString()}] Chaos panic - all chaos disabled`);
    res.send('OK');
});

app.get('/health', (req, res) => {
    res.json({ chaosActive, schedule });
});

const PORT = process.env.PORT || 8084;

app.listen(PORT, () => {
    console.log(`[${new Date().toISOString()}] Chaos controller listening on port ${PORT}`);

    // Load schedule and start after server is ready
    loadSchedule();
    if (schedule.length > 0) {
        startSchedule();
    } else {
        console.log(`[${new Date().toISOString()}] No schedule loaded, waiting for manual injection`);
    }
});