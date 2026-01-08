const express = require('express');

const PORT = process.env.DB_PORT || 3001;
let mode = 'fast'; // 'fast' or 'slow'

const app = express();
app.use(express.json());

// Metrics endpoint
app.get('/metrics', (req, res) => {
    res.json({
        db_mode: mode,
        db_port: PORT,
        timestamp: Date.now(),
        uptime: process.uptime()
    });
});

// Mode control endpoint
app.post('/mode', (req, res) => {
    const { mode: newMode } = req.body;
    if (newMode === 'fast' || newMode === 'slow') {
        mode = newMode;
        res.json({ success: true, mode, message: `DB mode changed to ${mode}` });
    } else {
        res.status(400).json({ error: 'Invalid mode. Use "fast" or "slow"' });
    }
});

// Query endpoint (simulates DB work)
app.get('/query', (req, res) => {
    const queryTime = mode === 'fast' ? 5 : 100; // ms
    const start = Date.now();

    // Simulate some CPU work for the query
    let result = 0;
    const iterations = mode === 'fast' ? 1000 : 10000;
    for (let i = 0; i < iterations; i++) {
        result += Math.sqrt(i) * Math.random();
    }

    setTimeout(() => {
        res.json({
            db_result: 'success',
            mode,
            query_time: queryTime,
            compute_time: Date.now() - start - queryTime,
            data_size: 100,
            sample_data: Array.from({ length: 5 }, (_, i) => ({
                id: i,
                value: Math.random(),
                timestamp: Date.now()
            }))
        });
    }, queryTime);
});

// Health check
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        service: 'db_sim',
        mode,
        port: PORT
    });
});

// Start server
const server = app.listen(PORT, () => {
    console.log(`DB simulator listening on port ${PORT}`);
    console.log(`  Mode: ${mode}`);
    console.log(`  Health: http://localhost:${PORT}/health`);
    console.log(`  Change mode: POST http://localhost:${PORT}/mode { "mode": "slow" }`);
});

// Graceful shutdown
function shutdown() {
    console.log(`DB simulator on port ${PORT} shutting down...`);
    server.close(() => {
        console.log(`DB simulator on port ${PORT} closed`);
        process.exit(0);
    });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);