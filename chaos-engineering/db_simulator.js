const express = require('express');
const app = express();

let requestCount = 0;

app.get('/query', (req, res) => {
    requestCount++;
    // Simulate very low latency (sub-millisecond, like in-memory cache)
    res.json({ db: 'ok', count: requestCount });
});

app.get('/metrics', (req, res) => {
    res.set('Content-Type', 'text/plain');
    res.send(`
# HELP db_requests Total DB requests.
# TYPE db_requests counter
db_requests ${requestCount}
`);
});

const PORT = process.env.PORT || 8083;

app.listen(PORT, () => {
    console.log(`[${new Date().toISOString()}] DB simulator listening on port ${PORT}`);
});